import CloudKit
import Foundation
import GRDB
import WidgetKit

/// The database side of iCloud sync: building outgoing records and applying incoming ones to the log. `Sync` drives
/// it with CloudKit's engine; nothing here uses the network, so all of it can be tested against an in-memory log.
///
/// Each drink, Log tile, entry and manually set day is one record, named for its table and key (`pour-<hex id>`,
/// `day-<number>`), with the row as JSON in `payload` and its last change time in `modifiedAt`. A single payload
/// rather than a field per column means a new column never needs a CloudKit schema change.
nonisolated struct SyncRecords: Sendable {
    let writer: any DatabaseWriter
    let clock: DayClock

    static let zone = CKRecordZone.ID(zoneName: "Log")

    enum Kind: String, CaseIterable {
        case drink, favourite, pour, day
    }

    /// The parts of a day not derived from its entries.
    struct DayMark: Codable {
        var isAlcoholFree: Bool
        var costOverride: Double?
    }

    struct Pending: Hashable {
        let id: CKRecord.ID
        let changedAt: Date
        /// Whether the row still exists: a save if so, a deletion if not.
        let exists: Bool
    }

    // MARK: Going up

    /// Every change not yet acknowledged by iCloud.
    func pending() throws -> [Pending] {
        try writer.read { db in
            try Row.fetchAll(db, sql: "SELECT recordName, changedAt FROM syncPending").map { row in
                let name: String = row["recordName"]
                return Pending(id: Self.id(name), changedAt: row["changedAt"], exists: try Self.exists(name, db))
            }
        }
    }

    /// The record to send for a row, carrying the change tag of the copy iCloud last acknowledged. Nil when the row
    /// was deleted after the change was queued; its deletion is queued separately.
    func record(for id: CKRecord.ID) throws -> CKRecord? {
        try writer.read { db in
            guard let payload = try Self.row(for: id.recordName, db) else { return nil }
            let record = try Self.systemFields(for: id.recordName, db) ?? CKRecord(recordType: Self.kind(of: id.recordName).rawValue, recordID: id)
            record["payload"] = payload
            record["modifiedAt"] = try Date.fetchOne(db, sql: "SELECT changedAt FROM syncPending WHERE recordName = ?", arguments: [id.recordName]) ?? Date()
            return record
        }
    }

    /// Records iCloud has accepted. A save is cleared only if the row has not changed since the uploaded copy, and a
    /// deletion only if the row is still absent; otherwise the change stays queued and is sent again.
    func acknowledge(saved: [CKRecord], deleted: [CKRecord.ID]) throws {
        try writer.write { db in
            for record in saved {
                try db.execute(sql: "INSERT OR REPLACE INTO syncRecord (recordName, systemFields) VALUES (?, ?)",
                               arguments: [record.recordID.recordName, Self.encode(systemFieldsOf: record)])
                guard let sent = record["modifiedAt"] as? Date else { continue }
                try db.execute(sql: "DELETE FROM syncPending WHERE recordName = ? AND changedAt <= ?", arguments: [record.recordID.recordName, sent])
            }
            for id in deleted {
                try db.execute(sql: "DELETE FROM syncRecord WHERE recordName = ?", arguments: [id.recordName])
                if try Self.row(for: id.recordName, db) == nil {
                    try db.execute(sql: "DELETE FROM syncPending WHERE recordName = ?", arguments: [id.recordName])
                }
            }
        }
    }

    /// Keeps a newer server copy's change tag, so the next attempt saves over it rather than conflicting again.
    func remember(_ server: CKRecord) throws {
        try writer.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO syncRecord (recordName, systemFields) VALUES (?, ?)",
                           arguments: [server.recordID.recordName, Self.encode(systemFieldsOf: server)])
        }
    }

    /// Drops the server's metadata for a record, so it is uploaded as new.
    func forgetServerCopy(of id: CKRecord.ID) throws {
        try writer.write { db in try db.execute(sql: "DELETE FROM syncRecord WHERE recordName = ?", arguments: [id.recordName]) }
    }

    /// Queues everything, for a first sync or a new iCloud account. Pours, drinks and tiles have random ids, so the
    /// same log arriving from two devices merges as a union with nothing overwritten.
    func queueEverything() throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM syncRecord; DELETE FROM syncParked; UPDATE syncState SET engine = NULL")
            let now = "strftime('%Y-%m-%d %H:%M:%f', 'now')"
            try db.execute(sql: """
                INSERT OR IGNORE INTO syncPending (recordName, changedAt)
                SELECT 'drink-' || hex(id), \(now) FROM drink
                UNION ALL SELECT 'favourite-' || hex(id), \(now) FROM favourite
                UNION ALL SELECT 'pour-' || hex(id), \(now) FROM pour
                UNION ALL SELECT 'day-' || number, \(now) FROM day WHERE isAlcoholFree OR costOverride IS NOT NULL
                """)
        }
    }

    /// The engine's serialised state from `syncState`, or nil if this log has never synced.
    var engineState: CKSyncEngine.State.Serialization? {
        get throws {
            try writer.read { db in
                try Data.fetchOne(db, sql: "SELECT engine FROM syncState WHERE id = 1").flatMap {
                    try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0)
                }
            }
        }
    }

    /// The CloudKit environment `syncState` and `syncRecord` describe, or nil before the first sync.
    var environment: String? {
        get throws { try writer.read { try String.fetchOne($0, sql: "SELECT environment FROM syncState WHERE id = 1") } }
    }

    func setEnvironment(_ environment: String) throws {
        try writer.write { try $0.execute(sql: "UPDATE syncState SET environment = ? WHERE id = 1", arguments: [environment]) }
    }

    func save(_ state: CKSyncEngine.State.Serialization) throws {
        let data = try JSONEncoder().encode(state)
        try writer.write { try $0.execute(sql: "UPDATE syncState SET engine = ? WHERE id = 1", arguments: [data]) }
    }

    // MARK: Coming down

    /// Applies another device's changes in one transaction. A record replaces the local row when it changed later; a
    /// record for a drink not yet present waits in `syncParked` until the drink arrives. Afterwards, the same drink
    /// seeded separately on two devices is merged into one.
    func apply(modified: [CKRecord], deleted: [(CKRecord.ID, String)]) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE syncState SET applying = 1 WHERE id = 1")
            var touched: Set<DayKey> = []
            var resend: [String] = []

            // Drinks first, so the entries and tiles that refer to them can be inserted.
            let ordered = modified.sorted { Self.order($0.recordID.recordName) < Self.order($1.recordID.recordName) }
            for record in ordered {
                try apply(record, touched: &touched, db)
            }
            // Parked records whose drink has since arrived.
            for row in try Row.fetchAll(db, sql: "SELECT recordName, record FROM syncParked") {
                let data: Data = row["record"]
                guard let record = try NSKeyedUnarchiver.unarchivedObject(ofClass: CKRecord.self, from: data) else { continue }
                try db.execute(sql: "DELETE FROM syncParked WHERE recordName = ?", arguments: [record.recordID.recordName])
                try apply(record, touched: &touched, db)
            }
            for (id, _) in deleted {
                try delete(id.recordName, touched: &touched, resend: &resend, db)
            }

            try Logbook(writer: writer, clock: clock).retotal(touched, db)
            try db.execute(sql: "UPDATE syncState SET applying = 0 WHERE id = 1")

            // Outside `applying`, so the merge's changes are uploaded and other devices converge on the same result.
            let merged = try mergeDuplicates(db)
            try Logbook(writer: writer, clock: clock).retotal(merged, db)
            for name in resend {
                try db.execute(sql: """
                    INSERT INTO syncPending (recordName, changedAt) VALUES (?, strftime('%Y-%m-%d %H:%M:%f', 'now'))
                    ON CONFLICT (recordName) DO UPDATE SET changedAt = excluded.changedAt
                    """, arguments: [name])
            }
        }
        // Local writes reload the widgets through Logbook; these bypass it.
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func apply(_ record: CKRecord, touched: inout Set<DayKey>, _ db: Database) throws {
        let name = record.recordID.recordName
        guard let payload = record["payload"] as? Data, let kind = Kind(rawValue: String(name.prefix { $0 != "-" })) else { return }
        // A local change made after the incoming one wins, and is uploaded in turn.
        if let local = try Date.fetchOne(db, sql: "SELECT changedAt FROM syncPending WHERE recordName = ?", arguments: [name]),
           let theirs = record["modifiedAt"] as? Date, local > theirs {
            try db.execute(sql: "INSERT OR REPLACE INTO syncRecord (recordName, systemFields) VALUES (?, ?)",
                           arguments: [name, Self.encode(systemFieldsOf: record)])
            return
        }
        let decoder = JSONDecoder()
        switch kind {
        case .drink:
            let drink = try decoder.decode(Drink.self, from: payload)
            let before = try Drink.fetchOne(db, key: drink.id)
            try drink.save(db)
            if let before, before.abv != drink.abv || before.category != drink.category {
                let days = try Int.fetchAll(db, sql: "SELECT DISTINCT day FROM pour WHERE drinkId = ?", arguments: [drink.id])
                touched.formUnion(days.map(DayKey.init(number:)))
            }
        case .favourite:
            let favourite = try decoder.decode(Favourite.self, from: payload)
            guard try Drink.exists(db, key: favourite.drinkId) else { return try park(record, db) }
            try favourite.save(db)
        case .pour:
            let pour = try decoder.decode(Pour.self, from: payload)
            guard try Drink.exists(db, key: pour.drinkId) else { return try park(record, db) }
            if let before = try Pour.fetchOne(db, key: pour.id) { touched.insert(before.dayKey) }
            try pour.save(db)
            touched.insert(pour.dayKey)
        case .day:
            guard let number = Int(name.dropFirst("day-".count)) else { return }
            let mark = try decoder.decode(DayMark.self, from: payload)
            var day = try Day.fetchOne(db, key: number) ?? Day(number: number)
            day.isAlcoholFree = mark.isAlcoholFree
            day.costOverride = mark.costOverride
            try day.save(db)
            touched.insert(day.key)
        }
        try db.execute(sql: "INSERT OR REPLACE INTO syncRecord (recordName, systemFields) VALUES (?, ?)",
                       arguments: [name, Self.encode(systemFieldsOf: record)])
        // The incoming copy is now the local state; a stale pending change to the same row would only send it back.
        try db.execute(sql: "DELETE FROM syncPending WHERE recordName = ?", arguments: [name])
    }

    private func delete(_ name: String, touched: inout Set<DayKey>, resend: inout [String], _ db: Database) throws {
        try db.execute(sql: "DELETE FROM syncRecord WHERE recordName = ?; DELETE FROM syncParked WHERE recordName = ?", arguments: [name, name])
        guard let kind = Kind(rawValue: String(name.prefix { $0 != "-" })) else { return }
        // A local change to an entry or day made since wins, as it does against an older edit in `apply`, and is
        // uploaded. Otherwise clearing a day remotely would discard a spend entered here.
        if kind == .pour || kind == .day,
           try Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM syncPending WHERE recordName = ?)", arguments: [name]) == true {
            return
        }
        switch kind {
        case .drink:
            guard let id = Self.uuid(name) else { return }
            // A drink can only be deleted while nothing is logged as it. If this device logged it in the meantime,
            // the drink stays and is uploaded again so other devices restore it.
            if try Pour.filter(Column("drinkId") == id).fetchCount(db) > 0 {
                resend.append(name)
            } else {
                _ = try Drink.deleteOne(db, key: id)
            }
        case .favourite:
            if let id = Self.uuid(name) { _ = try Favourite.deleteOne(db, key: id) }
        case .pour:
            if let id = Self.uuid(name), let pour = try Pour.fetchOne(db, key: id) {
                try pour.delete(db)
                touched.insert(pour.dayKey)
            }
        case .day:
            guard let number = Int(name.dropFirst("day-".count)), var day = try Day.fetchOne(db, key: number) else { return }
            day.isAlcoholFree = false
            day.costOverride = nil
            try day.save(db)
            touched.insert(day.key)
        }
        try db.execute(sql: "DELETE FROM syncPending WHERE recordName = ?", arguments: [name])
    }

    private func park(_ record: CKRecord, _ db: Database) throws {
        let data = try NSKeyedArchiver.archivedData(withRootObject: record, requiringSecureCoding: true)
        try db.execute(sql: "INSERT OR REPLACE INTO syncParked (recordName, record) VALUES (?, ?)", arguments: [record.recordID.recordName, data])
    }

    /// Every device seeds its own Beer, Wine and Units with its own ids, and the same drink can be added on two
    /// devices before they sync. Drinks with the same name and type are merged into the one with the lowest id, so
    /// every device picks the same survivor independently. Identical tiles are merged the same way. Returns the days
    /// whose entries moved, for retotalling.
    func mergeDuplicates(_ db: Database) throws -> Set<DayKey> {
        var touched: Set<DayKey> = []
        let groups = Dictionary(grouping: try Drink.fetchAll(db)) { "\($0.category.rawValue)|\($0.name)" }
        for drinks in groups.values where drinks.count > 1 {
            let keep = drinks.min { $0.id.uuidString < $1.id.uuidString }!
            for drink in drinks where drink.id != keep.id {
                let days = try Int.fetchAll(db, sql: "SELECT DISTINCT day FROM pour WHERE drinkId = ?", arguments: [drink.id])
                touched.formUnion(days.map(DayKey.init(number:)))
                try Pour.filter(Column("drinkId") == drink.id).updateAll(db, Column("drinkId").set(to: keep.id))
                try Favourite.filter(Column("drinkId") == drink.id).updateAll(db, Column("drinkId").set(to: keep.id))
                _ = try drink.delete(db)
            }
        }
        let tiles = Dictionary(grouping: try Favourite.fetchAll(db)) { "\($0.drinkId)|\($0.vessel.rawValue)|\($0.volumeMl)" }
        for favourites in tiles.values where favourites.count > 1 {
            let keep = favourites.min { $0.id.uuidString < $1.id.uuidString }!
            for favourite in favourites where favourite.id != keep.id {
                _ = try favourite.delete(db)
            }
        }
        return touched
    }

    // MARK: Rows and names

    /// The row a record represents, encoded as its payload, or nil if absent. A day with no manual settings counts as
    /// absent: its record is deleted and only its locally derived totals remain.
    private static func row(for name: String, _ db: Database) throws -> Data? {
        let encoder = JSONEncoder()
        switch kind(of: name) {
        case .drink: return try uuid(name).flatMap { try Drink.fetchOne(db, key: $0) }.map { try encoder.encode($0) }
        case .favourite: return try uuid(name).flatMap { try Favourite.fetchOne(db, key: $0) }.map { try encoder.encode($0) }
        case .pour: return try uuid(name).flatMap { try Pour.fetchOne(db, key: $0) }.map { try encoder.encode($0) }
        case .day:
            guard let number = Int(name.dropFirst("day-".count)), let day = try Day.fetchOne(db, key: number),
                  day.isAlcoholFree || day.costOverride != nil else { return nil }
            return try encoder.encode(DayMark(isAlcoholFree: day.isAlcoholFree, costOverride: day.costOverride))
        }
    }

    /// Whether `row(for:)` would find something, checked by key alone: this runs over the whole queue at every launch
    /// and foregrounding, and encoding each row just to test existence dominated the cost.
    private static func exists(_ name: String, _ db: Database) throws -> Bool {
        switch kind(of: name) {
        case .drink: return try uuid(name).map { try Drink.exists(db, key: $0) } ?? false
        case .favourite: return try uuid(name).map { try Favourite.exists(db, key: $0) } ?? false
        case .pour: return try uuid(name).map { try Pour.exists(db, key: $0) } ?? false
        case .day:
            guard let number = Int(name.dropFirst("day-".count)), let day = try Day.fetchOne(db, key: number) else { return false }
            return day.isAlcoholFree || day.costOverride != nil
        }
    }

    private static func systemFields(for name: String, _ db: Database) throws -> CKRecord? {
        guard let data = try Data.fetchOne(db, sql: "SELECT systemFields FROM syncRecord WHERE recordName = ?", arguments: [name]) else { return nil }
        let coder = try NSKeyedUnarchiver(forReadingFrom: data)
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }

    static func encode(systemFieldsOf record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    static func id(_ name: String) -> CKRecord.ID { CKRecord.ID(recordName: name, zoneID: zone) }

    static func kind(of name: String) -> Kind { Kind(rawValue: String(name.prefix { $0 != "-" })) ?? .day }

    /// Drinks before tiles and entries, which refer to them.
    private static func order(_ name: String) -> Int { kind(of: name) == .drink ? 0 : 1 }

    /// The id in `pour-<hex>`, written by SQLite's `hex()` over the 16-byte blob GRDB stores a UUID as.
    static func uuid(_ name: String) -> UUID? {
        let hex = Array(name.drop { $0 != "-" }.dropFirst())
        guard hex.count == 32 else { return nil }
        let parts = [0..<8, 8..<12, 12..<16, 16..<20, 20..<32].map { String(hex[$0]) }
        return UUID(uuidString: parts.joined(separator: "-"))
    }

    static func name(_ kind: Kind, _ id: UUID) -> String {
        "\(kind.rawValue)-" + id.uuidString.replacingOccurrences(of: "-", with: "")
    }
}
