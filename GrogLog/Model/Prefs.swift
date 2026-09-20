import Foundation
import Observation

@Observable final class Prefs {
    @ObservationIgnored private let store: UserDefaults

    var rolloverHour: Int { didSet { store.set(rolloverHour, forKey: "rolloverHour") } }
    var currency: String { didSet { store.set(currency, forKey: "currency") } }
    var goal: Goal { didSet { store.set(try? JSONEncoder().encode(goal), forKey: "goal") } }
    var mirrorsToHealth: Bool { didSet { store.set(mirrorsToHealth, forKey: "mirrorsToHealth") } }

    init(store: UserDefaults = .shared) {
        self.store = store
        rolloverHour = store.object(forKey: "rolloverHour") as? Int ?? 5
        currency = store.string(forKey: "currency") ?? Locale.current.currency?.identifier ?? "GBP"
        goal = store.data(forKey: "goal").flatMap { try? JSONDecoder().decode(Goal.self, from: $0) } ?? Goal()
        mirrorsToHealth = store.bool(forKey: "mirrorsToHealth")
    }

    var clock: DayClock { DayClock(rolloverHour: rolloverHour) }
}

nonisolated extension UserDefaults {
    /// Settings live in the app group alongside the log. A widget is another process, and its `standard` defaults
    /// are its own empty ones — read those and it sees no goal, so it draws a budget nobody set.
    nonisolated(unsafe) static let shared: UserDefaults = {
        guard let group = UserDefaults(suiteName: AppDatabase.appGroup) else { return .standard }
        // Settings written before there were widgets are carried across once; `standard` is left as it was.
        if group.object(forKey: "carriedOver") == nil {
            for key in ["rolloverHour", "currency", "goal", "mirrorsToHealth"] {
                if let value = UserDefaults.standard.object(forKey: key) { group.set(value, forKey: key) }
            }
            group.set(true, forKey: "carriedOver")
        }
        return group
    }()
}
