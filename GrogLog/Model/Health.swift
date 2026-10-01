import Foundation
import HealthKit
import os

/// A copy of the log in Health, for the apps and watches that read from there.
///
/// The database is authoritative and Health only mirrors it. A day is rewritten whole rather than patched, so an
/// edit, an undo or a corrected strength moves the samples with it and the copy cannot drift. Failures here are
/// logged and swallowed: a refused permission or a missing Health store must never block logging a drink.
@MainActor final class Health {
    static let shared = Health()

    private let store = HKHealthStore()
    private let beverages = HKQuantityType(.numberOfAlcoholicBeverages)
    private let energy = HKQuantityType(.dietaryEnergyConsumed)
    private let hrv = HKQuantityType(.heartRateVariabilitySDNN)
    private let restingHR = HKQuantityType(.restingHeartRate)
    private let heartRate = HKQuantityType(.heartRate)
    private let sleep = HKCategoryType(.sleepAnalysis)
    private let log = Logger(subsystem: "cc.blit.groglog", category: "health")
    private var queue: Task<Void, Never>?

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Asks for permission and copies the whole log across if it is given. Returns whether sharing was granted,
    /// so a refusal leaves the switch off.
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

    /// Removes GrogLog's samples, which Health would otherwise keep reporting after mirroring stops.
    func disable() async {
        guard Self.isAvailable else { return }
        for type in [beverages, energy] {
            _ = try? await store.deleteObjects(of: type, predicate: HKQuery.predicateForSamples(withStart: .distantPast, end: .distantFuture))
        }
    }

    /// Rewrites the whole log in one pass: this app's samples out, every entry in. Going day by day costs four
    /// round trips per day, which takes minutes on a long log and blocks drinks logged in the meantime.
    func mirrorEverything(_ logbook: Logbook) async {
        let previous = queue
        let rewrite = Task { await previous?.value; await DatabaseSuspension.awake { await self.rewriteAll(logbook) } }
        queue = rewrite
        await rewrite.value
    }

    private func rewriteAll(_ logbook: Logbook) async {
        guard Self.isAvailable, store.authorizationStatus(for: beverages) == .sharingAuthorized else { return }
        do {
            for type in [beverages, energy] {
                _ = try await store.deleteObjects(of: type, predicate: HKQuery.predicateForSamples(withStart: .distantPast, end: .distantFuture))
            }
            let entries = try await logbook.writer.read { try Pour.including(required: Pour.drink).asRequest(of: Entry.self).fetchAll($0) }
            let samples = entries.flatMap(samples(for:))
            for start in stride(from: 0, to: samples.count, by: 2000) {
                try await store.save(Array(samples[start..<min(start + 2000, samples.count)]))
            }
        } catch {
            log.error("Couldn't mirror the log: \(error)")
        }
    }

    /// Rewrites these days: this app's samples out, the current entries in. HealthKit only lets an app delete the
    /// samples it wrote.
    ///
    /// Rewrites are serialised. Two drinks logged in quick succession each rewrite the day; run concurrently, both
    /// would clear it before either saved and each would then save both drinks, doubling the count.
    func mirror(_ days: Set<DayKey>, _ logbook: Logbook) async {
        let previous = queue
        let rewrite = Task { await previous?.value; await DatabaseSuspension.awake { await self.rewrite(days, logbook) } }
        queue = rewrite
        await rewrite.value
    }

