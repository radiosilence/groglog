import Foundation
import GRDB
import Synchronization

/// iOS terminates an app that is suspended while holding a lock on a file in a shared container (0xdead10cc), and
/// the log lives in the app group. GRDB stops taking locks when told the app is going to sleep, and takes them again
/// when told it is awake. Work that runs while the app is in the background, such as an iCloud push, a Shortcut or
/// a rebuild still in progress, runs inside `awake` so the log is open for it and closed again afterwards.
nonisolated enum DatabaseSuspension {
    private static let state = Mutex((background: false, awake: 0))

    static func enterBackground() {
        let suspend = state.withLock { state in
            state.background = true
            return state.awake == 0
        }
        if suspend { post(Database.suspendNotification) }
    }

    static func enterForeground() {
        state.withLock { $0.background = false }
        post(Database.resumeNotification)
    }

    static func awake<T>(_ body: () async throws -> T) async rethrows -> T {
        state.withLock { $0.awake += 1 }
        post(Database.resumeNotification)
        defer {
            let suspend = state.withLock { state in
                state.awake -= 1
                return state.awake == 0 && state.background
            }
            if suspend { post(Database.suspendNotification) }
        }
        return try await body()
    }

    private static func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }
}
