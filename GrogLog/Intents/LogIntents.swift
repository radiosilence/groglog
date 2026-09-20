import AppIntents
import Foundation
import GRDB

/// Logging as an intent, so a widget button, Shortcuts and the Action Button reach the same `Logbook` transaction
/// the Log grid does. There is no second write path: totals stay derived and can't drift, whoever made the change.

/// A drink in a size — what a Log tile is — as something an intent can take as a parameter.
nonisolated struct ServeEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Drink")
    static let defaultQuery = ServeQuery()

    /// `Serve.key`: the drink, its vessel and its size. The price isn't in it — that's read at logging time.
    var id: String
    var name: String
    var size: String
    var units: Double

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(size) · \(units.unitsText) u")
    }

    init(_ serve: Serve) {
        id = serve.id
        name = serve.drink.name
        size = serve.vessel.label(ml: serve.volumeMl)
        units = serve.units
    }
}

nonisolated struct ServeQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ServeEntity] {
        let logbook = await Store.logbook
        return try await logbook.writer.read { db in
            try identifiers.compactMap { try Serve.matching($0, db) }.map(ServeEntity.init)
        }
    }

    func suggestedEntities() async throws -> [ServeEntity] {
        let logbook = await Store.logbook
        return try await logbook.writer.read { try Serve.grid($0).map(ServeEntity.init) }
    }
}

struct LogDrinkIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a Drink"
    static let description = IntentDescription("Logs a drink now, at the size and price it's pinned at on the Log grid.")

    @Parameter(title: "Drink") var serve: ServeEntity

    init() {}

    /// What a widget's tile is: this drink, logged now.
    init(serve: ServeEntity) {
        self.serve = serve
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let logbook = await Store.logbook
        guard let pour = try await logbook.writer.read({ try Serve.matching(serve.id, $0) }) else { throw DrinkGone() }
        logbook.log(pour, at: [.now])

        let goal = await Store.goal
        let ledger = Ledger(days: try await logbook.writer.read { try Day.fetchAll($0) }, clock: logbook.clock)
        let day = logbook.clock.today
        let units = ledger.totals(on: day).units
        guard let budget = ledger.dailyBudget(on: day, goal: goal) else {
            return .result(dialog: "\(units.unitsText) units today.")
        }
        let left = budget - units
        return .result(dialog: left >= 0
            ? "\(units.unitsText) units today, \(left.unitsText) of \(budget.unitsText) left."
            : "\(units.unitsText) units today, \((-left).unitsText) over \(budget.unitsText).")
    }
}

nonisolated struct MarkDayAlcoholFreeIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark Today Alcohol-Free"
    static let description = IntentDescription("Marks today as a day without a drink. A day left unmarked isn't a dry one — it's one that wasn't logged.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let logbook = await Store.logbook
        let day = logbook.clock.today
        // Logging a drink clears the mark, so setting it on a day that already has drinks would only lie until the next retotal.
        let count = try await logbook.writer.read { try Day.fetchOne($0, key: day.number)?.count ?? 0 }
        guard count == 0 else { return .result(dialog: "Today already has \(count) logged.") }
        logbook.setAlcoholFree(true, on: day)
        return .result(dialog: "Today's marked alcohol-free.")
    }
}

nonisolated struct GrogLogShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogDrinkIntent(),
            phrases: ["Log a drink in \(.applicationName)"],
            shortTitle: "Log a drink",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: MarkDayAlcoholFreeIntent(),
            phrases: ["Mark today alcohol-free in \(.applicationName)"],
            shortTitle: "Alcohol-free day",
            systemImageName: "checkmark.circle"
        )
    }
}

nonisolated struct DrinkGone: Error, CustomLocalizedStringResourceConvertible {
    var localizedStringResource: LocalizedStringResource { "That drink isn't in GrogLog any more." }
}

nonisolated extension Serve {
    /// The tiles an intent offers: pinned drinks, most recently drunk first, hidden ones out. The Log grid also
    /// shows whatever was logged today; a list of suggestions doesn't need to follow the day around.
    static func grid(_ db: Database) throws -> [Serve] {
        try Favourite
            .including(required: Favourite.drink)
            .order(Column("lastUsed").desc, Column("sortOrder"))
            .asRequest(of: FavouriteItem.self)
            .fetchAll(db)
            .filter { !$0.drink.isHidden }
            .map(\.serve)
    }

    /// The inverse of `key`: a drink in a size, at the price it's pinned at — or what the drink comes to at that
    /// size if it isn't pinned any more. Prices are read now rather than carried in the key, because they change.
    static func matching(_ key: String, _ db: Database) throws -> Serve? {
        let parts = key.split(separator: "|")
        guard parts.count == 3,
              let drinkId = UUID(uuidString: String(parts[0])),
              let vessel = Vessel(rawValue: String(parts[1])),
              let volumeMl = Double(parts[2]),
              let drink = try Drink.fetchOne(db, key: drinkId)
        else { return nil }
        let price = try Favourite
            .filter(Column("drinkId") == drinkId && Column("vessel") == vessel.rawValue && Column("volumeMl") == volumeMl)
            .fetchOne(db)?.price
        return Serve(drink, vessel, volumeMl, price: price)
    }
}
