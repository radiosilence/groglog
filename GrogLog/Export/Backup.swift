import CoreTransferable
import Foundation
import GRDB
import UniformTypeIdentifiers

/// Everything, as one self-describing document. Days are listed explicitly, including unlogged ones, so a reader
/// (human or LLM) can tell a dry day from a gap. Import is lenient: only `days[].date` and `days[].status` are
/// required, so other apps' data can be hand-converted (see docs/IMPORT.md).
nonisolated struct Backup: Codable, Sendable {
    var format: String? = "groglog/1"
    var exportedAt: Date? = .now
    var notes: String? = "UK units: 1 unit = 10 ml pure alcohol. Days run from dayStartsAtHour to the same hour next morning. status is drank, alcohol_free (explicitly marked), not_logged (unknown; do not assume dry) or in_progress (today)."
    var dayStartsAtHour: Int?
    var currency: String?
    var goal: Goal?
    /// `yyyy-MM-dd` on which the taper reaches the level at which drinking can stop (`Goal.stopFrom`), if followed.
    var projectedStop: String?
    var drinks: [DrinkRecord]?
    /// The Log grid: drinks in their usual sizes and prices.
    var favourites: [FavouriteRecord]?
    var days: [DayRecord]

    /// A drink's identity, with the size and price it was first added at.
    struct DrinkRecord: Codable {
        var id: UUID
        var name: String
        var category: DrinkCategory
        var abv: Double
        var vessel: Vessel
        var volumeMl: Double
        var price: Double
        var isGeneric: Bool
        var isHidden: Bool
    }

    struct FavouriteRecord: Codable {
        var drinkID: UUID
        var vessel: Vessel
        var volumeMl: Double
        var price: Double
        var order: Int
    }

    struct DayRecord: Codable {
        var date: String
        var status: String
        var units: Double?
        var kcal: Double?
        var cost: Double?
        /// Set when the day's spend was entered manually; `cost` is then that figure rather than the sum of prices.
        var spentByHand: Double?
        var budget: Double?
        var pours: [PourRecord]?
    }

    struct PourRecord: Codable {
        var id: UUID?
        var time: Date?
        var name: String
        var category: DrinkCategory?
        var vessel: Vessel?
        var volumeMl: Double?
        var abv: Double?
        var units: Double?
        var kcal: Double?
        var price: Double?
        var drinkID: UUID?
    }
}

