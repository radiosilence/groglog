import SwiftData
import SwiftUI

@main
struct GrogLogApp: App {
    @State private var prefs: Prefs
    private let container: ModelContainer

    init() {
        let demo = ProcessInfo.processInfo.arguments.contains("-demo")
        let prefs = Prefs(store: demo ? UserDefaults(suiteName: "demo")! : .standard)
        container = try! ModelContainer(
            for: Drink.self, Favourite.self, Pour.self, AlcoholFreeDay.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: demo)
        )
        Seed.drinksIfNeeded(container.mainContext)
        #if DEBUG
        if demo { Seed.sample(container.mainContext, prefs: prefs) }
        #endif
        _prefs = State(initialValue: prefs)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(prefs)
                .tint(.grog)
        }
        .modelContainer(container)
    }
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
