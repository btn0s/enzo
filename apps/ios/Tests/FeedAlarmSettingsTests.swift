import Foundation
import XCTest
@testable import Enzo

final class FeedAlarmSettingsTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testDisabledActiveHoursAllowAnyTime() {
        let settings = makeSettings(activeHoursEnabled: false, start: 7 * 60, end: 22 * 60)

        XCTAssertTrue(settings.allowsAlarm(at: date(hour: 3), calendar: calendar))
    }

    func testDaytimeRangeIncludesStartAndExcludesEnd() {
        let settings = makeSettings(activeHoursEnabled: true, start: 7 * 60, end: 22 * 60)

        XCTAssertFalse(settings.allowsAlarm(at: date(hour: 6, minute: 59), calendar: calendar))
        XCTAssertTrue(settings.allowsAlarm(at: date(hour: 7), calendar: calendar))
        XCTAssertTrue(settings.allowsAlarm(at: date(hour: 21, minute: 59), calendar: calendar))
        XCTAssertFalse(settings.allowsAlarm(at: date(hour: 22), calendar: calendar))
    }

    func testOvernightRangeAllowsLateAndEarlyHours() {
        let settings = makeSettings(activeHoursEnabled: true, start: 20 * 60, end: 7 * 60)

        XCTAssertTrue(settings.allowsAlarm(at: date(hour: 23), calendar: calendar))
        XCTAssertTrue(settings.allowsAlarm(at: date(hour: 6, minute: 59), calendar: calendar))
        XCTAssertFalse(settings.allowsAlarm(at: date(hour: 12), calendar: calendar))
    }

    func testMatchingStartAndEndMeanAllDay() {
        let settings = makeSettings(activeHoursEnabled: true, start: 8 * 60, end: 8 * 60)

        XCTAssertTrue(settings.allowsAlarm(at: date(hour: 2), calendar: calendar))
        XCTAssertTrue(settings.allowsAlarm(at: date(hour: 14), calendar: calendar))
    }

    func testDisabledAlarmIsNeverAllowed() {
        var settings = makeSettings(activeHoursEnabled: false, start: 7 * 60, end: 22 * 60)
        settings.enabled = false

        XCTAssertFalse(settings.allowsAlarm(at: date(hour: 12), calendar: calendar))
    }

    func testCadenceMapsOnlyExplicitReminderOptionsToIntervals() {
        XCTAssertNil(AlarmCadence.once.repeatMinutes)
        XCTAssertEqual(AlarmCadence.fiveMinutes.repeatMinutes, 5)
        XCTAssertEqual(AlarmCadence.tenMinutes.repeatMinutes, 10)
        XCTAssertEqual(AlarmCadence.fifteenMinutes.repeatMinutes, 15)
    }

    func testAlarmPreferencesStayIsolatedBetweenDeviceContainers() throws {
        let firstSuite = "FeedAlarmSettingsTests.first.\(UUID().uuidString)"
        let secondSuite = "FeedAlarmSettingsTests.second.\(UUID().uuidString)"
        let firstDefaults = try XCTUnwrap(UserDefaults(suiteName: firstSuite))
        let secondDefaults = try XCTUnwrap(UserDefaults(suiteName: secondSuite))
        defer {
            firstDefaults.removePersistentDomain(forName: firstSuite)
            secondDefaults.removePersistentDomain(forName: secondSuite)
        }
        let firstStore = AlarmSettingsStore(defaults: firstDefaults)
        let secondStore = AlarmSettingsStore(defaults: secondDefaults)
        var firstSettings = firstStore.settings
        firstSettings.enabled = false
        firstSettings.sound = .classicAlarm

        firstStore.save(firstSettings)

        XCTAssertFalse(firstStore.settings.enabled)
        XCTAssertEqual(firstStore.settings.sound, .classicAlarm)
        XCTAssertTrue(secondStore.settings.enabled)
        XCTAssertEqual(secondStore.settings.sound, .system)
    }

    func testClassicAlarmUsesBundledSound() {
        XCTAssertEqual(AlarmSound.classicAlarm.fileName, "EnzoClassicAlarm.wav")
    }

    private func makeSettings(activeHoursEnabled: Bool, start: Int, end: Int) -> FeedAlarmSettings {
        FeedAlarmSettings(
            enabled: true,
            leadMinutes: 0,
            cadence: .once,
            activeHoursEnabled: activeHoursEnabled,
            activeHoursStartMinutes: start,
            activeHoursEndMinutes: end,
            sound: .system
        )
    }

    private func date(hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            year: 2027,
            month: 1,
            day: 15,
            hour: hour,
            minute: minute
        ))!
    }
}
