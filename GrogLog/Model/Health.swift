import Foundation
import HealthKit
import os

/// A copy of the log in Health, for the apps and watches that read from there.
///
/// It is a mirror and never a source: the database is authoritative, and a day is rewritten whole rather than
/// patched, so an edit, an undo or a corrected strength moves the samples with it and the copy can't drift.
/// Nothing here is allowed to fail loudly — a refused permission or a missing Health store costs the mirror, not
/// the drink you just logged.
@MainActor final class Health {
    static let shared = Health()

    private let store = HKHealthStore()
    private let beverages = HKQuantityType(.numberOfAlcoholicBeverages)
    private let energy = HKQuantityType(.dietaryEnergyConsumed)
    private let log = Logger(subsystem: "cc.blit.groglog", category: "health")

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Asks for permission and copies the whole log across if it's given. Returns what was actually granted, not
    /// that the sheet was answered, so a refusal leaves the switch off rather than pretending to mirror.
    func enable(_ logbook: Logbook) async -> Bool {
        guard Self.isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [beverages, energy], read: [])
        } catch {
            log.error("Health wouldn't authorise: \(error)")
            return false
        }
        guard store.authorizationStatus(for: beverages) == .sharingAuthorized else { return false }
        await mirrorEverything(logbook)
        return true
    }

    /// Takes GrogLog's samples back out. Health keeps its own copy of everything until told otherwise, and a log
    /// you've stopped mirroring shouldn't keep answering for you.
    func disable() async {
        guard Self.isAvailable else { return }
        for type in [beverages, energy] {
            _ = try? await store.deleteObjects(of: type, predicate: HKQuery.predicateForSamples(withStart: .distantPast, end: .distantFuture))
        }
    }

    func mirrorEverything(_ logbook: Logbook) async {
        let days = (try? await logbook.writer.read { try Day.fetchAll($0).map(\.key) }) ?? []
        await mirror(Set(days), logbook)
    }

    /// Rewrites these days: ours out, the current entries in. Only samples this app wrote are ever removed —
    /// HealthKit won't let an app delete anyone else's.
    func mirror(_ days: Set<DayKey>, _ logbook: Logbook) async {
        guard Self.isAvailable, store.authorizationStatus(for: beverages) == .sharingAuthorized else { return }
        for day in days {
            let start = logbook.clock.start(of: day)
            let end = logbook.clock.end(of: day)
            let range = HKQuery.predicateForSamples(withStart: start, end: end)
            do {
                for type in [beverages, energy] {
                    _ = try await store.deleteObjects(of: type, predicate: range)
                }
                let entries = try await logbook.writer.read { try EntriesRequest(days: day...day).fetch($0) }
                let samples = entries.flatMap(samples(for:))
                if !samples.isEmpty { try await store.save(samples) }
            } catch {
                log.error("Couldn't mirror \(day.number): \(error)")
            }
        }
    }

    private func samples(for entry: Entry) -> [HKQuantitySample] {
        let at = entry.timestamp
        return [
            HKQuantitySample(type: beverages, quantity: HKQuantity(unit: .count(), doubleValue: entry.standardDrinks), start: at, end: at),
            HKQuantitySample(type: energy, quantity: HKQuantity(unit: .kilocalorie(), doubleValue: entry.kcal), start: at, end: at),
        ]
    }
}

nonisolated extension Entry {
    /// Health counts standard drinks, which are not UK units: 17.7 ml of alcohol against 10. Handing it units
    /// would overstate every reading by three quarters.
    var standardDrinks: Double { units * Units.unitMl / Units.standardDrinkMl }
}
