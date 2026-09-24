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
    private let hrv = HKQuantityType(.heartRateVariabilitySDNN)
    private let restingHR = HKQuantityType(.restingHeartRate)
    private let heartRate = HKQuantityType(.heartRate)
    private let sleep = HKCategoryType(.sleepAnalysis)
    private let log = Logger(subsystem: "cc.blit.groglog", category: "health")
    private var queue: Task<Void, Never>?

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
    ///
    /// One rewrite at a time. Two pints tapped in quick succession each ask for the day, and run side by side both
    /// would clear it before either saved, then each save both drinks — four in Health for two drunk.
    func mirror(_ days: Set<DayKey>, _ logbook: Logbook) async {
        let previous = queue
        let rewrite = Task { await previous?.value; await self.rewrite(days, logbook) }
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

    /// Asks to read heart data. Health never says whether reading was allowed — a refusal just looks like an empty
    /// store — so this can only report that the question was answered.
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

    /// Heart readings and sleep, filed under the nights they followed, however far back Health goes: what came before
    /// the log is the baseline worth comparing with. Health labels every HRV as SDNN whatever the device measured, so
    /// the numbers compare with themselves, not with another brand's. Sleep is read for heart rate as well, since it
    /// says which beats were asleep.
    func nights(clock: DayClock, heart: Bool, sleep readsSleep: Bool) async -> Nights {
        guard Self.isAvailable, heart || readsSleep else { return Nights(clock: clock) }
        // Asks only for what hasn't been asked before, so this is silent after the first time.
        _ = await allowReading()
        // Within these spans, or all of it without any.
        let read = { (type: HKQuantityType, unit: HKUnit, spans: [DateInterval]?) async -> [(Date, Double)] in
            let range = spans.map { spans in
                NSCompoundPredicate(orPredicateWithSubpredicates: spans.map { HKQuery.predicateForSamples(withStart: $0.start, end: $0.end) })
            } ?? HKQuery.predicateForSamples(withStart: nil, end: .now)
            let query = HKSampleQueryDescriptor(predicates: [.quantitySample(type: type, predicate: range)], sortDescriptors: [])
            do {
                return try await query.result(for: self.store).map {
                    ($0.startDate.addingTimeInterval($0.endDate.timeIntervalSince($0.startDate) / 2), $0.quantity.doubleValue(for: unit))
                }
            } catch {
                self.log.error("Couldn't read \(type): \(error)")
                return []
            }
        }
        let spans = await sleepSpans()
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let nights = Nights(
            hrv: heart ? await read(hrv, .secondUnit(with: .milli), nil) : [],
            restingHR: heart ? await read(restingHR, bpm, nil) : [],
            sleep: spans,
            // A watch can write a heart rate every minute or two for years; only the nights are wanted, so only those
            // are fetched.
            heartRate: heart && !spans.isEmpty ? await read(heartRate, bpm, Self.nightSpans(spans, clock: clock)) : [],
            clock: clock
        )
        guard !readsSleep else { return nights }
        return Nights(byDay: nights.byDay.mapValues { var night = $0; night.sleep = nil; return night })
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
    /// Health counts standard drinks, which are not UK units: 17.7 ml of alcohol against 10. Handing it units
    /// would overstate every reading by three quarters.
    var standardDrinks: Double { units * Units.unitMl / Units.standardDrinkMl }
}
