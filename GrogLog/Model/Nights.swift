import Foundation

/// What the body said after a drinking day: overnight HRV in ms, and resting and sleeping heart rate in bpm, from
/// whatever writes them into Health. A night with no reading is missing, not zero, and stays out of every average.
nonisolated struct Night: Equatable {
    var hrv: Double?
    var restingHR: Double?
    /// The mean of the heart rate while asleep. Nearer the night than resting rate, which a watch works out over a
    /// whole day.
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

    var asleep: Double { deep + core + rem + unstaged }

    /// Only where the night was staged; a share of unstaged sleep would read as no REM at all.
    var remShare: Double? { unstaged == 0 && asleep > 0 ? rem / asleep : nil }
}

nonisolated enum SleepStage {
    case awake, core, deep, rem, unstaged
}

nonisolated struct SleepSpan: Equatable {
    let interval: DateInterval
    let stage: SleepStage
    /// Which device recorded it. Two that both recorded a night would count it twice, so only one is taken.
    let source: String
}

nonisolated struct Nights: Equatable {
    var byDay: [DayKey: Night] = [:]

    subscript(day: DayKey) -> Night? { byDay[day] }

    var isEmpty: Bool { byDay.isEmpty }

    var first: DayKey? { byDay.keys.min() }

    /// The latest night before this one with a reading, however long ago.
    func last(_ reading: KeyPath<Night, Double?>, before day: DayKey) -> DayKey? {
        byDay.filter { $0.key < day && $0.value[keyPath: reading] != nil }.keys.max()
    }

    /// Files readings under the night they followed. HRV is only taken overnight — a daytime spot reading after a walk
    /// says nothing about the night — and a night with several is their mean.
    /// Sleep goes to the evening before by when it began, so a bedtime after midnight still counts for that evening.
    /// Sleeping rate takes only the beats inside an asleep stage, leaving out time awake in the night.
    init(hrv: [(Date, Double)] = [], restingHR: [(Date, Double)] = [], sleep: [SleepSpan] = [], heartRate: [(Date, Double)] = [], clock: DayClock) {
        let overnight = hrv.filter { clock.isOvernight($0.0) }
        for (day, values) in Dictionary(grouping: overnight, by: { clock.night(for: $0.0) }) {
            byDay[day, default: Night()].hrv = values.map(\.1).mean
        }
        for (day, values) in Dictionary(grouping: restingHR, by: { clock.night(for: $0.0) }) {
            byDay[day, default: Night()].restingHR = values.map(\.1).mean
        }
        var asleep: [DateInterval] = []
        for (day, spans) in Nights.sleepByNight(sleep, clock: clock) {
            var night = Sleep()
            for span in spans {
                switch span.stage {
                case .deep: night.deep += span.interval.duration
                case .core: night.core += span.interval.duration
                case .rem: night.rem += span.interval.duration
                case .unstaged: night.unstaged += span.interval.duration
                case .awake: night.awake += span.interval.duration
                }
            }
            byDay[day, default: Night()].sleep = night
            asleep += spans.filter { $0.stage != .awake }.map(\.interval)
        }
        asleep.sort { $0.start < $1.start }
        var sleeping: [DayKey: [Double]] = [:]
        var i = 0
        for (date, value) in heartRate.sorted(by: { $0.0 < $1.0 }) {
            while i < asleep.count, asleep[i].end <= date { i += 1 }
            guard i < asleep.count, asleep[i].contains(date) else { continue }
            sleeping[clock.night(for: asleep[i].start), default: []].append(value)
        }
        for (day, values) in sleeping {
            byDay[day, default: Night()].sleepingHR = values.mean
        }
    }

    init(byDay: [DayKey: Night]) { self.byDay = byDay }

    /// Each night's spans from the one device that recorded the most sleep that night.
    static func sleepByNight(_ spans: [SleepSpan], clock: DayClock) -> [DayKey: [SleepSpan]] {
        Dictionary(grouping: spans) { clock.night(for: $0.interval.start) }.mapValues { spans in
            let bySource = Dictionary(grouping: spans, by: \.source)
            return bySource.max { a, b in
                let asleep = { (spans: [SleepSpan]) in spans.filter { $0.stage != .awake }.map(\.interval.duration).reduce(0, +) }
                return asleep(a.value) < asleep(b.value)
            }!.value
        }
    }

    /// The mean over a stretch of nights, or nothing if too few of them have a reading to say anything.
    func mean(_ reading: KeyPath<Night, Double?>, over days: ClosedRange<DayKey>, atLeast minimum: Int = 3) -> Double? {
        let values = days.compactMap { byDay[$0]?[keyPath: reading] }
        return values.count >= minimum ? values.mean : nil
    }
}

nonisolated extension DayClock {
    /// The drinking day a reading answers for. A night runs 8pm to 8pm on a 5am day end: the 11pm reading, the 3am one
    /// and the resting rate Health stamps on the next morning all belong to the evening that caused them.
    func night(for date: Date) -> DayKey { day(for: date.addingTimeInterval(-15 * 3600)) }

    /// 8pm to noon, on a 5am day end.
    func isOvernight(_ date: Date) -> Bool {
        let shifted = date.addingTimeInterval(-15 * 3600)
        return hours(shifted, into: day(for: shifted)) < 16
    }
}

nonisolated extension Array<Double> {
    var mean: Double? { isEmpty ? nil : reduce(0, +) / Double(count) }
}
