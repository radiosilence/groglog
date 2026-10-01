import AppIntents
import Foundation
import GRDB

/// Logging as an intent, so a widget button, Shortcuts and the Action Button use the same `Logbook` transaction as
/// the Log grid. With a single write path, totals stay derived and cannot drift.

/// A drink in a size, as on a Log tile, in a form an intent can take as a parameter.
nonisolated struct ServeEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Drink")
    static let defaultQuery = ServeQuery()

    /// `Serve.key`: the drink, its vessel and its size. The price is excluded and read at logging time.
    var id: String
    var name: String
    var size: String
    /// The size in short form, for a widget tile.
    var shortSize: String
    var units: Double

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(size) · \(units.unitsText) u")
    }

    init(_ serve: Serve) {
        id = serve.id
        name = serve.drink.name
        size = serve.vessel.label(ml: serve.volumeMl)
        shortSize = serve.vessel.shortLabel(ml: serve.volumeMl)
        units = serve.units
    }
}

nonisolated struct ServeQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ServeEntity] {
        try await DatabaseSuspension.awake {
            let logbook = try await Store.logbook()
            return try await logbook.writer.read { db in
                try identifiers.compactMap { try Serve.matching($0, db) }.map(ServeEntity.init)
            }
        }
    }

    func suggestedEntities() async throws -> [ServeEntity] {
        try await DatabaseSuspension.awake {
            let logbook = try await Store.logbook()
            return try await logbook.writer.read { try Serve.grid($0).map(ServeEntity.init) }
        }
    }
}

struct LogDrinkIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a Drink"
    static let description = IntentDescription("Logs a drink now, at the size and price pinned on the Log grid.")

    @Parameter(title: "Drink") var serve: ServeEntity

    init() {}

    /// A widget tile's action: this drink, logged now.
    init(serve: ServeEntity) {
        self.serve = serve
    }

    /// Siri and Shortcuts can run this with the app in the background, so the log is opened for it.
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await DatabaseSuspension.awake { try await log() }
    }

    private func log() async throws -> some IntentResult & ProvidesDialog {
        let logbook = try await Store.logbook()
        guard let pour = try await logbook.writer.read({ try Serve.matching(serve.id, $0) }) else { throw DrinkGone() }
        logbook.log(pour, at: [.now])

        let goal = await Store.goal
        let ledger = Ledger(days: try await logbook.writer.read { try Day.fetchAll($0) }, clock: logbook.clock)
        let day = logbook.clock.today
        let units = ledger.totals(on: day).units
        guard let budget = ledger.dailyBudget(on: day, goal: goal) else {
            return .result(dialog: "\(units.unitsText) units today.")
        }
        return .result(dialog: "\(units.unitsText) units today, \(units.leftText(of: budget)).")
    }
}

nonisolated struct MarkDayAlcoholFreeIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark Today Alcohol-Free"
    static let description = IntentDescription("Marks today as a day without a drink. A day left unmarked is treated as not logged rather than alcohol-free.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await DatabaseSuspension.awake { try await mark() }
    }

    private func mark() async throws -> some IntentResult & ProvidesDialog {
        let logbook = try await Store.logbook()
        let day = logbook.clock.today
        // Logging a drink clears the mark, so marking a day that already has drinks would be wrong until the next retotal.
        let count = try await logbook.writer.read { try Day.fetchOne($0, key: day.number)?.count ?? 0 }
        guard count == 0 else { return .result(dialog: "Today already has \(count) logged.") }
        logbook.setAlcoholFree(true, on: day)
        return .result(dialog: "Today is marked alcohol-free.")
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
    var localizedStringResource: LocalizedStringResource { "That drink is no longer in GrogLog." }
}

nonisolated extension Serve {
    /// The tiles an intent offers: pinned drinks, most recently drunk first, excluding hidden drinks and Units,
    /// which in the app asks for an amount and here could only log one. Unlike the Log grid, today's other drinks
    /// are not included, since suggestions need not track the day.
    static func grid(_ db: Database) throws -> [Serve] {
        try Favourite
            .including(required: Favourite.drink)
            .order(Column("lastUsed").desc, Column("sortOrder"))
            .asRequest(of: FavouriteItem.self)
            .fetchAll(db)
            .filter { !$0.drink.isHidden && $0.drink.category != .units }
            .map(\.serve)
    }

    /// The inverse of `key`: a drink in a size at its pinned price, or the drink's derived price at that size if it
    /// is no longer pinned. Prices are read at call time rather than carried in the key, because they change.
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
