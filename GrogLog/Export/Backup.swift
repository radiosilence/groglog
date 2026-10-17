import CoreTransferable
import Foundation
import GRDB
import GrogLogCore
import UniformTypeIdentifiers

/// The backup document is the shared core's: its format, the assembly of an export and the planning of a restore. This
/// file reads the database into what the core asks for, and applies the plan it gives back. Days are listed
/// explicitly, including unlogged ones, so a reader (human or LLM) can tell a dry day from a gap. Import is lenient:
/// only `days[].date` and `days[].status` are required, so other apps' data can be hand-converted (see docs/IMPORT.md).
typealias Backup = BackupDoc

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
        let entries = try Pour.including(required: Pour.drink).order(Column("timestamp")).asRequest(of: Entry.self).fetchAll(db)
        return try backupBuild(input: ExportInput(
            exportedAt: seconds(.now),
            rolloverHour: Int64(settings.rolloverHour),
            currency: settings.currency,
            goalJson: try goalJSON(settings.goal),
            goal: settings.goal.spec(startDay: DayKey(settings.goal.start, in: clock.calendar)),
            today: Int64(clock.today.number),
            firstWeekday: Int64(clock.calendar.firstWeekday),
            days: try Day.fetchAll(db).map(DayRow.init),
            entries: entries.map(ExportEntry.init),
            drinks: try Drink.order(Column("name")).fetchAll(db).map(ExportDrink.init),
            favourites: try Favourite.order(Column("sortOrder")).fetchAll(db).map(ExportFavourite.init)
        ))
    }

    static func json(_ backup: Backup) throws -> Data { backup.json() }

    /// A compact, readable log meant for pasting into a chat with an LLM.
    static func markdown(_ backup: Backup) -> String {
        backup.markdown(now: seconds(.now), format: Reader())
    }

    enum ImportError: LocalizedError {
        case tooLarge
        case unreadable(String)
        case dayEndsAtImpossibleHour(Int)

        var errorDescription: String? {
            switch self {
            case .tooLarge: "The file is too large to be a GrogLog backup."
            case .unreadable(let reason): "The file is not a GrogLog backup: \(reason)"
            case .dayEndsAtImpossibleHour(let hour): "The file sets the day to end at hour \(hour), which is not an hour of the day."
            }
        }
    }

    /// Merges a backup in one transaction without modifying existing data: drinks and entries are matched by id, and
    /// a day that already has drinks keeps them. Settings present in the file are restored first, so entries land on
    /// the correct days. Totals are recomputed for only the touched days.
    @MainActor @discardableResult
    static func restore(_ data: Data, writer: any DatabaseWriter, prefs: Prefs) throws -> Int {
        let backup: Backup
        do {
            backup = try BackupDoc.parse(data: data)
        } catch let error as GrogLogCore.BackupError {
            switch error {
            case .Unreadable(let reason): throw ImportError.unreadable(reason)
            case .DayEndsAtImpossibleHour(let hour): throw ImportError.dayEndsAtImpossibleHour(Int(hour))
            }
        }
        let goal = try backup.goalJson().map(decodeGoal)
        let movesDayEnd = backup.dayStartsAtHour().map { Int($0) != prefs.rolloverHour } ?? false
        if let hour = backup.dayStartsAtHour() { prefs.rolloverHour = Int(hour) }
        if let currency = backup.currency() { prefs.currency = currency }
        if let goal { prefs.goal = goal }
        let logbook = Logbook(writer: writer, clock: prefs.clock, mirrorsToHealth: prefs.mirrorsToHealth)
        var added = 0

        try logbook.bulk { db in
            let plan = backup.plan(snapshot: try snapshot(db, today: logbook.clock.today))
            var evenings: [Int: Date] = [:]
            for op in plan.ops {
                switch op {
                case let .insertDrink(id, name, category, abv, vessel, volumeMl, price, isGeneric, isHidden, sortOrder):
                    try Drink(id: UUID(uuidString: id)!, name: name, category: DrinkCategory(rawValue: category)!, abv: abv, vessel: Vessel(rawValue: vessel)!, volumeMl: volumeMl, price: price, isGeneric: isGeneric, isHidden: isHidden, sortOrder: Int(sortOrder)).insert(db)
                case let .insertFavourite(drinkId, vessel, volumeMl, price, sortOrder):
                    try Favourite(drinkId: UUID(uuidString: drinkId)!, vessel: Vessel(rawValue: vessel)!, volumeMl: volumeMl, price: price, sortOrder: Int(sortOrder)).insert(db)
                case let .markAlcoholFree(day):
                    var row = try Day.fetchOne(db, key: Int(day)) ?? Day(number: Int(day))
                    row.isAlcoholFree = true
                    try row.save(db)
                case let .setSpend(day, amount):
                    var row = try Day.fetchOne(db, key: Int(day)) ?? Day(number: Int(day))
                    row.costOverride = amount
                    try row.save(db)
                case let .insertPour(id, drinkId, time, offset, day, vessel, volumeMl, price, kcalOverride, abvOverride):
                    let timestamp: Date
                    if let time {
                        timestamp = Date(timeIntervalSince1970: TimeInterval(time))
                    } else {
                        let evening = evenings[Int(day)] ?? logbook.clock.suggestedTime(for: DayKey(number: Int(day)), after: nil)
                        evenings[Int(day)] = evening
                        timestamp = evening.addingTimeInterval(Double(offset) * 60)
                    }
                    try Pour(id: UUID(uuidString: id)!, drinkId: UUID(uuidString: drinkId)!, timestamp: timestamp, day: Int(day), vessel: Vessel(rawValue: vessel)!, volumeMl: volumeMl, price: price, kcalOverride: kcalOverride, abvOverride: abvOverride).insert(db)
                }
            }
            added = Int(plan.added)
            return Set(plan.touched.map { DayKey(number: Int($0)) })
        }
        // Existing entries were assigned days by the old hour and imported ones by the new one, so every day is
        // reassigned.
        if movesDayEnd { Task.detached { logbook.rebuild(reassigningDays: true) } }
        return added
    }

    /// The goal as a backup holds it: dates as ISO 8601, the way the file has always written them.
    private static func goalJSON(_ goal: Goal) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(goal), as: UTF8.self)
    }

    private static func decodeGoal(_ json: String) throws -> Goal {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Goal.self, from: Data(json.utf8))
    }

    /// Whole seconds, which is all a backup keeps of a moment.
    fileprivate static func seconds(_ date: Date) -> Int64 { Int64(date.timeIntervalSince1970.rounded(.down)) }

    private static func snapshot(_ db: Database, today: DayKey) throws -> RestoreSnapshot {
        RestoreSnapshot(
            today: Int64(today.number),
            drinks: try Drink.fetchAll(db).map { SnapshotDrink(id: $0.id.uuidString, name: $0.name, category: $0.category.rawValue, abv: $0.abv) },
            favourites: try Favourite.fetchAll(db).map { SnapshotFavourite(drinkId: $0.drinkId.uuidString, vessel: $0.vessel.rawValue, volumeMl: $0.volumeMl) },
            pourIds: try Pour.select(Column("id"), as: UUID.self).fetchAll(db).map(\.uuidString),
            daysWithPours: try Pour.select(Column("day"), as: Int.self).distinct().fetchAll(db).map { Int64($0) }
        )
    }

    /// How a reader of the markdown sees numbers and dates: in this phone's language and region.
    private final class Reader: MarkdownFormat {
        func units(value: Double) -> String { value.unitsText }
        func money(value: Double, currency: String) -> String { value.money(currency) }
        func volume(ml: Double) -> String { ml.volumeText }
        func abv(abv: Double) -> String { abv.abvText }
        func dateTime(seconds: Int64) -> String { Date(timeIntervalSince1970: TimeInterval(seconds)).formatted(date: .abbreviated, time: .shortened) }
        func date(seconds: Int64) -> String { Date(timeIntervalSince1970: TimeInterval(seconds)).formatted(date: .abbreviated, time: .omitted) }
        func time(seconds: Int64) -> String { Date(timeIntervalSince1970: TimeInterval(seconds)).formatted(date: .omitted, time: .shortened) }
    }
}

nonisolated private extension ExportEntry {
    init(_ entry: Entry) {
        self.init(
            id: entry.id.uuidString,
            time: Exporter.seconds(entry.timestamp),
            day: Int64(entry.day),
            name: entry.name,
            category: entry.category.rawValue,
            vessel: entry.vessel.rawValue,
            volumeMl: entry.volumeMl,
            abv: entry.abv,
            units: entry.units,
            kcal: entry.kcal,
            price: entry.price,
            drinkId: entry.drink.id.uuidString
        )
    }
}

nonisolated private extension ExportDrink {
    init(_ drink: Drink) {
        self.init(id: drink.id.uuidString, name: drink.name, category: drink.category.rawValue, abv: drink.abv, vessel: drink.vessel.rawValue, volumeMl: drink.volumeMl, price: drink.price, isGeneric: drink.isGeneric, isHidden: drink.isHidden)
    }
}

nonisolated private extension ExportFavourite {
    init(_ favourite: Favourite) {
        self.init(drinkId: favourite.drinkId.uuidString, vessel: favourite.vessel.rawValue, volumeMl: favourite.volumeMl, price: favourite.price, sortOrder: Int64(favourite.sortOrder))
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
