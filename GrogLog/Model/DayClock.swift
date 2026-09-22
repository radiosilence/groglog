import Foundation

/// Maps moments onto drinking days. A day runs from `rolloverHour` to `rolloverHour` the next morning,
/// so the 1am pint counts towards the night it belongs to.
nonisolated struct DayClock: Equatable {
    var rolloverHour: Int
    var calendar: Calendar = .current

    var today: DayKey { day(for: .now) }

    /// Decided on the wall clock, so it agrees with `start(of:)` on the nights the clocks change.
    func day(for date: Date) -> DayKey {
        let hour = calendar.component(.hour, from: date)
        return DayKey(date, in: calendar) - (hour < rolloverHour ? 1 : 0)
    }

    func start(of day: DayKey) -> Date {
        let c = day.components
        return calendar.date(from: DateComponents(year: c.year, month: c.month, day: c.day, hour: rolloverHour))!
    }

    func end(of day: DayKey) -> Date { start(of: day + 1) }

    func weekStart(of day: DayKey) -> DayKey {
        day - (day.weekday - calendar.firstWeekday + 7) % 7
    }

    func hours(_ date: Date, into day: DayKey) -> Double {
        date.timeIntervalSince(start(of: day)) / 3600
    }

    /// Places a clock time within the drinking day: 01:30 lands after midnight rather than before the day began.
    func resolve(_ time: Date, into day: DayKey) -> Date {
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        let hour = parts.hour ?? 0
        let c = (hour < rolloverHour ? day + 1 : day).components
        return calendar.date(from: DateComponents(year: c.year, month: c.month, day: c.day, hour: hour, minute: parts.minute ?? 0))!
    }

    /// Now for today; otherwise just after the last drink, or 8pm for an empty day.
    func suggestedTime(for day: DayKey, after last: Date?) -> Date {
        if day == today { return .now }
        if let last { return min(last.addingTimeInterval(20 * 60), end(of: day).addingTimeInterval(-60)) }
        let c = day.components
        return calendar.date(from: DateComponents(year: c.year, month: c.month, day: c.day, hour: 20))!
    }

    func hourLabel(_ hours: Double) -> String {
        start(of: today).addingTimeInterval(hours * 3600).formatted(.dateTime.hour())
    }
}

/// `hours(_:into:)` over a screen's worth of drinks. Where a day starts is a calendar calculation, and the
/// curves ask it once per drink; this asks it once per day.
nonisolated struct HourCounter {
    let clock: DayClock
    private var starts: [Int: Date] = [:]

    init(_ clock: DayClock) { self.clock = clock }

    mutating func hours(_ date: Date, into day: DayKey) -> Double {
        if let start = starts[day.number] { return date.timeIntervalSince(start) / 3600 }
        let start = clock.start(of: day)
        starts[day.number] = start
        return date.timeIntervalSince(start) / 3600
    }
}

nonisolated extension DayKey {
    static func + (day: DayKey, n: Int) -> DayKey { day.advanced(by: n) }
    static func - (day: DayKey, n: Int) -> DayKey { day.advanced(by: -n) }
}
