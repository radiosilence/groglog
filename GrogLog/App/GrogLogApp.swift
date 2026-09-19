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
        // The Lock Screen widget: two taps from a locked phone to a logged drink.
        .onOpenURL { if $0.host() == "log" { tab = "log" } }
    }
}
