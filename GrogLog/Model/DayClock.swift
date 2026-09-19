import Foundation

/// Maps moments onto drinking days. A day runs from `rolloverHour` to `rolloverHour` the next morning,
/// so the 1am pint counts towards the night it belongs to.
nonisolated struct DayClock {
    var rolloverHour: Int
    var calendar: Calendar = .current

    var today: DayKey { day(for: .now) }

    func day(for date: Date) -> DayKey {
        let shifted = calendar.date(byAdding: .hour, value: -rolloverHour, to: date)!
        let c = calendar.dateComponents([.year, .month, .day], from: shifted)
        return DayKey(year: c.year!, month: c.month!, day: c.day!)
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

nonisolated extension DayKey {
    static func + (day: DayKey, n: Int) -> DayKey { day.advanced(by: n) }
    static func - (day: DayKey, n: Int) -> DayKey { day.advanced(by: -n) }
}
