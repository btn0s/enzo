import Foundation
import XCTest
@testable import Enzo

final class DailyReferenceTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    // Friday, August 28, 2026 at 9:30 PM.
    private lazy var birth = calendar.date(
        from: DateComponents(year: 2026, month: 8, day: 28, hour: 21, minute: 30)
    )!
    private lazy var profile = EnzoProfile(birthDate: birth)

    private func date(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour))!
    }

    func testBirthDayIsDayZeroAndNextCalendarDayIsDayOne() {
        XCTAssertEqual(profile.dayOfLife(on: date(28, 23), calendar: calendar), 0)
        XCTAssertEqual(profile.dayOfLife(on: date(29, 1), calendar: calendar), 1)
        XCTAssertEqual(profile.dayOfLife(on: date(29, 23), calendar: calendar), 1)
        XCTAssertEqual(profile.dayOfLife(on: date(30, 12), calendar: calendar), 2)
        XCTAssertEqual(profile.dayOfLife(on: date(31, 12), calendar: calendar), 3)
    }

    func testTuesdayAfterFridayNightBirthIsDayFour() {
        XCTAssertEqual(
            profile.dayOfLife(
                on: calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 12))!,
                calendar: calendar
            ),
            4
        )
    }

    func testMilkGoalFollowsHourlyBandsThenEstablishedRange() {
        XCTAssertEqual(DailyReference.dailyMilk(weightKg: 3.4, hoursOfAge: 87), 340...340)
        XCTAssertEqual(DailyReference.dailyMilk(weightKg: 3.4, hoursOfAge: 97), 408...408)
        XCTAssertEqual(DailyReference.dailyMilk(weightKg: 3.4, hoursOfAge: 200), 510...680)
        XCTAssertNil(DailyReference.dailyMilk(weightKg: nil, hoursOfAge: 87))
    }

    func testPaceScalesGoalToTimeOfDay() {
        let noon = date(31, 12)
        XCTAssertEqual(DailyReference.pace(current: 4, goal: 8, slack: 0.5, now: noon, calendar: calendar), .onPace)
        XCTAssertEqual(DailyReference.pace(current: 3, goal: 8, slack: 0.5, now: noon, calendar: calendar), .belowPace)
        XCTAssertEqual(DailyReference.pace(current: 8, goal: 8, slack: 0.5, now: noon, calendar: calendar), .goalMet)
        XCTAssertEqual(DailyReference.pace(current: 0, goal: nil, slack: 0.5, now: noon, calendar: calendar), .tracking)
    }

    func testGoalsFallBackToGuidanceWithoutCheckup() {
        let goals = DailyGoals.resolve(checkup: nil, weightKg: 3.4, day: 4, hoursOfAge: 87, defaultIntervalMinutes: 120)
        XCTAssertEqual(goals.feeds.value, 8...12)
        XCTAssertEqual(goals.feeds.source, .guidance)
        XCTAssertEqual(goals.dailyMilkMl?.value, 340...340)
        XCTAssertEqual(goals.bottleMl?.value, 42.5...42.5)
        XCTAssertEqual(goals.feedIntervalMinutes.value, 120)
        XCTAssertEqual(goals.feedIntervalMinutes.source, .settings)
        XCTAssertEqual(goals.peeMin?.value, 3)
    }

    func testCheckupOverridesOnlyWhatItSets() {
        var checkup = Checkup.new(at: birth.addingTimeInterval(3 * 86_400))
        checkup.bottleMl = 60
        checkup.feedIntervalMinutes = 150
        checkup.feedsMin = 9
        let goals = DailyGoals.resolve(checkup: checkup, weightKg: 3.4, day: 4, hoursOfAge: 87, defaultIntervalMinutes: 120)
        XCTAssertEqual(goals.bottleMl?.value, 60...60)
        XCTAssertEqual(goals.bottleMl?.source, .checkup(checkup))
        XCTAssertEqual(goals.bottleMl?.guidance, 42.5...42.5)
        XCTAssertEqual(goals.feedIntervalMinutes.value, 150)
        XCTAssertEqual(goals.feedIntervalMinutes.guidance, 120)
        XCTAssertEqual(goals.feeds.value, 9...12)
        XCTAssertEqual(goals.dailyMilkMl?.source, .guidance)
        XCTAssertNil(goals.dailyMilkMl?.guidance)
        XCTAssertEqual(goals.peeMin?.source, .guidance)
    }

    func testGoalsWithoutWeightHaveNoMilkTargets() {
        let goals = DailyGoals.resolve(checkup: nil, weightKg: nil, day: 4, hoursOfAge: 87, defaultIntervalMinutes: 120)
        XCTAssertNil(goals.dailyMilkMl)
        XCTAssertNil(goals.bottleMl)
    }

    func testVolumeUnitRoundTripsAndFormats() {
        let ml = VolumeUnit.ounces.ml(from: 2.5)
        XCTAssertEqual(ml, 73.93375, accuracy: 0.0001)
        XCTAssertEqual(VolumeUnit.ounces.format(ml: ml), "2.5 oz")
        XCTAssertEqual(VolumeUnit.milliliters.format(ml: ml), "74 mL")
        XCTAssertEqual(VolumeUnit.ounces.format(range: 510...680), "17.2–23 oz")
        XCTAssertEqual(VolumeUnit.milliliters.format(range: 340...340), "340 mL")
    }

    func testFeedIntervalOptionsUseHourLabels() {
        XCTAssertEqual(FeedIntervalFormatting.options, [60, 90, 120, 150, 180, 210, 240])
        XCTAssertEqual(FeedIntervalFormatting.label(for: 120), "Every 2 hours")
        XCTAssertEqual(FeedIntervalFormatting.label(for: 150), "Every 2½ hours")
    }

    func testProfileDecodesSharedFeedInterval() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let profile = try decoder.decode(
            Profile.self,
            from: Data(
                #"{"birthAt":"2026-08-29T04:00:00Z","feedIntervalMinutes":120}"#.utf8
            )
        )
        XCTAssertEqual(profile.feedIntervalMinutes, 120)
    }

    func testProfileDecodesLegacyPayloadWithoutFeedInterval() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let profile = try decoder.decode(
            Profile.self,
            from: Data(#"{"birthAt":"2026-08-29T04:00:00Z"}"#.utf8)
        )
        XCTAssertNil(profile.feedIntervalMinutes)
    }
}
