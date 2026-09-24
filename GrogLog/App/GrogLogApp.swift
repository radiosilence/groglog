import GRDBQuery
import SwiftUI

@main
struct GrogLogApp: App {
    /// Debug builds can swap to a throwaway in-memory database of sample data; the real log is never touched.
    @AppStorage("demoMode") private var demoMode = false
    @State private var real = Store.real
    @State private var demo: Store?

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

    var body: some View {
        let today = prefs.clock.today
        TabView(selection: $tab) {
            Tab("Log", systemImage: "plus.circle", value: "log") {
                NavigationStack { LedgerReader { LogScreen(ledger: $0) } }
            }
            Tab("Calendar", systemImage: "calendar", value: "calendar") {
                NavigationStack { LedgerReader { CalendarScreen(ledger: $0) } }
            }
            Tab("Day", systemImage: "chart.line.uptrend.xyaxis", value: "day") {
                NavigationStack { DayPager(day: today).id(today) }
            }
            Tab("Reports", systemImage: "chart.bar.xaxis", value: "reports") {
                NavigationStack { LedgerReader { ReportsScreen(ledger: $0) } }
            }
            Tab("Setup", systemImage: "slider.horizontal.3", value: "setup") {
                NavigationStack { LedgerReader { SetupScreen(ledger: $0) } }
            }
        }
        // Reading scenePhase re-evaluates `today` when the app comes back the next morning, and picks up anything
        // the widget logged while we were away: observations only see writes made through this process, and a
        // widget is another one. A widget can only be tapped with the app in the background, so coming back is the
        // moment to ask. The database is told its region changed rather than written to — there's nothing to write,
        // the drink is already there; the screens just don't know yet.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, let writer = try? database.writer else { return }
            try? writer.write { try $0.notifyChanges(in: .fullDatabase) }
            // A widget's tap logs in the widget's process, which has no Health entitlement, so its drinks reach
            // Health from here. Rewriting a day that didn't change leaves it as it was.
            if prefs.mirrorsToHealth {
                let logbook = database.logbook(prefs)
                let today = logbook.clock.today
                Task { await Health.shared.mirror([today - 1, today], logbook) }
            }
        }
        // The Lock Screen widget: two taps from a locked phone to a logged drink.
        .onOpenURL { if $0.host() == "log" { tab = "log" } }
    }
}
