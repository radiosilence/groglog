import SwiftData
import SwiftUI

@main
struct GrogLogApp: App {
    /// Debug builds can swap to a throwaway in-memory store of sample data; the real log is never touched.
    @AppStorage("demoMode") private var demoMode = false
    @State private var real = Store.real()
    @State private var demo: Store?

    var body: some Scene {
        WindowGroup {
            let store = demoMode ? demo ?? real : real
            RootView()
                .id(ObjectIdentifier(store.container))
                .environment(store.prefs)
                .modelContainer(store.container)
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
    let container: ModelContainer
    let prefs: Prefs

    static let schema: [any PersistentModel.Type] = [Drink.self, Favourite.self, Pour.self, Day.self]

    static func real() -> Store {
        let prefs = Prefs()
        let container = try! ModelContainer(for: Schema(schema))
        Seed.drinksIfNeeded(container.mainContext)
        return Store(container: container, prefs: prefs)
    }

    #if DEBUG
    static func demo() -> Store {
        let prefs = Prefs(store: UserDefaults(suiteName: "demo")!)
        if !prefs.goal.isEnabled { prefs.goal = Goal(isEnabled: true, reductionPercent: 10, periodDays: 7) }
        let container = try! ModelContainer(for: Schema(schema), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        Seed.drinksIfNeeded(container.mainContext)
        Seed.sample(container.mainContext, clock: prefs.clock)
        return Store(container: container, prefs: prefs)
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
