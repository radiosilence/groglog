import Foundation
import Observation

/// Keeps the settings that belong to the log, rather than to the phone, in iCloud's key-value store: the goal, the
/// currency and the hour the day ends. A new phone or a reinstall gets them back with the log. The Health switches
/// stay behind, because each device grants its own Health permission.
///
/// Settings live in the app group's defaults, where the widgets read them, so changes from iCloud are written there
/// through `Prefs` like any other change.
@MainActor final class SettingsSync {
    private let prefs: Prefs
    private let logbook: () -> Logbook
    private let cloud = NSUbiquitousKeyValueStore.default
    private var observer: NSObjectProtocol?
    private var running = false

    private nonisolated static let keys = ["rolloverHour", "currency", "goal"]

    init(prefs: Prefs, logbook: @escaping () -> Logbook) {
        self.prefs = prefs
        self.logbook = logbook
    }

    /// The real log's. Demo mode's settings are never synced.
    static let shared: SettingsSync? = (try? Store.real.get()).map { store in
        SettingsSync(prefs: store.prefs) {
            Logbook(writer: store.database.writer, clock: store.prefs.clock, mirrorsToHealth: store.prefs.mirrorsToHealth)
        }
    }

    func start() {
        guard !running else { return }
        running = true
        observer = NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, queue: .main) { [weak self] note in
            let keys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? Self.keys
            MainActor.assumeIsolated { self?.take(keys) }
        }
        cloud.synchronize()
        // A setting never changed on this phone takes iCloud's; one that was goes up if iCloud has none. Between two
        // phones that both set something before syncing, iCloud's copy wins, the same as for any later change.
        let local = UserDefaults.shared
        take(Self.keys.filter { local.object(forKey: $0) == nil || cloud.object(forKey: $0) != nil })
        for key in Self.keys where cloud.object(forKey: key) == nil { send(key) }
        watch()
    }

    func stop() {
        running = false
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    /// Applies iCloud's values. Moving the hour the day ends re-days every entry, as it does when changed in Setup.
    private func take(_ keys: [String]) {
        for key in keys {
            switch key {
            case "rolloverHour":
                guard let hour = cloud.object(forKey: key) as? Int, hour != prefs.rolloverHour else { continue }
                prefs.rolloverHour = hour
                let logbook = logbook()
                Task.detached { logbook.rebuild(reassigningDays: true) }
            case "currency":
                guard let currency = cloud.string(forKey: key), currency != prefs.currency else { continue }
                prefs.currency = currency
            case "goal":
                guard let data = cloud.data(forKey: key), let goal = try? JSONDecoder().decode(Goal.self, from: data), goal != prefs.goal else { continue }
                prefs.goal = goal
            default:
                continue
            }
        }
    }

    private func send(_ key: String) {
        switch key {
        case "rolloverHour": cloud.set(prefs.rolloverHour, forKey: key)
        case "currency": cloud.set(prefs.currency, forKey: key)
        case "goal": cloud.set(try? JSONEncoder().encode(prefs.goal), forKey: key)
        default: break
        }
    }

    /// Sends each change made on this phone. Observation fires once per registration, so it re-registers each time.
    private func watch() {
        guard running else { return }
        let before = (prefs.rolloverHour, prefs.currency, prefs.goal)
        withObservationTracking {
            _ = (prefs.rolloverHour, prefs.currency, prefs.goal)
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.running else { return }
                if self.prefs.rolloverHour != before.0 { self.send("rolloverHour") }
                if self.prefs.currency != before.1 { self.send("currency") }
                if self.prefs.goal != before.2 { self.send("goal") }
                self.watch()
            }
        }
    }
}
