import Foundation

/// Pure feed-alarm trigger math. `desiredDate` in reconciliation is always the
/// trigger instant (due minus lead), not the feed due time.
enum AlarmTriggerCalculator {
    static let immediateFloorOffset: TimeInterval = 2
    static let leadRange = 0...180

    static func triggerDate(
        dueAt: Date,
        leadMinutes: Int,
        now: Date = Date()
    ) -> Date {
        let clampedLead = leadRange.clamp(leadMinutes)
        let leadInterval = TimeInterval(clampedLead) * 60
        let rawTrigger = dueAt.addingTimeInterval(-leadInterval)
        let floor = now.addingTimeInterval(immediateFloorOffset)
        return max(rawTrigger, floor)
    }
}

private extension ClosedRange where Bound == Int {
    func clamp(_ value: Int) -> Int {
        min(max(value, lowerBound), upperBound)
    }
}
