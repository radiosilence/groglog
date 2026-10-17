import Foundation
import GrogLogCore

/// Body readings after a drinking day: overnight HRV in ms, and resting and sleeping heart rate in bpm, from
/// whatever writes them into Health. A night with no reading is nil and is excluded from every average.
nonisolated struct Night: Equatable {
    var hrv: Double?
    var restingHR: Double?
    /// The mean heart rate while asleep. Closer to the night than resting rate, which a watch derives over a whole
    /// day.
    var sleepingHR: Double?
    var sleep: Sleep?
}

/// A night's sleep by stage, in seconds.
nonisolated struct Sleep: Equatable {
    var deep = 0.0
    var core = 0.0
    var rem = 0.0
    /// Asleep with no stage given, as older watches record it.
    var unstaged = 0.0
    var awake = 0.0

    var asleep: Double { sleepAsleep(sleep: row) }

    /// Only for fully staged nights, since unstaged sleep would read as no REM.
    var remShare: Double? { sleepRemShare(sleep: row) }

    private var row: SleepRow { SleepRow(deep: deep, core: core, rem: rem, unstaged: unstaged, awake: awake) }
}

nonisolated enum SleepStage {
    case awake, core, deep, rem, unstaged
}

nonisolated struct SleepSpan: Equatable {
    let interval: DateInterval
    let stage: SleepStage
    /// The recording device. Two devices recording the same night would double it, so only one is used.
    let source: String
}

nonisolated struct Nights: Equatable {
    let byDay: [DayKey: Night]
    private let core: CoreNights

    subscript(day: DayKey) -> Night? { byDay[day] }

    var isEmpty: Bool { byDay.isEmpty }

    var first: DayKey? { core.first().map { DayKey(number: Int($0)) } }

    static func == (lhs: Nights, rhs: Nights) -> Bool { lhs.byDay == rhs.byDay }

    /// The latest night before this one with a reading, however long ago.
    func last(_ reading: KeyPath<Night, Double?>, before day: DayKey) -> DayKey? {
        core.last(kind: Self.kind(reading), before: Int64(day.number)).map { DayKey(number: Int($0)) }
    }

    /// Files readings under the night they followed. HRV is taken only overnight, since a daytime spot reading
    /// reflects the day's activity, and a night with several readings uses their mean. Sleep is filed by when it
    /// began, so a bedtime after midnight counts for the evening before. Sleeping rate uses only beats inside an
    /// asleep stage. Which night a moment belongs to is the calendar's to say; the filing is the shared core's.
    init(hrv: [(Date, Double)] = [], restingHR: [(Date, Double)] = [], sleep: [SleepSpan] = [], heartRate: [(Date, Double)] = [], clock: DayClock) {
        let night = { (date: Date) in Int64(clock.night(for: date).number) }
        let rows = nightsBuild(
            hrv: hrv.filter { clock.isOvernight($0.0) }.map { ReadingIn(night: night($0.0), value: $0.1) },
            restingHr: restingHR.map { ReadingIn(night: night($0.0), value: $0.1) },
            sleep: sleep.map {
                SleepIn(night: night($0.interval.start), start: $0.interval.start.timeIntervalSince1970, end: $0.interval.end.timeIntervalSince1970, stage: $0.stage.kind, source: $0.source)
            },
            heartRate: heartRate.map { SampleIn(at: $0.0.timeIntervalSince1970, value: $0.1) }
        )
        self.init(byDay: Dictionary(uniqueKeysWithValues: rows.map { (DayKey(number: Int($0.day)), Night($0)) }))
    }

    init(byDay: [DayKey: Night]) {
        self.byDay = byDay
        core = CoreNights(rows: byDay.map { day, night in
            NightRow(day: Int64(day.number), hrv: night.hrv, restingHr: night.restingHR, sleepingHr: night.sleepingHR, sleep: night.sleep.map { SleepRow(deep: $0.deep, core: $0.core, rem: $0.rem, unstaged: $0.unstaged, awake: $0.awake) })
        })
    }

    /// The mean over a range of nights, or nil if fewer than `minimum` have a reading.
    func mean(_ reading: KeyPath<Night, Double?>, over days: ClosedRange<DayKey>, atLeast minimum: Int = 3) -> Double? {
        core.mean(kind: Self.kind(reading), first: Int64(days.lowerBound.number), last: Int64(days.upperBound.number), minimum: Int64(minimum))
    }

    /// Each night's first sleep to its last, one span per night, for fetching the heart rate inside them.
    static func nightSpans(_ spans: [SleepSpan], clock: DayClock) -> [DateInterval] {
        nightsNightSpans(sleep: spans.map {
            SleepIn(night: Int64(clock.night(for: $0.interval.start).number), start: $0.interval.start.timeIntervalSince1970, end: $0.interval.end.timeIntervalSince1970, stage: $0.stage.kind, source: $0.source)
        }).map { DateInterval(start: Date(timeIntervalSince1970: $0.start), end: Date(timeIntervalSince1970: $0.end)) }
    }

    /// The three readings are the only ones the core files, so any other key path is a programming error.
    private static func kind(_ reading: KeyPath<Night, Double?>) -> ReadingKind {
        switch reading {
        case \Night.hrv: .hrv
        case \Night.restingHR: .restingHr
        case \Night.sleepingHR: .sleepingHr
        default: preconditionFailure("\(reading) is not a nightly reading")
        }
    }
}

nonisolated extension SleepStage {
    var kind: StageKind {
        switch self {
        case .awake: .awake
        case .core: .core
        case .deep: .deep
        case .rem: .rem
        case .unstaged: .unstaged
        }
    }
}

nonisolated extension Night {
    init(_ row: NightRow) {
        self.init(
            hrv: row.hrv,
            restingHR: row.restingHr,
            sleepingHR: row.sleepingHr,
            sleep: row.sleep.map { Sleep(deep: $0.deep, core: $0.core, rem: $0.rem, unstaged: $0.unstaged, awake: $0.awake) }
        )
    }
}

nonisolated extension DayClock {
    /// The drinking day a reading belongs to. With a 5am day end a night runs 8pm to 8pm, so the 11pm reading, the
    /// 3am one and the resting rate Health stamps on the next morning all belong to the preceding evening.
    func night(for date: Date) -> DayKey { day(for: date.addingTimeInterval(-nightsShiftHours() * 3600)) }

    /// 8pm to noon, on a 5am day end.
    func isOvernight(_ date: Date) -> Bool {
        let shifted = date.addingTimeInterval(-nightsShiftHours() * 3600)
        return nightsIsOvernight(hoursIntoShiftedDay: hours(shifted, into: day(for: shifted)))
    }
}

nonisolated extension Array<Double> {
    var mean: Double? { isEmpty ? nil : reduce(0, +) / Double(count) }
}