    private func rewrite(_ days: Set<DayKey>, _ logbook: Logbook) async {
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

    /// Asks to read heart data. Health never reveals whether reading was allowed (a refusal looks like an empty
    /// store), so this only reports that the request completed.
    func allowReading() async -> Bool {
        guard Self.isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: [hrv, restingHR, heartRate, sleep])
            return true
        } catch {
            log.error("Health wouldn't authorise reading: \(error)")
            return false
        }
    }

    /// Heart readings and sleep, filed under the nights they followed, as far back as Health goes: readings from
    /// before the log began form the baseline. Health labels every HRV as SDNN whatever the device measured, so the
    /// numbers are only comparable with readings from the same source. Sleep is also read for heart rate, since it
    /// identifies which beats were asleep.
    func nights(clock: DayClock, heart: Bool, sleep readsSleep: Bool) async -> Nights {
        guard Self.isAvailable, heart || readsSleep else { return Nights(clock: clock) }
        // Only prompts for types not yet requested, so this is silent after the first time.
        _ = await allowReading()
        let store = store, log = log
        // Restricted to the spans when given, otherwise unbounded.
        let read = { (type: HKQuantityType, unit: HKUnit, spans: [DateInterval]?) async -> [(Date, Double)] in
            do {
                return try await Self.quantities(type, unit, within: spans, store)
            } catch {
                log.error("Couldn't read \(type): \(error)")
                return []
            }
        }
        let spans = await sleepSpans()
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let hrvReadings = heart ? await read(hrv, .secondUnit(with: .milli), nil) : []
        let resting = heart ? await read(restingHR, bpm, nil) : []
        // A watch can write a heart rate every minute or two for years, so only the nights are fetched.
        let beats = heart && !spans.isEmpty ? await read(heartRate, bpm, Self.nightSpans(spans, clock: clock)) : []
        let nights = await Self.file(hrv: hrvReadings, restingHR: resting, sleep: spans, heartRate: beats, clock: clock)
        guard !readsSleep else { return nights }
        return Nights(byDay: nights.byDay.mapValues { var night = $0; night.sleep = nil; return night })
    }

    /// Runs off the main thread: years of readings are filed here, and Reports asks again each time the app returns
    /// to it.
    @concurrent nonisolated private static func quantities(_ type: HKQuantityType, _ unit: HKUnit, within spans: [DateInterval]?, _ store: HKHealthStore) async throws -> [(Date, Double)] {
        let range = spans.map { spans in
            NSCompoundPredicate(orPredicateWithSubpredicates: spans.map { HKQuery.predicateForSamples(withStart: $0.start, end: $0.end) })
        } ?? HKQuery.predicateForSamples(withStart: nil, end: .now)
        let query = HKSampleQueryDescriptor(predicates: [.quantitySample(type: type, predicate: range)], sortDescriptors: [])
        return try await query.result(for: store).map {
            ($0.startDate.addingTimeInterval($0.endDate.timeIntervalSince($0.startDate) / 2), $0.quantity.doubleValue(for: unit))
        }
    }

    @concurrent nonisolated private static func file(hrv: [(Date, Double)], restingHR: [(Date, Double)], sleep: [SleepSpan], heartRate: [(Date, Double)], clock: DayClock) async -> Nights {
        Nights(hrv: hrv, restingHR: restingHR, sleep: sleep, heartRate: heartRate, clock: clock)
    }

    private func sleepSpans() async -> [SleepSpan] {
        let query = HKSampleQueryDescriptor(predicates: [.categorySample(type: sleep, predicate: HKQuery.predicateForSamples(withStart: nil, end: .now))], sortDescriptors: [])
        do {
            return try await query.result(for: store).compactMap { sample in
                let stage: SleepStage? = switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
                case .awake: .awake
                case .asleepCore: .core
                case .asleepDeep: .deep
                case .asleepREM: .rem
                case .asleepUnspecified: .unstaged
                default: nil
                }
                return stage.map { SleepSpan(interval: DateInterval(start: sample.startDate, end: sample.endDate), stage: $0, source: sample.sourceRevision.source.bundleIdentifier) }
            }
        } catch {
            log.error("Couldn't read sleep: \(error)")
            return []
        }
    }

    /// Each night's first sleep to its last, one span per night, for fetching the heart rate inside them.
    nonisolated static func nightSpans(_ spans: [SleepSpan], clock: DayClock) -> [DateInterval] {
        Nights.sleepByNight(spans, clock: clock).values.map { spans in
            let asleep = spans.filter { $0.stage != .awake }.map(\.interval)
            return DateInterval(start: asleep.map(\.start).min() ?? spans[0].interval.start, end: asleep.map(\.end).max() ?? spans[0].interval.end)
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
    /// Health counts standard drinks (17.7 ml of alcohol), not UK units (10 ml). Passing units would overstate
    /// every reading by three quarters.
    var standardDrinks: Double { units * Units.unitMl / Units.standardDrinkMl }
}
