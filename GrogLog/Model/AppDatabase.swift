import Foundation
import GRDB

/// The SQLite database: schema, migrations, and where it lives. Writes go through `Logbook`.
nonisolated struct AppDatabase: Sendable {
    let writer: any DatabaseWriter

    init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    var reader: any DatabaseReader { writer }

    /// The real log, in Application Support, in WAL mode so reads never wait on a write.
    static func onDisk() throws -> AppDatabase {
        let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return try AppDatabase(DatabasePool(path: folder.appending(path: "groglog.sqlite").path, configuration: configuration))
    }

    /// Tests and demo mode.
    static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue(configuration: configuration))
    }

    private static var configuration: Configuration {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
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
        return migrator
    }
}
