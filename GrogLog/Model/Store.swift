import Foundation

/// Where the app, its intents and its widgets all get at the log. The app builds its views around it; intents and
/// widget timelines run outside the view hierarchy, with no environment to read the database from, so they come here.
struct Store {
    let id = UUID()
    let database: AppDatabase
    let prefs: Prefs

    /// One handle to the real log per process — shared with the app's own when it happens to be running.
    static let real = live()

    static var logbook: Logbook { real.logbook }

    static var goal: Goal { real.prefs.goal }

    var logbook: Logbook { Logbook(writer: database.writer, clock: prefs.clock, mirrorsToHealth: prefs.mirrorsToHealth) }

    private static func live() -> Store {
        let prefs = Prefs()
        let database = try! AppDatabase.onDisk()
        let logbook = Logbook(writer: database.writer, clock: prefs.clock)
        try! Seed.drinksIfNeeded(logbook)
        #if DEBUG
        // `-importBackup <path>` merges a backup file on launch, for moving data between builds.
        if let path = UserDefaults.standard.string(forKey: "importBackup"), let data = FileManager.default.contents(atPath: path) {
            _ = try? Exporter.restore(data, writer: database.writer, prefs: prefs)
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
