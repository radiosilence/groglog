import Foundation
import Testing
@testable import GrogLog

/// Health counts standard drinks, not UK units. Getting this wrong doesn't fail — it just quietly overstates
/// every reading by three quarters, which is why it's pinned down here.
@Suite struct StandardDrinkTests {
    private func entry(ml: Double, abv: Double) -> Entry {
        let drink = Drink(name: "Beer", category: .beer, abv: abv, vessel: .pint, volumeMl: ml)
        return Entry(pour: Pour(drinkId: drink.id, timestamp: .now, day: 0, vessel: .pint, volumeMl: ml, price: 0), drink: drink)
    }

    @Test func oneUnitIsAboutFiveEighthsOfAStandardDrink() {
        // 10 ml of alcohol against Health's 17.7.
        let oneUnit = entry(ml: 1000, abv: 1)
        #expect(abs(oneUnit.units - 1) < 0.0001)
        #expect(abs(oneUnit.standardDrinks - 0.5636) < 0.001)
    }

    @Test func aPintOfFivePercentIsOneAndAHalfStandardDrinks() {
        let pint = entry(ml: 568, abv: 5)
        #expect(abs(pint.units - 2.84) < 0.0001)
        #expect(abs(pint.standardDrinks - 1.6) < 0.01)
    }

    @Test func unitsAreNeverHandedOverAsDrinks() {
        let pint = entry(ml: 568, abv: 5)
        #expect(pint.standardDrinks < pint.units)
    }

    @Test func nothingDrunkIsNoDrinks() {
        #expect(entry(ml: 330, abv: 0).standardDrinks == 0)
    }
}

/// A reading belongs to the evening that caused it. File one by calendar date and every heavy night's damage lands on
/// the day after, which is usually a quiet one.
@Suite struct NightTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()
    private var clock: DayClock { DayClock(rolloverHour: 5, calendar: calendar) }
    private let friday = DayKey(year: 2026, month: 9, day: 18)

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    @Test func theNightAndTheMorningAfterBelongToTheEvening() {
        for date in [at(18, 23, 30), at(19, 3), at(19, 7), at(19, 11, 59)] {
            #expect(clock.night(for: date) == friday)
        }
        #expect(clock.night(for: at(18, 19, 59)) == friday - 1)
        #expect(clock.night(for: at(19, 20)) == friday + 1)
    }

    @Test func aRestingRateStampedOnTheMorningIsTheNightBefore() {
        // Health stamps a day's resting rate across the whole calendar day; its middle is Saturday noon.
        let nights = Nights(restingHR: [(at(19, 12), 58)], clock: clock)
        #expect(nights[friday]?.restingHR == 58)
    }

    @Test func daytimeHRVIsLeftOut() {
        let nights = Nights(hrv: [(at(19, 2), 40), (at(19, 4), 50), (at(19, 15), 90)], clock: clock)
        #expect(nights[friday]?.hrv == 45)
        #expect(nights[friday - 1] == nil)
    }

    @Test func tooFewNightsIsNoAverage() {
        let nights = Nights(hrv: [(at(15, 3), 40), (at(16, 3), 50)], clock: clock)
        #expect(nights.mean(\.hrv, over: (friday - 6)...friday) == nil)
        #expect(nights.mean(\.hrv, over: (friday - 6)...friday, atLeast: 2) == 45)
    }
}

@Suite struct SleepingHeartRateTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()
    private var clock: DayClock { DayClock(rolloverHour: 5, calendar: calendar) }
    private let tuesday = DayKey(year: 2026, month: 9, day: 22)

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    private func span(_ start: Date, _ end: Date, _ stage: SleepStage = .core, _ source: String = "watch") -> SleepSpan {
        SleepSpan(interval: DateInterval(start: start, end: end), stage: stage, source: source)
    }

    @Test func stagesAddUpAndAwakeIsNotSleep() {
        let spans = [
            span(at(23, 0), at(23, 1), .deep),
            span(at(23, 1), at(23, 1, 30), .awake),
            span(at(23, 1, 30), at(23, 3), .rem),
            span(at(23, 3), at(23, 7), .core),
        ]
        let sleep = Nights(sleep: spans, clock: clock)[tuesday]?.sleep
        #expect(sleep?.asleep == 6.5 * 3600)
        #expect(sleep?.awake == 1800)
        #expect(sleep?.remShare == 1.5 / 6.5)
    }

    @Test func twoDevicesOnOneNightCountOnce() {
        let spans = [
            span(at(23, 0), at(23, 7), .core, "garmin"),
            span(at(23, 1), at(23, 5), .unstaged, "phone"),
        ]
        let sleep = Nights(sleep: spans, clock: clock)[tuesday]?.sleep
        #expect(sleep?.asleep == 7.0 * 3600)
        #expect(sleep?.unstaged == 0)
    }

    @Test func aLateBedtimeStillBelongsToTheEveningBefore() {
        let asleep = [span(at(23, 4, 36), at(23, 9, 38))]
        let nights = Nights(sleep: asleep, heartRate: [(at(23, 6), 60), (at(23, 7), 70)], clock: clock)
        #expect(nights[tuesday]?.sleepingHR == 65)
    }

    @Test func awakeInTheNightAndBeforeSleepAreLeftOut() {
        let asleep = [
            span(at(23, 1), at(23, 3)),
            span(at(23, 3), at(23, 3, 30), .awake),
            span(at(23, 3, 30), at(23, 7)),
        ]
        let beats = [(at(23, 0, 30), 90.0), (at(23, 2), 60), (at(23, 3, 15), 95), (at(23, 5), 64), (at(23, 8), 88)]
        #expect(Nights(sleep: asleep, heartRate: beats, clock: clock)[tuesday]?.sleepingHR == 62)
    }

    @Test func oneSpanPerNightToFetchWithin() {
        let asleep = [
            span(at(22, 0, 27), at(22, 1, 41)),
            span(at(22, 1, 41), at(22, 1, 49), .awake),
            span(at(22, 1, 49), at(22, 9, 22)),
            span(at(23, 4, 36), at(23, 9, 38)),
        ]
        let spans = Health.nightSpans(asleep, clock: clock).sorted { $0.start < $1.start }
        #expect(spans == [DateInterval(start: at(22, 0, 27), end: at(22, 9, 22)), DateInterval(start: at(23, 4, 36), end: at(23, 9, 38))])
    }
}
