import Foundation
import Observation

@Observable final class Prefs {
    @ObservationIgnored private let store: UserDefaults

    var rolloverHour: Int { didSet { store.set(rolloverHour, forKey: "rolloverHour") } }
    var currency: String { didSet { store.set(currency, forKey: "currency") } }
    var goal: Goal { didSet { store.set(try? JSONEncoder().encode(goal), forKey: "goal") } }
    var mirrorsToHealth: Bool { didSet { store.set(mirrorsToHealth, forKey: "mirrorsToHealth") } }
    var readsHeart: Bool { didSet { store.set(readsHeart, forKey: "readsHeart") } }
    var readsSleep: Bool { didSet { store.set(readsSleep, forKey: "readsSleep") } }

    init(store: UserDefaults = .shared) {
        self.store = store
        rolloverHour = store.object(forKey: "rolloverHour") as? Int ?? 5
        currency = store.string(forKey: "currency") ?? Locale.current.currency?.identifier ?? "GBP"
        goal = store.data(forKey: "goal").flatMap { try? JSONDecoder().decode(Goal.self, from: $0) } ?? Goal()
        mirrorsToHealth = store.bool(forKey: "mirrorsToHealth")
        readsHeart = store.bool(forKey: "readsHeart")
        readsSleep = store.bool(forKey: "readsSleep")
    }

    var clock: DayClock { DayClock(rolloverHour: rolloverHour) }
}

nonisolated extension UserDefaults {
    /// Settings live in the app group alongside the log. A widget is another process, and its `standard` defaults
    /// are its own empty ones — read those and it sees no goal, so it draws a budget nobody set.
    nonisolated(unsafe) static let shared: UserDefaults = {
        guard let group = UserDefaults(suiteName: AppDatabase.appGroup) else { return .standard }
        // Only the app carries settings across, and only once. An extension's `standard` is its own empty one, so
        // a widget running this first copied nothing and marked the move done — taking the app's settings with it.
        // Hence a second key: the first is already stamped on phones the broken version reached.
        let isExtension = Bundle.main.bundleURL.pathExtension == "appex"
        if !isExtension, group.object(forKey: "carriedOverFromApp") == nil {
            for key in ["rolloverHour", "currency", "goal", "mirrorsToHealth"] {
                if let value = UserDefaults.standard.object(forKey: key) { group.set(value, forKey: key) }
            }
            group.set(true, forKey: "carriedOverFromApp")
        }
        return group
    }()
}
