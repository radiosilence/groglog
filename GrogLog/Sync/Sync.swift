import CloudKit
import GRDB
import Synchronization
import UIKit
import os

/// Keeps the log in step with the user's private iCloud database through `CKSyncEngine`, which schedules the work,
/// retries it, and wakes the app when another device changes something. What goes up is whatever `syncPending` says
/// changed; what comes down goes through `SyncRecords.apply`.
///
/// Only the app syncs. A widget writes to the same database from its own process, and its changes are queued by the
/// database's triggers and sent when the app next comes to the front.
nonisolated final class Sync: CKSyncEngineDelegate, Sendable {
    static let container = "iCloud.cc.blit.groglog"

    private let records: SyncRecords
    private let engine = Mutex<CKSyncEngine?>(nil)
    private let watching = Mutex<AnyDatabaseCancellable?>(nil)
    private let log = Logger(subsystem: "cc.blit.groglog", category: "sync")

    init(writer: any DatabaseWriter, clock: DayClock) {
        records = SyncRecords(writer: writer, clock: clock)
    }

    /// The real log's. Demo mode's database is never synced.
    @MainActor static let shared: Sync? = (try? Store.real.get()).map { Sync(writer: $0.database.writer, clock: $0.prefs.clock) }

    /// Starts syncing. The first time, or after the iCloud account changes, the whole log is queued.
    func start() {
        guard engine.withLock({ $0 == nil }) else { return }
        do {
            let state = try records.engineState
            if state == nil { try records.queueEverything() }
            let database = CKContainer(identifier: Self.container).privateCloudDatabase
            var configuration = CKSyncEngine.Configuration(database: database, stateSerialization: try records.engineState, delegate: self)
            configuration.automaticallySync = true
            let engine = CKSyncEngine(configuration)
            self.engine.withLock { $0 = engine }
            if state == nil {
                engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: SyncRecords.zone))])
            }
            queuePending()
            // This process's own writes are queued as they commit. The callback runs on the database's queue, where
            // reading again isn't allowed, so the queueing happens after it.
            let observation = DatabaseRegionObservation(tracking: Table("syncPending"))
            let cancellable = observation.start(in: records.writer) { [log] error in
                log.error("Stopped watching for changes: \(error)")
            } onChange: { [weak self] _ in
                Task { self?.queuePending() }
            }
            watching.withLock { $0 = cancellable }
            // Another device's change arrives as a silent push, which the engine answers by fetching.
            Task { @MainActor in UIApplication.shared.registerForRemoteNotifications() }
        } catch {
            log.error("Couldn't start sync: \(error)")
        }
    }

    /// Stops syncing and leaves everything where it is, on the phone and in iCloud.
    func stop() {
        watching.withLock {
            $0?.cancel()
            $0 = nil
        }
        let stopped = engine.withLock { engine in
            defer { engine = nil }
            return engine
        }
        if let stopped { Task { await stopped.cancelOperations() } }
    }

    /// Hands the engine every change the database has queued. Called after this process writes, and when the app
    /// comes to the front, which is when a widget's writes are first noticed.
    func queuePending() {
        guard let engine = engine.withLock({ $0 }) else { return }
        do {
            let pending = try records.pending()
            let saves = pending.filter(\.exists).map(\.id)
            let deletes = pending.filter { !$0.exists }.map(\.id)
            // A row saved and then deleted before either went is sent once, as whichever it is now.
            engine.state.remove(pendingRecordZoneChanges: saves.map { .deleteRecord($0) } + deletes.map { .saveRecord($0) })
            engine.state.add(pendingRecordZoneChanges: saves.map { .saveRecord($0) } + deletes.map { .deleteRecord($0) })
        } catch {
            log.error("Couldn't read pending changes: \(error)")
        }
    }

    // MARK: CKSyncEngineDelegate

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        do {
            switch event {
            case .stateUpdate(let update):
                try records.save(update.stateSerialization)

            case .accountChange(let change):
                switch change.changeType {
                case .signIn, .switchAccounts:
                    // A different iCloud account has none of this log, and whatever it has is merged in.
                    try records.queueEverything()
                    syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: SyncRecords.zone))])
                    queuePending()
                case .signOut:
                    // Signing out of iCloud leaves the log on the phone. It goes up again whole on the next sign-in.
                    try records.queueEverything()
                @unknown default:
                    break
                }

            case .fetchedDatabaseChanges(let changes):
                // The zone gone from iCloud (deleted in Settings, or reset) means iCloud no longer has the log. The
                // phone still does, and puts it back.
                if changes.deletions.contains(where: { $0.zoneID == SyncRecords.zone }) {
                    try records.queueEverything()
                    syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: SyncRecords.zone))])
                    queuePending()
                }

            case .fetchedRecordZoneChanges(let changes):
                try records.apply(
                    modified: changes.modifications.map(\.record),
                    deleted: changes.deletions.map { ($0.recordID, $0.recordType) }
                )
                queuePending()

            case .sentRecordZoneChanges(let sent):
                try records.acknowledge(saved: sent.savedRecords, deleted: sent.deletedRecordIDs)
                try resolve(sent.failedRecordSaves, syncEngine)

            default:
                break
            }
        } catch {
            log.error("Sync event failed: \(error)")
        }
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { id in
            do {
                return try self.records.record(for: id)
            } catch {
                self.log.error("Couldn't read \(id.recordName): \(error)")
                return nil
            }
        }
    }

    /// What iCloud refused. A newer copy there is applied here if it's the later change, and overwritten if this
    /// phone's is; either way the next save carries the right change tag.
    private func resolve(_ failures: [CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave], _ engine: CKSyncEngine) throws {
        var retry: [CKRecord.ID] = []
        for failure in failures {
            let id = failure.record.recordID
            switch failure.error.code {
            case .serverRecordChanged:
                guard let server = failure.error.serverRecord else { continue }
                // `apply` keeps this phone's row if it changed after the server's copy, and records the server's
                // change tag either way.
                try records.apply(modified: [server], deleted: [])
                retry.append(id)
            case .unknownItem:
                // Deleted from iCloud since this phone last heard of it. Sent again as new, since the row is still here.
                try records.forgetServerCopy(of: id)
                retry.append(id)
            case .zoneNotFound:
                engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: SyncRecords.zone))])
                try records.forgetServerCopy(of: id)
                retry.append(id)
            case .networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited, .zoneBusy, .notAuthenticated, .operationCancelled:
                // The engine retries these itself.
                break
            default:
                log.error("Couldn't save \(id.recordName): \(failure.error)")
            }
        }
        if !retry.isEmpty { queuePending() }
    }
}
