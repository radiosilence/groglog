import Foundation
import GrogLogCore

/// A calendar date with no time or zone, identifying a drinking day. Held as days since 1970-01-01 so day
/// arithmetic is integer arithmetic, and so a night logged in one timezone stays on its date in another.
nonisolated struct DayKey: Hashable, Comparable, Strideable, Codable, CustomStringConvertible {
    let number: Int

    init(number: Int) {
        self.number = number
    }

    /// Days from civil date, in the proleptic Gregorian calendar.
    init(year: Int, month: Int, day: Int) {
        number = Int(dayNumber(year: Int64(year), month: Int64(month), day: Int64(day)))
    }

    /// The civil date `date` falls on in `calendar`.
    init(_ date: Date, in calendar: Calendar) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    /// A valid `yyyy-MM-dd` date. Imported files are parsed with this, so impossible or day-first dates are refused
    /// rather than rolled over into another day.
    init?(_ string: String) {
        guard let number = dayParse(text: string) else { return nil }
        self.init(number: Int(number))
    }

    var components: (year: Int, month: Int, day: Int) {
        let c = dayCivil(number: Int64(number))
        return (Int(c.year), Int(c.month), Int(c.day))
    }

    /// 1 = Sunday … 7 = Saturday, matching `Calendar`.
    var weekday: Int { Int(dayWeekday(number: Int64(number))) }

    var monthStart: DayKey { DayKey(number: Int(dayMonthStart(number: Int64(number)))) }

    var daysInMonth: Int { Int(dayDaysInMonth(number: Int64(number))) }

    /// `yyyy-MM-dd`.
    var description: String { dayFormat(number: Int64(number)) }

    /// Local midnight, for display and chart axes.
    func date(in calendar: Calendar) -> Date {
        let c = components
        return calendar.date(from: DateComponents(year: c.year, month: c.month, day: c.day))!
    }

    static func < (lhs: DayKey, rhs: DayKey) -> Bool { lhs.number < rhs.number }
    func advanced(by n: Int) -> DayKey { DayKey(number: number + n) }
    func distance(to other: DayKey) -> Int { other.number - number }

    init(from decoder: Decoder) throws {
        let string = try decoder.singleValueContainer().decode(String.self)
        guard let key = DayKey(string) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Expected yyyy-MM-dd, got \(string)"))
        }
        self = key
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
