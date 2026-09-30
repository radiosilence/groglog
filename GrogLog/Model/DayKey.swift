import Foundation

/// A calendar date with no time or zone — what a drinking day is. Held as days since 1970-01-01 so that day maths
/// (windows, weeks, streaks) is integer maths, and so a night logged in one timezone stays on its date in another.
nonisolated struct DayKey: Hashable, Comparable, Strideable, Codable, CustomStringConvertible {
    let number: Int

    init(number: Int) {
        self.number = number
    }

    /// Days from civil date (Howard Hinnant's algorithm), valid for the proleptic Gregorian calendar.
    init(year: Int, month: Int, day: Int) {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        number = era * 146_097 + doe - 719_468
    }

    /// The civil date `date` falls on in `calendar`.
    init(_ date: Date, in calendar: Calendar) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    /// A `yyyy-MM-dd` date that exists. Imported files are read with this, so month 13, the 31st of June and a
    /// day-first date are refused rather than rolled over into some other day.
    init?(_ string: String) {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1900...2200).contains(parts[0]), (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
        guard components == (parts[0], parts[1], parts[2]) else { return nil }
    }

    var components: (year: Int, month: Int, day: Int) {
        let z = number + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let day = doy - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (month <= 2 ? 1 : 0), month, day)
    }

    /// 1 = Sunday … 7 = Saturday, matching `Calendar`.
    var weekday: Int { ((number + 4) % 7 + 7) % 7 + 1 }

    var monthStart: DayKey {
        let c = components
        return DayKey(year: c.year, month: c.month, day: 1)
    }

    var daysInMonth: Int {
        let c = components
        let next = c.month == 12 ? DayKey(year: c.year + 1, month: 1, day: 1) : DayKey(year: c.year, month: c.month + 1, day: 1)
        return monthStart.distance(to: next)
    }

    /// `yyyy-MM-dd`.
    var description: String {
        let c = components
        return String(format: "%04d-%02d-%02d", c.year, c.month, c.day)
    }

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
