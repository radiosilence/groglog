import CloudKit
import Foundation
import GRDB

/// The database's side of iCloud sync: what goes up, and what comes down applied to the log. `Sync` drives it with
/// CloudKit's engine; nothing here talks to the network, so all of it can be tested against an in-memory log.
///
/// Each drink, Log tile, entry and hand-set day is one record, named for its table and key (`pour-<hex id>`,
/// `day-<number>`), with the row itself as JSON in `payload` and the time it last changed in `modifiedAt`. A payload
/// rather than a field per column means a new column never needs a CloudKit schema change.
nonisolated struct SyncRecords: Sendable {
    let writer: any DatabaseWriter
    let clock: DayClock

    static let zone = CKRecordZone.ID(zoneName: "Log")

    enum Kind: String, CaseIterable {
        case drink, favourite, pour, day
    }

    /// What a day carries that isn't worked out from its entries.
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
                return Pending(id: Self.id(name), changedAt: row["changedAt"], exists: try Self.row(for: name, db) != nil)
            }
        }
    }

    /// The record to send for a row, carrying the change tag of the copy iCloud last acknowledged. Nil when the row
    /// has gone since the change was queued; its deletion is queued separately.
    func record(for id: CKRecord.ID) throws -> CKRecord? {
        try writer.read { db in
            guard let payload = try Self.row(for: id.recordName, db) else { return nil }
            let record = try Self.systemFields(for: id.recordName, db) ?? CKRecord(recordType: Self.kind(of: id.recordName).rawValue, recordID: id)
            record["payload"] = payload
            record["modifiedAt"] = try Date.fetchOne(db, sql: "SELECT changedAt FROM syncPending WHERE recordName = ?", arguments: [id.recordName]) ?? Date()
            return record
        }
    }

    /// Records iCloud has taken. A save is done with only if the row hasn't changed again since the copy that went
    /// up, and a deletion only if the row is still gone; otherwise the change stays queued and goes again.
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

    /// Drops what iCloud knew about a record, so it goes up as new.
    func forgetServerCopy(of id: CKRecord.ID) throws {
        try writer.write { db in try db.execute(sql: "DELETE FROM syncRecord WHERE recordName = ?", arguments: [id.recordName]) }
    }

    /// Queues everything, for a first sync or a new iCloud account. Pours, drinks and tiles have random ids, so the
    /// same log arriving from two phones is a union: nothing on either is overwritten.
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

    /// Whether this log has ever synced. CloudKit's engine keeps its place in `syncState`.
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

    /// Applies what another device changed, in one transaction. A record wins over the local row when it changed
    /// later; a record for a drink this phone hasn't heard of yet waits in `syncParked` until the drink arrives.
    /// Afterwards, drinks that are the same drink seeded separately on two phones are merged into one.
    func apply(modified: [CKRecord], deleted: [(CKRecord.ID, String)]) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE syncState SET applying = 1 WHERE id = 1")
            var touched: Set<DayKey> = []
            var resend: [String] = []

            // Drinks first, so the entries and tiles that refer to them can go in.
            let ordered = modified.sorted { Self.order($0.recordID.recordName) < Self.order($1.recordID.recordName) }
            for record in ordered {
                try apply(record, touched: &touched, db)
            }
            // Parked records whose drink has now arrived.
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

            // Outside `applying`, so what merging changes goes back up and the other phones merge the same way.
            let merged = try mergeDuplicates(db)
            try Logbook(writer: writer, clock: clock).retotal(merged, db)
            for name in resend {
                try db.execute(sql: """
                    INSERT INTO syncPending (recordName, changedAt) VALUES (?, strftime('%Y-%m-%d %H:%M:%f', 'now'))
                    ON CONFLICT (recordName) DO UPDATE SET changedAt = excluded.changedAt
                    """, arguments: [name])
            }
        }
    }

    private func apply(_ record: CKRecord, touched: inout Set<DayKey>, _ db: Database) throws {
        let name = record.recordID.recordName
        guard let payload = record["payload"] as? Data, let kind = Kind(rawValue: String(name.prefix { $0 != "-" })) else { return }
        // A change made here after the incoming one was made stands, and goes up in its turn.
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
        // What came down is now what's here; a stale local change to the same row would only send it back.
        try db.execute(sql: "DELETE FROM syncPending WHERE recordName = ?", arguments: [name])
    }

    private func delete(_ name: String, touched: inout Set<DayKey>, resend: inout [String], _ db: Database) throws {
        try db.execute(sql: "DELETE FROM syncRecord WHERE recordName = ?; DELETE FROM syncParked WHERE recordName = ?", arguments: [name, name])
        guard let kind = Kind(rawValue: String(name.prefix { $0 != "-" })) else { return }
        switch kind {
        case .drink:
            guard let id = Self.uuid(name) else { return }
            // A drink can only be deleted while nothing has been logged as it. If this phone logged it in the
            // meantime, the drink stays and goes back up, so the other phones get it again.
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

    /// Every phone seeds its own Beer, Wine and Units with its own ids, and the same drink can be added on two phones
    /// before they sync. Drinks with the same name and type become one, the lowest id, so every phone picks the same
    /// survivor without asking the others. Tiles that end up identical are merged the same way. Returns the days whose
    /// entries moved, for re-totting.
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

    /// The row a record stands for, as the payload it's sent with, or nil if it's gone. A day with nothing set by
    /// hand counts as gone: its record is deleted and only its totals, worked out here, remain.
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
