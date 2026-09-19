import Foundation

/// Maps timestamps onto drinking days. A day runs from `rolloverHour` to `rolloverHour` the next morning,
/// so the 1am pint counts towards the night it belongs to.
struct DayClock {
    var rolloverHour: Int
    var calendar: Calendar = .current

    var today: Date { day(for: .now) }

    func day(for date: Date) -> Date {
        calendar.startOfDay(for: calendar.date(byAdding: .hour, value: -rolloverHour, to: date)!)
    }

    func start(of day: Date) -> Date {
        calendar.date(byAdding: .hour, value: rolloverHour, to: day)!
    }

    func end(of day: Date) -> Date {
        start(of: adding(1, to: day))
    }

    func adding(_ days: Int, to day: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: day)!
    }

    func weekStart(of day: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: day)!.start
    }

    func hours(_ date: Date, into day: Date) -> Double {
        date.timeIntervalSince(start(of: day)) / 3600
    }

    /// Places a clock time within the drinking day: 01:30 lands after midnight rather than before the day began.
    func resolve(_ time: Date, into day: Date) -> Date {
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        let hour = parts.hour ?? 0
        let date = calendar.date(bySettingHour: hour, minute: parts.minute ?? 0, second: 0, of: day)!
        return hour < rolloverHour ? adding(1, to: date) : date
    }

    func suggestedTime(for day: Date, after last: Date?) -> Date {
        if day == today { return .now }
        if let last { return min(last.addingTimeInterval(20 * 60), end(of: day).addingTimeInterval(-60)) }
        return calendar.date(bySettingHour: 20, minute: 0, second: 0, of: day)!
    }

    /// `yyyy-MM-dd` in the local calendar — ISO formatting would use UTC and shift days near midnight.
    func key(_ day: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    func day(key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    func hourLabel(_ hours: Double) -> String {
        start(of: calendar.startOfDay(for: .now))
            .addingTimeInterval(hours * 3600)
            .formatted(.dateTime.hour())
    }
}
