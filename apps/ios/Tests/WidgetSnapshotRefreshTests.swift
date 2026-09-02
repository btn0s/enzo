import XCTest
@testable import Enzo

final class WidgetSnapshotRefreshTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testRemoteRefreshReplacesStaleCrossDeviceSnapshot() async {
        let stale = WidgetSnapshot(
            nextFeedAt: now.addingTimeInterval(900),
            milkMl: 120,
            feeds: 2,
            pees: 1,
            poops: 0,
            dayOfLife: 3,
            volumeUnit: .ounces,
            updatedAt: now.addingTimeInterval(-600)
        )
        let remote = WidgetRemoteState(
            nextFeedAt: now.addingTimeInterval(7_200),
            birthAt: now.addingTimeInterval(-5 * 86_400),
            milkMl: 240,
            feeds: 4,
            pees: 3,
            poops: 1
        )
        let refresher = WidgetSnapshotRefresher(fetchRemoteState: { remote })
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let refreshed = await refresher.refresh(cached: stale, now: now, calendar: calendar)

        XCTAssertEqual(refreshed?.nextFeedAt, remote.nextFeedAt)
        XCTAssertEqual(refreshed?.milkMl, 240)
        XCTAssertEqual(refreshed?.feeds, 4)
        XCTAssertEqual(refreshed?.pees, 3)
        XCTAssertEqual(refreshed?.poops, 1)
        XCTAssertEqual(refreshed?.dayOfLife, 5)
        XCTAssertEqual(refreshed?.volumeUnit, .ounces)
        XCTAssertEqual(refreshed?.updatedAt, now)
    }

    func testRemoteRefreshFallsBackToCachedSnapshotWhenFetchFails() async {
        let cached = WidgetSnapshot.placeholder
        let refresher = WidgetSnapshotRefresher(fetchRemoteState: {
            throw URLError(.notConnectedToInternet)
        })

        let refreshed = await refresher.refresh(cached: cached, now: now)

        XCTAssertEqual(refreshed, cached)
    }
}
