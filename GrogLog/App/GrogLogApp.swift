import GRDBQuery
import SwiftUI

@main
struct GrogLogApp: App {
    /// Debug builds can swap to a throwaway in-memory database of sample data; the real log is never touched.
    @AppStorage("demoMode") private var demoMode = false
    @State private var real = Store.real
    @State private var demo: Store?

    /// The real log's setting, whichever log is on screen.
    private var syncing: Bool { (try? real.get())?.prefs.syncsWithICloud ?? false }

    var body: some Scene {
        WindowGroup {
            Group {
                switch demoMode ? demo.map({ .success($0) }) ?? real : real {
                case .success(let store):
                    RootView()
                        .id(store.id)
                        .environment(store.prefs)
                        .databaseContext(.readWrite { store.database.writer })
                case .failure(let error):
                    ContentUnavailableView(
                        "The log could not be opened",
                        systemImage: "exclamationmark.triangle",
                        description: Text("Nothing has been changed. Close GrogLog fully and open it again. If this keeps happening, the reason is: \(error.localizedDescription)")
                    )
                }
            }
            .tint(.grog)
            .onChange(of: syncing, initial: true) { _, on in
                if on {
                    Sync.shared?.start()
                    SettingsSync.shared?.start()
                } else {
                    Sync.shared?.stop()
                    SettingsSync.shared?.stop()
                }
            }
            .onChange(of: demoMode, initial: true) {
                #if DEBUG
                if demoMode, demo == nil { demo = .demo() }
                #endif
            }
        }
    }
}

struct RootView: View {
    @Environment(Prefs.self) private var prefs
    @Environment(\.databaseContext) private var database
    @Environment(\.scenePhase) private var scenePhase
    /// Opens on Log; `-tab <name>` picks another, for screenshots.
    @State private var tab = UserDefaults.standard.string(forKey: "tab") ?? "log"
    @State private var calendarReselects = 0
    @State private var dayReselects = 0

    var body: some View {
        let today = prefs.clock.today
        // Tapping the selected tab again is the system's scroll-to-top, but the calendar's top is its oldest month.
        let selection = Binding(get: { tab }, set: {
            if $0 == tab, $0 == "calendar" { calendarReselects += 1 }
            if $0 == tab, $0 == "day" { dayReselects += 1 }
            tab = $0
        })
        TabView(selection: selection) {
            Tab("Log", systemImage: "plus.circle", value: "log") {
                NavigationStack { LedgerReader { LogScreen(ledger: $0) } }
            }
            Tab("Calendar", systemImage: "calendar", value: "calendar") {
                NavigationStack { LedgerReader { CalendarScreen(ledger: $0, reselects: calendarReselects) } }
            }
            Tab("Day", systemImage: "chart.line.uptrend.xyaxis", value: "day") {
                // `-dayOffset 1` opens on yesterday, for screenshots of a finished day.
                NavigationStack { DayPager(day: today - UserDefaults.standard.integer(forKey: "dayOffset"), reselects: dayReselects).id(today) }
            }
            Tab("Reports", systemImage: "chart.bar.xaxis", value: "reports") {
                NavigationStack { LedgerReader { ReportsScreen(ledger: $0) } }
            }
            Tab("Setup", systemImage: "slider.horizontal.3", value: "setup") {
                NavigationStack { LedgerReader { SetupScreen(ledger: $0) } }
            }
        }
        // Reading scenePhase re-evaluates `today` when the app returns on a later day, and picks up drinks the widget
        // logged in the meantime: observations only see writes made through this process, and the widget runs in
        // another. A widget can only be tapped with the app in the background, so returning to the foreground is the
        // moment to check. The database is notified that its region changed instead of being written to, since the
        // drink is already stored and only the screens are out of date.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, let writer = try? database.writer else { return }
            try? writer.write { try $0.notifyChanges(in: .fullDatabase) }
            if let sync = Sync.shared { Task.detached { sync.queuePending() } }
            // A widget's tap logs in the widget's process, which has no Health entitlement, so its drinks reach
            // Health from here. Rewriting an unchanged day leaves it as it was.
            if prefs.mirrorsToHealth {
                let logbook = database.logbook(prefs)
                let today = logbook.clock.today
                Task { await Health.shared.mirror([today - 1, today], logbook) }
            }
        }
        // The Lock Screen widget's link opens straight onto the Log tab.
        .onOpenURL { if $0.host() == "log" { tab = "log" } }
    }
}
