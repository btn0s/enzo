import Foundation

/// What the home screen widget shows. The app writes after local changes; the
/// widget refreshes the same cache directly when WidgetKit wakes it remotely.
struct WidgetSnapshot: Codable, Hashable {
    var nextFeedAt: Date?
    var milkMl: Double
    var feeds: Int
    var pees: Int
    var poops: Int
    var dayOfLife: Int
    var volumeUnit: VolumeUnit
    var updatedAt: Date

    static let placeholder = WidgetSnapshot(
        nextFeedAt: Date().addingTimeInterval(2 * 3600),
        milkMl: 240,
        feeds: 4,
        pees: 3,
        poops: 1,
        dayOfLife: 4,
        volumeUnit: .ounces,
        updatedAt: Date()
    )
}

enum WidgetSnapshotStore {
    static let appGroup = "group.com.btn0s.enzo.prototype"
    private static let key = "enzo.widget.snapshot"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    static func load() -> WidgetSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    static func save(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: key)
    }
}
