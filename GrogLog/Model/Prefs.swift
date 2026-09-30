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
    var syncsWithICloud: Bool { didSet { store.set(syncsWithICloud, forKey: "syncsWithICloud") } }

    init(store: UserDefaults = .shared) {
        self.store = store
        rolloverHour = store.object(forKey: "rolloverHour") as? Int ?? 5
        currency = store.string(forKey: "currency") ?? Locale.current.currency?.identifier ?? "GBP"
        goal = store.data(forKey: "goal").flatMap { try? JSONDecoder().decode(Goal.self, from: $0) } ?? Goal()
        mirrorsToHealth = store.bool(forKey: "mirrorsToHealth")
        readsHeart = store.bool(forKey: "readsHeart")
        readsSleep = store.bool(forKey: "readsSleep")
        syncsWithICloud = store.object(forKey: "syncsWithICloud") as? Bool ?? true
    }

    var clock: DayClock { DayClock(rolloverHour: rolloverHour) }
}

nonisolated extension UserDefaults {
    /// Settings live in the app group alongside the log. A widget's `standard` defaults are its own and empty, so
    /// reading them would show no goal.
    nonisolated(unsafe) static let shared: UserDefaults = {
        guard let group = UserDefaults(suiteName: AppDatabase.appGroup) else { return .standard }
        // Only the app migrates settings, and only once. An extension's `standard` defaults are empty, so a widget
        // running this first would copy nothing and mark the move done. The first marker key is already set on
        // devices where that happened, so a second key is used.
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
