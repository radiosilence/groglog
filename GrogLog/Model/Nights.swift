import Foundation

/// What the body said after a drinking day: overnight HRV in ms and resting heart rate in bpm, from whatever writes
/// them into Health. A night with no reading is missing, not zero, and stays out of every average.
nonisolated struct Night: Equatable {
    var hrv: Double?
    var restingHR: Double?
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
    init(hrv: [(Date, Double)] = [], restingHR: [(Date, Double)] = [], clock: DayClock) {
        let overnight = hrv.filter { clock.isOvernight($0.0) }
        for (day, values) in Dictionary(grouping: overnight, by: { clock.night(for: $0.0) }) {
            byDay[day, default: Night()].hrv = values.map(\.1).mean
        }
        for (day, values) in Dictionary(grouping: restingHR, by: { clock.night(for: $0.0) }) {
            byDay[day, default: Night()].restingHR = values.map(\.1).mean
        }
    }

    init(byDay: [DayKey: Night]) { self.byDay = byDay }

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
