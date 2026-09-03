import Foundation

/// Pure feed-alarm trigger math. `desiredDate` in reconciliation is always the
/// trigger instant (due minus lead), not the feed due time.
struct FeedAlarmScheduleTiming: Equatable, Sendable {
    let desiredDate: Date
    let scheduledDate: Date
}

enum AlarmTriggerCalculator {
    static let immediateFloorOffset: TimeInterval = 2
    static let leadRange = 0...180

    static func desiredDate(
        dueAt: Date,
        leadMinutes: Int
    ) -> Date {
        let clampedLead = leadRange.clamp(leadMinutes)
        return dueAt.addingTimeInterval(-TimeInterval(clampedLead) * 60)
    }

    static func scheduleTiming(
        dueAt: Date,
        leadMinutes: Int,
        now: Date = Date()
    ) -> FeedAlarmScheduleTiming? {
        guard dueAt > now else { return nil }
        let desiredDate = desiredDate(dueAt: dueAt, leadMinutes: leadMinutes)
        let floor = now.addingTimeInterval(immediateFloorOffset)
        return FeedAlarmScheduleTiming(
            desiredDate: desiredDate,
            scheduledDate: max(desiredDate, floor)
        )
    }

    static func triggerDate(
        dueAt: Date,
        leadMinutes: Int,
        now: Date = Date()
    ) -> Date {
        let rawTrigger = desiredDate(dueAt: dueAt, leadMinutes: leadMinutes)
        let floor = now.addingTimeInterval(immediateFloorOffset)
        return max(rawTrigger, floor)
    }
}

private extension ClosedRange where Bound == Int {
    func clamp(_ value: Int) -> Int {
        Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}
