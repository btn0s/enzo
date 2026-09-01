import ActivityKit
import Foundation

struct FeedActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable, Hashable {
            case waiting
            case feeding
        }

        var phase: Phase
        var startedAt: Date?
        var nextFeedAt: Date?
        var milkType: String
    }

    var eventID: String
    var createdAt: Date
}
