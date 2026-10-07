import CloudKit
import Foundation
import GRDB
import Testing
@testable import GrogLog

private let london: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/London")!
    return calendar
}()

private let clock = DayClock(rolloverHour: 5, calendar: london)

/// One phone: its own log, seeded as a fresh install is, and the sync records over it. iCloud is played by handing
/// one phone's outgoing records to the other. A phone is taken to have finished its first fetch unless `fresh`.
private struct Phone {
    let logbook: Logbook
    let records: SyncRecords

    init(fresh: Bool = false) throws {
        let database = try AppDatabase.inMemory()
        logbook = Logbook(writer: database.writer, clock: clock)
        records = SyncRecords(writer: database.writer, clock: clock)
        try Seed.drinksIfNeeded(logbook)
        if !fresh { try records.finishFetch() }
    }

    func drink(_ name: String) throws -> Drink {
        try logbook.writer.read { try Drink.filter(Column("name") == name).fetchOne($0)! }
    }

    func pours() throws -> [Pour] { try logbook.writer.read { try Pour.fetchAll($0) } }
    func days() throws -> [Day] { try logbook.writer.read { try Day.order(Column("number")).fetchAll($0) } }
    func drinks() throws -> [Drink] { try logbook.writer.read { try Drink.fetchAll($0) } }
    func tiles() throws -> [Favourite] { try logbook.writer.read { try Favourite.fetchAll($0) } }

    /// Everything this phone would send, marked as taken by iCloud.
    func send() throws -> (saved: [CKRecord], deleted: [(CKRecord.ID, String)]) {
        let pending = try records.pending()
        let saved = try pending.filter(\.exists).compactMap { try records.record(for: $0.id) }
        let deleted = pending.filter { !$0.exists }.map { ($0.id, SyncRecords.kind(of: $0.id.recordName).rawValue) }
        try records.acknowledge(saved: saved, deleted: deleted.map(\.0))
        return (saved, deleted)
    }

    func receive(_ changes: (saved: [CKRecord], deleted: [(CKRecord.ID, String)])) throws {
        try records.apply(modified: changes.saved, deleted: changes.deleted)
    }
}

/// Syncs two phones until neither has anything left to send.
private func settle(_ a: Phone, _ b: Phone) throws {
    for _ in 0..<5 {
        let fromA = try a.send()
        try b.receive(fromA)
        let fromB = try b.send()
        try a.receive(fromB)
        if fromA.saved.isEmpty && fromA.deleted.isEmpty && fromB.saved.isEmpty && fromB.deleted.isEmpty { return }
    }
    Issue.record("Still sending after five rounds")
}

private let evening = london.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 20))!

@Suite struct SyncTests {
    @Test func recordNamesRoundTrip() {
        let id = UUID()
        #expect(SyncRecords.uuid(SyncRecords.name(.pour, id)) == id)
    }

    @Test func triggersQueueEveryChangeButNotTotals() throws {
        let phone = try Phone()
        try phone.records.queueEverything()
        _ = try phone.send()
        #expect(try phone.records.pending().isEmpty)

        phone.logbook.log(Serve(try phone.drink("Beer")), at: [evening])
        // The entry, and the tile whose last-used time moved; not the day, whose totals each phone works out.
        let pending = try phone.records.pending().map { SyncRecords.kind(of: $0.id.recordName) }
        #expect(pending.sorted { $0.rawValue < $1.rawValue } == [.favourite, .pour])
    }

    @Test func twoPhonesConvergeWithTheirSeedsMerged() throws {
        let a = try Phone(), b = try Phone()
        try a.records.queueEverything()
        try b.records.queueEverything()
        a.logbook.log(Serve(try a.drink("Beer")), at: [evening])
        b.logbook.log(Serve(try b.drink("Red wine")), at: [evening.addingTimeInterval(3600)])
        b.logbook.setAlcoholFree(true, on: clock.day(for: evening) + 1)

        try settle(a, b)

        #expect(try a.pours().count == 2)
        #expect(Set(try a.pours().map(\.id)) == Set(try b.pours().map(\.id)))
        // Each phone seeded its own Beer; one survives, the same one on both.
        #expect(try a.drinks().filter { $0.name == "Beer" }.count == 1)
        #expect(Set(try a.drinks().map(\.id)) == Set(try b.drinks().map(\.id)))
        #expect(try a.days() == b.days())
        #expect(try a.days().first { $0.number == clock.day(for: evening).number }?.count == 2)
        #expect(try a.days().contains { $0.isAlcoholFree })
    }

    @Test func appliedChangesAreNotSentBack() throws {
        let a = try Phone(), b = try Phone()
        try settle(a, b)
        a.logbook.log(Serve(try a.drink("Beer")), at: [evening])
        try b.receive(try a.send())
        #expect(try b.records.pending().isEmpty)
    }

    @Test func aDeletedEntryGoesEverywhereAndItsDayIsReTotted() throws {
        let a = try Phone(), b = try Phone()
        a.logbook.log(Serve(try a.drink("Beer")), at: [evening])
        try settle(a, b)
        let pour = try b.pours()[0]
        b.logbook.delete(pour)

        try settle(a, b)

        #expect(try a.pours().isEmpty)
        #expect(try a.days().isEmpty)
    }

    @Test func aDrinkLoggedOnOnePhoneSurvivesItsDeletionOnAnother() throws {
        let a = try Phone(), b = try Phone()
        let lager = Drink(name: "Lager", category: .beer, abv: 4, vessel: .pint, volumeMl: 568)
        a.logbook.add(lager)
        try settle(a, b)
        // B deletes the drink while A, offline, logs one.
        b.logbook.delete(try b.drink("Lager"))
        a.logbook.log(Serve(lager), at: [evening])

        try settle(a, b)

        #expect(try a.drinks().contains { $0.id == lager.id })
        #expect(try b.drinks().contains { $0.id == lager.id })
        #expect(try b.pours().count == 1)
    }

