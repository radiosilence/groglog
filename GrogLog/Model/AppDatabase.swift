import Foundation
import GRDB
import os

/// The SQLite database: schema, migrations, and where it lives. Writes go through `Logbook`.
nonisolated struct AppDatabase: Sendable {
    let writer: any DatabaseWriter

    init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    var reader: any DatabaseReader { writer }

    /// The app group shared by the app and its widgets, which run in separate sandboxes.
    static let appGroup = "group.cc.blit.groglog"

    /// The real log, in the group container, in WAL mode so reads never wait on a write.
    static func onDisk() throws -> AppDatabase {
        try AppDatabase(DatabasePool(path: try location().path, configuration: configuration))
    }

    /// Builds before widgets kept the log in Application Support, where only the app can reach it. It is moved the
    /// first time the group container exists. If any step fails the old file remains the log, so a failed move
    /// breaks the widgets but loses no history.
    private static func location() throws -> URL {
        let files = FileManager.default
        let old = try files.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "groglog.sqlite")
        guard let new = files.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?.appending(path: "groglog.sqlite") else { return old }
        guard files.fileExists(atPath: old.path), !files.fileExists(atPath: new.path) else { return new }
        do {
            // Checkpoint the write-ahead log first so the main file holds everything and a left-behind -wal cannot
            // strand the newest drinks.
            let pool = try DatabasePool(path: old.path, configuration: configuration)
            try pool.writeWithoutTransaction { try $0.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)") }
            try pool.close()
            try files.moveItem(at: old, to: new)
            for suffix in ["-wal", "-shm"] { try? files.removeItem(atPath: old.path + suffix) }
            return new
        } catch {
            Logger(subsystem: "cc.blit.groglog", category: "database").error("Couldn't move the log into the app group: \(error)")
            return old
        }
    }

    /// Tests and demo mode.
    static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue(configuration: configuration))
    }

    private static var configuration: Configuration {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        // The app and its widgets write to the same file from separate processes. A write that finds the other
        // holding the lock waits for it; failing at once would drop the drink, since `Logbook` cannot retry it.
        configuration.busyMode = .timeout(5)
        // See `DatabaseSuspension`.
        configuration.observesSuspensionNotifications = true
        configuration.prepareDatabase { db in
            // In WAL mode this survives a crash of the app; only a power loss can lose the last commits. Each drink
            // logged no longer waits on a sync to storage.
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
        }
        return configuration
    }

    /// Append migrations; never edit a shipped one. The database is never erased to change schema.
    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "drink") { t in
                t.primaryKey("id", .blob)
                t.column("name", .text).notNull()
                t.column("category", .text).notNull()
                t.column("abv", .double).notNull()
                t.column("vessel", .text).notNull()
                t.column("volumeMl", .double).notNull()
                t.column("price", .double).notNull()
                t.column("isGeneric", .boolean).notNull()
                t.column("isHidden", .boolean).notNull()
                t.column("sortOrder", .integer).notNull()
            }
            try db.create(table: "favourite") { t in
                t.primaryKey("id", .blob)
                t.belongsTo("drink", onDelete: .cascade).notNull()
                t.column("vessel", .text).notNull()
                t.column("volumeMl", .double).notNull()
                t.column("price", .double).notNull()
                t.column("sortOrder", .integer).notNull()
                t.column("lastUsed", .datetime)
            }
            try db.create(table: "pour") { t in
                t.primaryKey("id", .blob)
                t.belongsTo("drink", onDelete: .restrict).notNull()
                t.column("timestamp", .datetime).notNull()
                t.column("day", .integer).notNull().indexed()
                t.column("vessel", .text).notNull()
                t.column("volumeMl", .double).notNull()
                t.column("price", .double).notNull()
                t.column("kcalOverride", .double)
            }
            try db.create(table: "day") { t in
                t.primaryKey("number", .integer)
                t.column("isAlcoholFree", .boolean).notNull()
                t.column("units", .double).notNull()
                t.column("kcal", .double).notNull()
                t.column("cost", .double).notNull()
                t.column("count", .integer).notNull()
            }
        }
        migrator.registerMigration("v2-spend-override") { db in
            try db.alter(table: "day") { t in
                t.add(column: "costOverride", .double)
            }
        }
        // The catalogue prices a drink when it is adopted, so drinks added before the catalogue had prices were left
        // at £0.00. Only prices still at zero are filled: a price set by hand stands, and logged entries keep the
        // price recorded at the time.
        migrator.registerMigration("v3-prices-for-drinks-added-before-the-catalogue-had-them") { db in
            for var drink in try Drink.filter(Column("price") == 0).fetchAll(db) {
                guard let found = Catalog.price(name: drink.name, category: drink.category, vessel: drink.vessel, ml: drink.volumeMl) else { continue }
                drink.price = found
                try drink.update(db)
            }
            for var favourite in try Favourite.filter(Column("price") == 0).fetchAll(db) {
                guard let drink = try Drink.fetchOne(db, key: favourite.drinkId) else { continue }
                let found = Catalog.price(name: drink.name, category: drink.category, vessel: favourite.vessel, ml: favourite.volumeMl)
                    ?? drink.price(for: favourite.vessel, ml: favourite.volumeMl)
                guard found > 0 else { continue }
                favourite.price = found
                try favourite.update(db)
            }
        }
        // iCloud sync state. Triggers note every changed row in `syncPending` whichever process made the change,
        // since widgets write here too and have no sync code. A pending row only marks a record as possibly changed;
        // its content is read from the table at send time, so a row saved then deleted is sent once, as a deletion.
        // Changes arriving from iCloud are applied with `syncState.applying` set so they are not sent back.
        migrator.registerMigration("v4-sync") { db in
            try db.create(table: "syncPending") { t in
                t.primaryKey("recordName", .text)
                t.column("changedAt", .datetime).notNull()
            }
            // The last copy of each record CloudKit acknowledged, as its encoded system fields. Saving over a record
            // without its change tag is refused as a conflict.
            try db.create(table: "syncRecord") { t in
                t.primaryKey("recordName", .text)
                t.column("systemFields", .blob).notNull()
            }
            // Records that arrived before the drink they refer to, applied once it has.
            try db.create(table: "syncParked") { t in
                t.primaryKey("recordName", .text)
                t.column("record", .blob).notNull()
            }
            try db.create(table: "syncState") { t in
                t.primaryKey("id", .integer).check { $0 == 1 }
                t.column("engine", .blob)
                t.column("applying", .boolean).notNull().defaults(to: false)
            }
            try db.execute(sql: "INSERT INTO syncState (id, applying) VALUES (1, 0)")

            let note = { (name: String) in
                """
                INSERT INTO syncPending (recordName, changedAt) VALUES (\(name), strftime('%Y-%m-%d %H:%M:%f', 'now'))
                ON CONFLICT (recordName) DO UPDATE SET changedAt = excluded.changedAt
                """
            }
            let local = "(SELECT applying FROM syncState WHERE id = 1) = 0"
            for (table, prefix) in [("drink", "drink"), ("favourite", "favourite"), ("pour", "pour")] {
                for (event, row) in [("INSERT", "NEW"), ("UPDATE", "NEW"), ("DELETE", "OLD")] {
                    try db.execute(sql: """
                        CREATE TRIGGER sync_\(table)_\(event.lowercased()) AFTER \(event) ON \(table) WHEN \(local)
                        BEGIN \(note("'\(prefix)-' || hex(\(row).id)")); END
                        """)
                }
            }
            // Only a day's manual settings are synced; its totals are derived from the entries on each device.
            let dayName = { (row: String) in "'day-' || \(row).number" }
            try db.execute(sql: """
                CREATE TRIGGER sync_day_insert AFTER INSERT ON day
                WHEN \(local) AND (NEW.isAlcoholFree OR NEW.costOverride IS NOT NULL)
                BEGIN \(note(dayName("NEW"))); END;
                CREATE TRIGGER sync_day_update AFTER UPDATE OF isAlcoholFree, costOverride ON day
                WHEN \(local) AND (OLD.isAlcoholFree IS NOT NEW.isAlcoholFree OR OLD.costOverride IS NOT NEW.costOverride)
                BEGIN \(note(dayName("NEW"))); END;
                CREATE TRIGGER sync_day_delete AFTER DELETE ON day
                WHEN \(local) AND (OLD.isAlcoholFree OR OLD.costOverride IS NOT NULL)
                BEGIN \(note(dayName("OLD"))); END;
                """)
        }
        // The CloudKit environment the sync state belongs to. Xcode builds sync with development and TestFlight or
        // App Store builds with production. These are separate databases, so a device switching between them must
        // send everything again rather than trust the other's acknowledgements.
        migrator.registerMigration("v5-sync-environment") { db in
            try db.alter(table: "syncState") { t in
                t.add(column: "environment", .text)
            }
        }
        // Entries are always read by day and in time order, so the index holds both and the rows come back sorted.
        migrator.registerMigration("v6-pour-day-time-index") { db in
            try db.create(index: "pour_on_day_timestamp", on: "pour", columns: ["day", "timestamp"])
            try db.drop(index: "pour_on_day")
        }
        return migrator
    }
}