nonisolated enum Exporter {
    /// What an export needs from settings, captured so the export can run off the main actor.
    struct Settings: Sendable {
        var rolloverHour: Int
        var currency: String
        var goal: Goal

        init(rolloverHour: Int = 5, currency: String = "GBP", goal: Goal = Goal()) {
            self.rolloverHour = rolloverHour
            self.currency = currency
            self.goal = goal
        }

        @MainActor init(_ prefs: Prefs) {
            rolloverHour = prefs.rolloverHour
            currency = prefs.currency
            goal = prefs.goal
        }
    }

    static func backup(_ db: Database, settings: Settings) throws -> Backup {
        let clock = DayClock(rolloverHour: settings.rolloverHour)
        let ledger = Ledger(days: try Day.fetchAll(db), clock: clock)
        let entries = try Pour.including(required: Pour.drink).order(Column("timestamp")).asRequest(of: Entry.self).fetchAll(db)
        let byDay = Dictionary(grouping: entries, by: \.day)
        let favourites = try Favourite.order(Column("sortOrder")).fetchAll(db)
        let days = ledger.firstDay.map { Array(min($0, ledger.today)...ledger.today) } ?? []

        return Backup(
            dayStartsAtHour: settings.rolloverHour,
            currency: settings.currency,
            goal: settings.goal,
            projectedStop: ledger.projection(goal: settings.goal).stoppable?.description,
            drinks: try Drink.order(Column("name")).fetchAll(db).map {
                .init(id: $0.id, name: $0.name, category: $0.category, abv: $0.abv, vessel: $0.vessel, volumeMl: $0.volumeMl, price: $0.price, isGeneric: $0.isGeneric, isHidden: $0.isHidden)
            },
            favourites: favourites.map { .init(drinkID: $0.drinkId, vessel: $0.vessel, volumeMl: $0.volumeMl, price: $0.price, order: $0.sortOrder) },
            days: days.reversed().map { day in
                let totals = ledger.totals(on: day)
                let status = switch ledger.status(on: day) {
                case .drank: "drank"
                case .alcoholFree: "alcohol_free"
                case .today: "in_progress"
                default: "not_logged"
                }
                return .init(
                    date: day.description,
                    status: status,
                    units: totals.units.rounded2,
                    kcal: totals.kcal.rounded(),
                    cost: totals.cost.rounded2,
                    spentByHand: ledger.spendOverride(on: day)?.rounded2,
                    budget: ledger.dailyBudget(on: day, goal: settings.goal)?.rounded2,
                    pours: (byDay[day.number] ?? []).map {
                        .init(id: $0.id, time: $0.timestamp, name: $0.name, category: $0.category, vessel: $0.vessel, volumeMl: $0.volumeMl, abv: $0.abv, units: $0.units.rounded2, kcal: $0.kcal.rounded(), price: $0.price, drinkID: $0.drink.id)
                    }
                )
            }
        )
    }

    static func json(_ backup: Backup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(backup)
    }

    /// A compact, readable log meant for pasting into a chat with an LLM.
    static func markdown(_ backup: Backup) -> String {
        let money = { (value: Double?) in (value ?? 0).money(backup.currency ?? "GBP") }
        var lines = [
            "# Drinking log",
            "",
            "Exported \((backup.exportedAt ?? .now).formatted(date: .abbreviated, time: .shortened)). \(backup.notes ?? "")",
            "",
        ]
        if let goal = backup.goal, goal.isEnabled {
            let from = "from \(goal.baselineWeekly.unitsText) units/week starting \(goal.start.formatted(date: .abbreviated, time: .omitted))"
            switch goal.taper {
            case .dynamic:
                lines.append("Goal: stepped taper, cut 10% every 4 days above 25 units/day, every 3 days above 15, then every day, compounding daily, down to \(goal.targetWeekly.unitsText) units/week, on a fixed schedule \(from).")
            case .proportional:
                lines.append("Goal: cut \(Int(goal.reductionPercent))% every \(goal.periodDays) day(s), compounding daily, down to \(goal.targetWeekly.unitsText) units/week, on a fixed schedule \(from).")
            case .linear:
                lines.append("Goal: cut \(goal.reductionUnits.unitsText) units/day off the daily budget every \(goal.periodDays) day(s), down to \(goal.targetWeekly.unitsText) units/week, on a fixed schedule \(from).")
            }
            if let stop = backup.projectedStop {
                lines.append("At this rate: down to \(Goal.stopFrom.unitsText) units/week, low enough to stop, by \(stop).")
            }
            lines.append("")
        }
        lines += ["## Days (newest first)", ""]
        for day in backup.days {
            switch day.status {
            case "alcohol_free":
                lines.append("- \(day.date): alcohol-free")
            case "not_logged":
                lines.append("- \(day.date): not logged")
            default:
                let budget = day.budget.map { " (budget \($0.unitsText))" } ?? ""
                lines.append("- \(day.date): \((day.units ?? 0).unitsText) u\(budget), \(Int(day.kcal ?? 0)) kcal, \(money(day.cost))\(day.status == "in_progress" ? " (so far)" : "")")
                for pour in day.pours ?? [] {
                    let time = pour.time?.formatted(date: .omitted, time: .shortened) ?? ""
                    lines.append("  - \(time) \(pour.name), \((pour.volumeMl ?? 0).volumeText) at \((pour.abv ?? 0).abvText): \((pour.units ?? 0).unitsText) u")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    enum ImportError: LocalizedError {
        case dayEndsAtImpossibleHour(Int)
        case tooLarge

        var errorDescription: String? {
            switch self {
            case .dayEndsAtImpossibleHour(let hour): "The file sets the day to end at hour \(hour), which is not an hour of the day."
            case .tooLarge: "The file is too large to be a GrogLog backup."
            }
        }
    }

    /// Merges a backup in one transaction without modifying existing data: drinks and entries are matched by id, and
    /// a day that already has drinks keeps them. Settings present in the file are restored first, so entries land on
    /// the correct days. Totals are recomputed for only the touched days.
    @MainActor @discardableResult
    static func restore(_ data: Data, writer: any DatabaseWriter, prefs: Prefs) throws -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(Backup.self, from: data)
        // An hour outside 0-23 would break every date the clock builds, so the file is refused.
        if let hour = backup.dayStartsAtHour, !(0...23).contains(hour) { throw ImportError.dayEndsAtImpossibleHour(hour) }
        let movesDayEnd = backup.dayStartsAtHour.map { $0 != prefs.rolloverHour } ?? false
        if let hour = backup.dayStartsAtHour { prefs.rolloverHour = hour }
        if let currency = backup.currency { prefs.currency = currency }
        if let goal = backup.goal { prefs.goal = goal }
        let logbook = Logbook(writer: writer, clock: prefs.clock, mirrorsToHealth: prefs.mirrorsToHealth)
        var added = 0

        try logbook.bulk { db in
            // Backup drinks match existing ones by id, or by name and type (a fresh install's generics), so restoring
            // onto a new device does not duplicate every drink.
            var drinkIDs: [UUID: UUID] = [:]
            for record in backup.drinks ?? [] {
                if let existing = try Drink.fetchOne(db, key: record.id)
                    ?? Drink.filter(Column("name") == record.name && Column("category") == record.category.rawValue).fetchOne(db) {
                    drinkIDs[record.id] = existing.id
                } else {
                    try Drink(id: record.id, name: record.name, category: record.category, abv: record.abv, vessel: record.vessel, volumeMl: record.volumeMl, price: record.price, isGeneric: record.isGeneric, isHidden: record.isHidden).insert(db)
                    drinkIDs[record.id] = record.id
                }
            }
            for record in backup.favourites ?? [] {
                guard let drinkID = drinkIDs[record.drinkID] else { continue }
                let pinned = try Favourite.filter(Column("drinkId") == drinkID && Column("vessel") == record.vessel.rawValue && Column("volumeMl") == record.volumeMl).fetchCount(db)
                if pinned == 0 {
                    try Favourite(drinkId: drinkID, vessel: record.vessel, volumeMl: record.volumeMl, price: record.price, sortOrder: record.order).insert(db)
                }
            }

            let existingPours = Set(try Pour.select(Column("id"), as: UUID.self).fetchAll(db))
            let daysWithPours = Set(try Pour.select(Column("day"), as: Int.self).distinct().fetchAll(db))
            var touched: Set<DayKey> = []
            for record in backup.days {
                // A future day cannot have been drunk on, and would put the log's first day after today.
                guard let day = DayKey(record.date), day <= logbook.clock.today, !daysWithPours.contains(day.number) else { continue }
                if record.status == "alcohol_free" {
                    var row = try Day.fetchOne(db, key: day.number) ?? Day(number: day.number)
                    row.isAlcoholFree = true
                    try row.save(db)
                }
                if let spent = record.spentByHand {
                    var row = try Day.fetchOne(db, key: day.number) ?? Day(number: day.number)
                    row.costOverride = spent
                    try row.save(db)
                    touched.insert(day)
                }
                let evening = logbook.clock.suggestedTime(for: day, after: nil)
                let pours = record.pours ?? []
                if pours.isEmpty, let units = record.units, units > 0 {
                    let drink = try logbook.unitsDrink(db)
                    try Pour(drinkId: drink.id, timestamp: evening, day: day.number, vessel: .shot, volumeMl: units * 10, price: record.cost ?? 0, kcalOverride: record.kcal).insert(db)
                    added += 1
                    touched.insert(day)
                }
                for (index, pour) in pours.enumerated() where pour.id.map(existingPours.contains) != true {
                    let time = pour.time ?? evening.addingTimeInterval(Double(index) * 30 * 60)
                    let id = pour.id ?? UUID()
                    if let volume = pour.volumeMl {
                        let category = pour.category ?? .beer
                        let vessel = pour.vessel ?? category.defaultVessel
                        let drink = try pour.drinkID.flatMap { drinkIDs[$0] }.flatMap { try Drink.fetchOne(db, key: $0) }
                            ?? logbook.findOrCreate(name: pour.name, category: category, abv: pour.abv ?? category.defaultABV, vessel: vessel, volumeMl: volume, db)
                        let kcal = drink.category == .units ? pour.kcal : nil
                        try Pour(id: id, drinkId: drink.id, timestamp: time, day: day.number, vessel: vessel, volumeMl: volume, price: pour.price ?? 0, kcalOverride: kcal).insert(db)
                    } else {
                        let drink = try logbook.unitsDrink(db)
                        try Pour(id: id, drinkId: drink.id, timestamp: time, day: day.number, vessel: .shot, volumeMl: (pour.units ?? 0) * 10, price: pour.price ?? 0, kcalOverride: pour.kcal).insert(db)
                    }
                    added += 1
                    touched.insert(day)
                }
            }
            return touched
        }
        // Existing entries were assigned days by the old hour and imported ones by the new one, so every day is
        // reassigned.
        if movesDayEnd { Task.detached { await DatabaseSuspension.awake { logbook.rebuild(reassigningDays: true) } } }
        return added
    }
}

/// A lazily built export file for `ShareLink`: nothing is read until the share sheet requests it, and then off the
/// main actor.
nonisolated struct ExportFile: Transferable {
    enum Kind: Sendable {
        case json, markdown
    }

    let kind: Kind
    let reader: any DatabaseReader
    let settings: Exporter.Settings

    @MainActor init(kind: Kind, reader: any DatabaseReader, prefs: Prefs) {
        self.kind = kind
        self.reader = reader
        settings = Exporter.Settings(prefs)
    }

    /// `UTType.markdown` requires iOS 27 and the app supports 26; the underlying identifier is the same.
    private static let markdown = UTType("net.daringfireball.markdown") ?? .plainText

    /// Each format is offered as a file representation, giving a receiver the bytes and a filename, and also as data:
    /// a receiver asking for a type not offered here is given the auto-registered file URL instead, which points into
    /// this app's sandbox and is unreadable elsewhere.
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { file in
            try await file.write()
        }
        .exportingCondition { $0.kind == .json }

        FileRepresentation(exportedContentType: markdown) { file in
            try await file.write()
        }
        .exportingCondition { $0.kind == .markdown }

        DataRepresentation(exportedContentType: .plainText) { file in
            try await file.contents()
        }
        .exportingCondition { $0.kind == .markdown }

        DataRepresentation(exportedContentType: .json) { file in
            try await file.contents()
        }
        .exportingCondition { $0.kind == .json }
    }

    /// The bytes themselves, for a receiver that prefers contents to a file.
    private func contents() async throws -> Data {
        let settings = settings
        let backup = try await reader.read { try Exporter.backup($0, settings: settings) }
        return kind == .json ? try Exporter.json(backup) : Data(Exporter.markdown(backup).utf8)
    }

    private func write() async throws -> SentTransferredFile {
        let stamp = DayClock(rolloverHour: settings.rolloverHour).today.description
        let url = URL.temporaryDirectory.appending(path: "groglog-\(stamp).\(kind == .json ? "json" : "md")")
        try await contents().write(to: url)
        return SentTransferredFile(url)
    }
}

nonisolated private extension Double {
    var rounded2: Double { (self * 100).rounded() / 100 }
}
