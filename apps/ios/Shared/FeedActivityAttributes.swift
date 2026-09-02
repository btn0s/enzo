import ActivityKit
import Foundation

struct FeedActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var nextFeedAt: Date?
    }

    var eventID: String
    var createdAt: Date
}
