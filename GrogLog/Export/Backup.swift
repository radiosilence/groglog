import CoreTransferable
import Foundation
import SwiftData
import UniformTypeIdentifiers

/// Everything, as one self-describing document. Days are listed explicitly — including unlogged ones —
/// so a reader (human or LLM) never has to guess whether a gap means "dry" or "forgot".
/// Import is lenient: only `days[].date` and `days[].status` are required, so other apps' data can be hand-converted (see docs/IMPORT.md).
struct Backup: Codable {
    var format: String? = "groglog/1"
    var exportedAt: Date? = .now
    var notes: String? = "UK units: 1 unit = 10 ml pure alcohol. Days run from dayStartsAtHour to the same hour next morning. status is drank, alcohol_free (explicitly marked), not_logged (unknown — do not assume dry) or in_progress (today)."
    var dayStartsAtHour: Int?
    var currency: String?
    var goal: Goal?
    /// `yyyy-MM-dd` the taper drops under a unit a day, if kept to.
    var projectedUnderOneUnit: String?
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

enum Exporter {
    static func backup(context: ModelContext, prefs: Prefs) throws -> Backup {
        let drinks = try context.fetch(FetchDescriptor<Drink>(sortBy: [SortDescriptor(\.name)]))
        let favourites = try context.fetch(FetchDescriptor<Favourite>(sortBy: [SortDescriptor(\.order)]))
        let ledger = Ledger(days: try context.fetch(FetchDescriptor<Day>()), clock: prefs.clock)
        let pours = Dictionary(grouping: try context.fetch(FetchDescriptor<Pour>(sortBy: [SortDescriptor(\.timestamp)])), by: \.day)
        let days = ledger.firstDay.map { Array($0...ledger.today) } ?? []

        return Backup(
            dayStartsAtHour: prefs.rolloverHour,
            currency: prefs.currency,
            goal: prefs.goal,
            projectedUnderOneUnit: ledger.projection(goal: prefs.goal).underOneUnit?.description,
            drinks: drinks.map {
                .init(id: $0.id, name: $0.name, category: $0.category, abv: $0.abv, vessel: $0.vessel, volumeMl: $0.volumeMl, price: $0.price, isGeneric: $0.isGeneric, isHidden: $0.isHidden)
            },
            favourites: favourites.compactMap { favourite in
                favourite.drink.map { .init(drinkID: $0.id, vessel: favourite.vessel, volumeMl: favourite.volumeMl, price: favourite.price, order: favourite.order) }
            },
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
                    budget: ledger.dailyBudget(on: day, goal: prefs.goal)?.rounded2,
                    pours: (pours[day.number] ?? []).map {
                        .init(id: $0.id, time: $0.timestamp, name: $0.name, category: $0.category, vessel: $0.vessel, volumeMl: $0.volumeMl, abv: $0.abv, units: $0.units.rounded2, kcal: $0.kcal.rounded(), price: $0.price, drinkID: $0.drink?.id)
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
            let schedule = goal.isDynamic
                ? "dynamic: each day's budget is the cut applied to the average over the previous period, so there is no schedule to fall behind"
                : "on a fixed schedule from \(goal.baselineWeekly.unitsText) units/week starting \(goal.start.formatted(date: .abbreviated, time: .omitted))"
            lines.append("Goal: cut \(Int(goal.reductionPercent))% every \(goal.periodDays) day(s), compounding daily, down to \(goal.targetWeekly.unitsText) units/week — \(schedule).")
            if let stop = backup.projectedUnderOneUnit {
                lines.append("At this rate: under 1 unit/day by \(stop).")
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

    /// Merges a backup in. Nothing already here is touched: drinks and pours are matched by id,
    /// and a day that already has drinks logged keeps them. Settings are restored when present.
    /// Merges a backup in. Nothing already here is touched: drinks and entries are matched by id, and a day that
    /// already has drinks logged keeps them. Settings are restored when present. Totals are recomputed for the days touched.
    @discardableResult
    static func restore(_ data: Data, into context: ModelContext, prefs: Prefs) throws -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(Backup.self, from: data)
        if let hour = backup.dayStartsAtHour { prefs.rolloverHour = hour }
        if let currency = backup.currency { prefs.currency = currency }
        if let goal = backup.goal { prefs.goal = goal }
        let clock = prefs.clock

        var drinks = try context.fetch(FetchDescriptor<Drink>())
        let drinkIDs = Set(drinks.map(\.id))
        let existing = try context.fetch(FetchDescriptor<Pour>())
        let pourIDs = Set(existing.map(\.id))
        let daysWithPours = Set(existing.map(\.day))

        for record in backup.drinks ?? [] where !drinkIDs.contains(record.id) {
            let drink = Drink(name: record.name, category: record.category, abv: record.abv, vessel: record.vessel, volumeMl: record.volumeMl, price: record.price, isGeneric: record.isGeneric)
            drink.id = record.id
            drink.isHidden = record.isHidden
            context.insert(drink)
            drinks.append(drink)
        }
        let pinned = try context.fetch(FetchDescriptor<Favourite>())
        for record in backup.favourites ?? [] {
            guard let drink = drinks.first(where: { $0.id == record.drinkID }),
                  !pinned.contains(where: { $0.drink == drink && $0.vessel == record.vessel && $0.volumeMl == record.volumeMl })
            else { continue }
            context.insert(Favourite(drink: drink, vessel: record.vessel, volumeMl: record.volumeMl, price: record.price, order: record.order))
        }

        var added = 0
        var touched: Set<DayKey> = []
        var dry: [DayKey] = []
        for record in backup.days {
            guard let day = DayKey(record.date), !daysWithPours.contains(day.number) else { continue }
            if record.status == "alcohol_free" { dry.append(day) }

            let evening = clock.suggestedTime(for: day, after: nil)
            let pours = record.pours ?? []
            if pours.isEmpty, let units = record.units, units > 0 {
                context.insert(Pour(drink: context.unitsDrink(), at: evening, day: day, volumeMl: units * 10, price: record.cost ?? 0, kcalOverride: record.kcal))
                added += 1
                touched.insert(day)
            }
            for (index, pour) in pours.enumerated() where !pourIDs.contains(pour.id ?? UUID()) {
                let time = pour.time ?? evening.addingTimeInterval(Double(index) * 30 * 60)
                let id = pour.id ?? UUID()
                if let volume = pour.volumeMl {
                    let category = pour.category ?? .beer
                    let abv = pour.abv ?? category.defaultABV
                    let vessel = pour.vessel ?? category.defaultVessel
                    let drink = drinks.first { $0.id == pour.drinkID }
                        ?? context.drink(named: pour.name, category: category, abv: abv, vessel: vessel, volumeMl: volume)
                    context.insert(Pour(drink: drink, at: time, day: day, vessel: vessel, volumeMl: volume, price: pour.price ?? 0, id: id))
                } else {
                    context.insert(Pour(drink: context.unitsDrink(), at: time, day: day, volumeMl: (pour.units ?? 0) * 10, price: pour.price ?? 0, kcalOverride: pour.kcal, id: id))
                }
                added += 1
                touched.insert(day)
            }
        }

        let logbook = Logbook(context: context, clock: clock)
        logbook.refresh(touched)
        for day in dry where !touched.contains(day) { logbook.setAlcoholFree(true, on: day) }
        try context.save()
        return added
    }
}

/// A lazily-built export file for `ShareLink`: nothing is generated until the share sheet asks for it.
nonisolated struct ExportFile: Transferable {
    enum Kind: Sendable {
        case json, markdown
    }

    let kind: Kind
    let container: ModelContainer

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { file in
            try await file.write()
        }
        .exportingCondition { $0.kind == .json }
        FileRepresentation(exportedContentType: .plainText) { file in
            try await file.write()
        }
        .exportingCondition { $0.kind == .markdown }
    }

    private func write() async throws -> SentTransferredFile {
        let kind = kind
        let container = container
        let (data, name) = try await MainActor.run {
            let backup = try Exporter.backup(context: container.mainContext, prefs: Prefs())
            let stamp = DayClock(rolloverHour: 0).today.description
            return kind == .json
                ? (try Exporter.json(backup), "groglog-\(stamp).json")
                : (Data(Exporter.markdown(backup).utf8), "groglog-\(stamp).md")
        }
        let url = URL.temporaryDirectory.appending(path: name)
        try data.write(to: url)
        return SentTransferredFile(url)
    }
}

private extension Double {
    var rounded2: Double { (self * 100).rounded() / 100 }
}
