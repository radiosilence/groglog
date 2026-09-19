import Foundation
import Observation

@Observable final class Prefs {
    @ObservationIgnored private let store: UserDefaults

    var rolloverHour: Int { didSet { store.set(rolloverHour, forKey: "rolloverHour") } }
    var currency: String { didSet { store.set(currency, forKey: "currency") } }
    var goal: Goal { didSet { store.set(try? JSONEncoder().encode(goal), forKey: "goal") } }

    init(store: UserDefaults = .standard) {
        self.store = store
        rolloverHour = store.object(forKey: "rolloverHour") as? Int ?? 5
        currency = store.string(forKey: "currency") ?? Locale.current.currency?.identifier ?? "GBP"
        goal = store.data(forKey: "goal").flatMap { try? JSONDecoder().decode(Goal.self, from: $0) } ?? Goal()
    }

    var clock: DayClock { DayClock(rolloverHour: rolloverHour) }
}
