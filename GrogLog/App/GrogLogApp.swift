import GRDBQuery
import SwiftUI

@main
struct GrogLogApp: App {
    /// Debug builds can swap to a throwaway in-memory database of sample data; the real log is never touched.
    @AppStorage("demoMode") private var demoMode = false
    @State private var real = Store.real()
    @State private var demo: Store?

    var body: some Scene {
        WindowGroup {
            let store = demoMode ? demo ?? real : real
            RootView()
                .id(store.id)
                .environment(store.prefs)
                .databaseContext(.readWrite { store.database.writer })
                .tint(.grog)
                .onChange(of: demoMode, initial: true) {
                    #if DEBUG
                    if demoMode, demo == nil { demo = .demo() }
                    #endif
                }
        }
    }
}

private struct Store {
    let id = UUID()
    let database: AppDatabase
    let prefs: Prefs

    static func real() -> Store {
        let prefs = Prefs()
        let database = try! AppDatabase.onDisk()
        let logbook = Logbook(writer: database.writer, clock: prefs.clock)
        try! Seed.drinksIfNeeded(logbook)
        #if DEBUG
        // `-importBackup <path>` merges a backup file on launch, for moving data between builds.
        if let path = UserDefaults.standard.string(forKey: "importBackup"), let data = FileManager.default.contents(atPath: path) {
            _ = try? Exporter.restore(data, writer: database.writer, prefs: prefs)
        }
        #endif
        return Store(database: database, prefs: prefs)
    }

    #if DEBUG
    static func demo() -> Store {
        let prefs = Prefs(store: UserDefaults(suiteName: "demo")!)
        if !prefs.goal.isEnabled { prefs.goal = Goal(isEnabled: true, reductionPercent: 10, periodDays: 7) }
        let database = try! AppDatabase.inMemory()
        let logbook = Logbook(writer: database.writer, clock: prefs.clock)
        try! Seed.drinksIfNeeded(logbook)
        try! Seed.sample(logbook)
        return Store(database: database, prefs: prefs)
    }
    #endif
}

struct RootView: View {
    @Environment(Prefs.self) private var prefs
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
        // Reading scenePhase re-evaluates `today` when the app comes back the next morning.
        .onChange(of: scenePhase) {}
    }
}
