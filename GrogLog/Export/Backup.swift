import CoreTransferable
import Foundation
import GRDB
import UniformTypeIdentifiers

/// Everything, as one self-describing document. Days are listed explicitly — including unlogged ones —
/// so a reader (human or LLM) never has to guess whether a gap means "dry" or "forgot".
/// Import is lenient: only `days[].date` and `days[].status` are required, so other apps' data can be hand-converted (see docs/IMPORT.md).
nonisolated struct Backup: Codable, Sendable {
    var format: String? = "groglog/1"
    var exportedAt: Date? = .now
    var notes: String? = "UK units: 1 unit = 10 ml pure alcohol. Days run from dayStartsAtHour to the same hour next morning. status is drank, alcohol_free (explicitly marked), not_logged (unknown — do not assume dry) or in_progress (today)."
    var dayStartsAtHour: Int?
    var currency: String?
    var goal: Goal?
    /// `yyyy-MM-dd` the taper gets low enough to stop at (`Goal.stopFrom`), if kept to.
    var projectedStop: String?
    var drinks: [DrinkRecord]?
    /// The Log grid: drinks in the sizes and at the prices you usually have them.
    var favourites: [FavouriteRecord]?
    var days: [DayRecord]

    /// What a drink is, with the size and price it was first added at.
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
        /// Set when the day's spend was entered by hand; `cost` is then that figure rather than the drinks' prices.
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
        let days = ledger.firstDay.map { Array($0...ledger.today) } ?? []

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
                lines.append("Goal: stepped taper, cut 10% every 4 days above 25 units/day, every 3 days above 15, then every day, compounding daily, down to \(goal.targetWeekly.unitsText) units/week — on a fixed schedule \(from).")
            case .proportional:
                lines.append("Goal: cut \(Int(goal.reductionPercent))% every \(goal.periodDays) day(s), compounding daily, down to \(goal.targetWeekly.unitsText) units/week — on a fixed schedule \(from).")
            case .linear:
                lines.append("Goal: cut \(goal.reductionUnits.unitsText) units/day off the daily budget every \(goal.periodDays) day(s), down to \(goal.targetWeekly.unitsText) units/week — on a fixed schedule \(from).")
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
                lines.append("- \(day.date): \((day.units ?? 0).unitsText) u\(budget), \(Int(day.kcal ?? 0)) kcal, \(money(day.cost))\(day.status == "in_progress" ? " — so far" : "")")
                for pour in day.pours ?? [] {
                    let time = pour.time?.formatted(date: .omitted, time: .shortened) ?? ""
                    lines.append("  - \(time) \(pour.name), \((pour.volumeMl ?? 0).volumeText) at \((pour.abv ?? 0).abvText): \((pour.units ?? 0).unitsText) u")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Merges a backup in, as one transaction. Nothing already here is touched: drinks and entries are matched by id,
    /// and a day that already has drinks logged keeps them. Settings are restored when present, first, so entries land
    /// on the right days. Totals are recomputed for just the days touched.
    @MainActor @discardableResult
    static func restore(_ data: Data, writer: any DatabaseWriter, prefs: Prefs) throws -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(Backup.self, from: data)
        if let hour = backup.dayStartsAtHour { prefs.rolloverHour = hour }
        if let currency = backup.currency { prefs.currency = currency }
        if let goal = backup.goal { prefs.goal = goal }
        let logbook = Logbook(writer: writer, clock: prefs.clock, mirrorsToHealth: prefs.mirrorsToHealth)
        var added = 0

        try logbook.bulk { db in
            // Backup drinks match existing ones by id, or by name and type (a fresh install's own generics),
            // so restoring onto a new phone doesn't double every drink.
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
                guard let day = DayKey(record.date), !daysWithPours.contains(day.number) else { continue }
                if record.status == "alcohol_free" {
                    try Day(number: day.number, isAlcoholFree: true).save(db)
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
        return added
    }
}

/// A lazily-built export file for `ShareLink`: nothing is read until the share sheet asks for it, and then off the main actor.
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

    /// `UTType.markdown` is iOS 27 and this ships to 26, but the identifier behind it is the same.
    private static let markdown = UTType("net.daringfireball.markdown") ?? .plainText

    /// A file representation each, so a receiver gets the bytes and a filename — and the contents behind
    /// them, because a receiver that asks for something not offered here gets handed the auto-registered
    /// file URL instead, and a URL into this app's sandbox is no use to anything outside it.
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

    /// The bytes themselves, for a receiver that would rather have the contents than a file.
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
