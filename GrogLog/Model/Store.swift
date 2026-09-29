import Foundation

/// Where the app, its intents and its widgets all get at the log. The app builds its views around it; intents and
/// widget timelines run outside the view hierarchy, with no environment to read the database from, so they come here.
struct Store {
    let id = UUID()
    let database: AppDatabase
    let prefs: Prefs

    /// One handle to the real log per process, shared with the app's own when it happens to be running. A log that
    /// won't open is kept as the error, so the app can say what went wrong and an intent can fail with it.
    static let real = Result { try live() }

    /// Settings are read afresh on every call rather than taken from `real`: a widget's process can outlive a change
    /// the app makes to them, and would otherwise draw yesterday's goal.
    static func logbook() throws -> Logbook {
        let prefs = Prefs()
        return Logbook(writer: try real.get().database.writer, clock: prefs.clock, mirrorsToHealth: prefs.mirrorsToHealth)
    }

    static var goal: Goal { Prefs().goal }

    private static func live() throws -> Store {
        let prefs = Prefs()
        let database = try AppDatabase.onDisk()
        let logbook = Logbook(writer: database.writer, clock: prefs.clock)
        try Seed.drinksIfNeeded(logbook)
        #if DEBUG
        // `-importBackup <path>` merges a backup file on launch, for moving data between builds.
        if let path = UserDefaults.standard.string(forKey: "importBackup"), let data = FileManager.default.contents(atPath: path) {
            _ = try? Exporter.restore(data, writer: database.writer, prefs: prefs)
        }
        // `-snapshot YES` writes a consistent copy of the log to the group's Library, the one part of a device's
        // containers `devicectl` may copy from, for backing up a phone's log or looking at its sync state.
        if UserDefaults.standard.bool(forKey: "snapshot"),
           let library = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppDatabase.appGroup)?.appending(path: "Library") {
            let copy = library.appending(path: "groglog-snapshot.sqlite")
            try? FileManager.default.removeItem(at: copy)
            try? database.writer.writeWithoutTransaction { try $0.execute(sql: "VACUUM INTO ?", arguments: [copy.path]) }
        }
        #endif
        return Store(database: database, prefs: prefs)
    }

    #if DEBUG
    static func demo() -> Store {
        let prefs = Prefs(store: UserDefaults(suiteName: "demo")!)
        prefs.goal = Goal(isEnabled: true, reductionPercent: 10, periodDays: 7)
        let database = try! AppDatabase.inMemory()
        let logbook = Logbook(writer: database.writer, clock: prefs.clock)
        try! Seed.drinksIfNeeded(logbook)
        try! Seed.sample(logbook)
        return Store(database: database, prefs: prefs)
    }
    #endif
}