    @Test func theLaterEditWins() throws {
        let a = try Phone(), b = try Phone()
        a.logbook.log(Serve(try a.drink("Beer")), at: [evening])
        try settle(a, b)
        let onA = try a.pours()[0], onB = try b.pours()[0]
        a.logbook.update(onA, time: evening, vessel: .pint, volumeMl: 568, price: 4)
        Thread.sleep(forTimeInterval: 0.01)
        b.logbook.update(onB, time: evening, vessel: .pint, volumeMl: 568, price: 7)

        // A's older edit reaches B, which keeps its own; B's newer one then reaches A.
        try settle(a, b)

        #expect(try a.pours()[0].price == 7)
        #expect(try b.pours()[0].price == 7)
    }

    @Test func queueingEverythingForgetsWhatAnotherEnvironmentAcknowledged() throws {
        let phone = try Phone()
        phone.logbook.log(Serve(try phone.drink("Beer")), at: [evening])
        try phone.records.queueEverything()
        _ = try phone.send()
        try phone.records.setEnvironment("development")
        #expect(try phone.records.pending().isEmpty)

        // What production needs when the phone moves to it: every row again, as new records.
        try phone.records.queueEverything()
        try phone.records.setEnvironment("production")
        let pending = try phone.records.pending()
        #expect(pending.contains { $0.id.recordName.hasPrefix("pour-") })
        #expect(try phone.records.environment == "production")
        #expect(try phone.records.record(for: pending[0].id)?.recordChangeTag == nil)
    }

    @Test func anEntryArrivingBeforeItsDrinkWaitsForIt() throws {
        let a = try Phone(), b = try Phone()
        let lager = Drink(name: "Lager", category: .beer, abv: 4, vessel: .pint, volumeMl: 568)
        a.logbook.add(lager)
        a.logbook.log(Serve(lager), at: [evening])
        let sent = try a.send()

        try b.receive((sent.saved.filter { $0.recordID.recordName.hasPrefix("pour-") }, []))
        #expect(try b.pours().isEmpty)
        try b.receive((sent.saved.filter { $0.recordID.recordName.hasPrefix("drink-") }, []))
        #expect(try b.pours().count == 1)
    }

    @Test func aDeletionDoesNotTakeAChangeMadeHereSince() throws {
        let a = try Phone(), b = try Phone()
        let day = clock.day(for: evening)
        b.logbook.setAlcoholFree(true, on: day)
        try settle(a, b)

        // B unticks the dry day, which leaves it nothing to hold and deletes it; A has meanwhile typed a spend.
        b.logbook.setAlcoholFree(false, on: day)
        let fromB = try b.send()
        #expect(!fromB.deleted.isEmpty)
        a.logbook.setSpend(12, on: day)
        try a.receive(fromB)
        #expect(try a.days().first { $0.number == day.number }?.costOverride == 12)

        try settle(a, b)
        #expect(try b.days().first { $0.number == day.number }?.costOverride == 12)
    }

    @Test func aRebuildSendsNothing() throws {
        let phone = try Phone()
        phone.logbook.log(Serve(try phone.drink("Beer")), at: [evening])
        phone.logbook.setAlcoholFree(true, on: clock.day(for: evening) + 1)
        phone.logbook.setSpend(20, on: clock.day(for: evening))
        try phone.records.queueEverything()
        _ = try phone.send()

        phone.logbook.rebuild()
        #expect(try phone.records.pending().isEmpty)
        #expect(try phone.days().map(\.costOverride) == [20, nil])
        #expect(try phone.days().map(\.isAlcoholFree) == [false, true])
    }

    @Test func aFreshInstallDoesNotBringBackATileUnpinnedElsewhere() throws {
        let a = try Phone()
        let beer = try a.drink("Beer")
        let can = try #require(try a.tiles().first { $0.drinkId == beer.id && $0.vessel == .can && $0.volumeMl == 440 })
        a.logbook.unpin(can)
        try a.records.queueEverything()

        // A reinstall seeds the can again, then syncs. Its seeded tiles wait for the fetch.
        let b = try Phone(fresh: true)
        try b.records.queueEverything()
        let early = try b.send()
        #expect(!early.saved.contains { $0.recordID.recordName.hasPrefix("favourite-") })
        try a.receive(early)
        try b.receive(try a.send())
        try b.records.finishFetch()
        try settle(a, b)

        let isCan = { (tile: Favourite) in tile.vessel == .can && tile.volumeMl == 440 }
        #expect(try !a.tiles().contains(where: isCan))
        #expect(try !b.tiles().contains(where: isCan))
        #expect(Set(try a.tiles().map(\.id)) == Set(try b.tiles().map(\.id)))
    }

    @Test func aFreshInstallWithNothingInICloudKeepsAndSendsItsTiles() throws {
        let phone = try Phone(fresh: true)
        try phone.records.queueEverything()
        let tiles = try phone.tiles().count
        #expect(try !phone.send().saved.contains { $0.recordID.recordName.hasPrefix("favourite-") })

        try phone.receive(([], []))
        try phone.records.finishFetch()

        #expect(try phone.tiles().count == tiles)
        #expect(try phone.send().saved.filter { $0.recordID.recordName.hasPrefix("favourite-") }.count == tiles)
    }
}
