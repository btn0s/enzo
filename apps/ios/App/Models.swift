import Foundation

enum MilkType: String, Codable, CaseIterable, Identifiable {
    case formula
    case breastMilk = "breast-milk"

    var id: String { rawValue }
    var label: String { self == .formula ? "Formula" : "Breast milk" }
}

enum EventType: String, Codable, Hashable {
    case feed
    case diaper
}

struct FeedEvent: Codable, Hashable {
    let milkType: MilkType
    let amountMl: Double?
    let resetsTimer: Bool
}

struct DiaperEvent: Codable, Hashable {
    let pee: Bool
    let poop: Bool
}

enum EventContent: Hashable {
    case feed(FeedEvent)
    case diaper(DiaperEvent)
}

struct ServerEvent: Decodable, Identifiable, Hashable {
    let id: String
    let occurredAt: Date
    let content: EventContent
    let notes: String

    var type: EventType {
        switch content {
        case .feed: .feed
        case .diaper: .diaper
        }
    }

    var feed: FeedEvent? {
        guard case .feed(let feed) = content else { return nil }
        return feed
    }

    var diaper: DiaperEvent? {
        guard case .diaper(let diaper) = content else { return nil }
        return diaper
    }

    private enum CodingKeys: String, CodingKey {
        case id, occurredAt, type, feed, diaper, notes
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        occurredAt = try values.decode(Date.self, forKey: .occurredAt)
        notes = try values.decode(String.self, forKey: .notes)

        switch try values.decode(EventType.self, forKey: .type) {
        case .feed:
            content = .feed(try values.decode(FeedEvent.self, forKey: .feed))
        case .diaper:
            let diaper = try values.decode(DiaperEvent.self, forKey: .diaper)
            guard diaper.pee || diaper.poop else {
                throw DecodingError.dataCorruptedError(
                    forKey: .diaper,
                    in: values,
                    debugDescription: "A diaper must contain pee, poop, or both"
                )
            }
            content = .diaper(diaper)
        }
    }
}

struct TodaySummary: Decodable {
    let milkMl: Double
    let feeds: Int
    let pees: Int
    let poops: Int
}

struct Profile: Decodable, Hashable {
    let birthAt: Date
    let feedIntervalMinutes: Int?
}

/// A clinician visit. Every goal field is optional; nil means "use guidance".
struct Checkup: Codable, Identifiable, Hashable {
    var id: String
    var occurredAt: Date
    var weightKg: Double?
    var feedIntervalMinutes: Int?
    var feedsMin: Int?
    var feedsMax: Int?
    var bottleMl: Double?
    var milkMlMin: Double?
    var milkMlMax: Double?
    var peeMin: Int?
    var poopMin: Int?
    var notes: String

    static func new(at date: Date = Date()) -> Checkup {
        Checkup(id: UUID().uuidString.lowercased(), occurredAt: date, notes: "")
    }

    /// True when the visit changed at least one goal beyond recording weight.
    var hasOverrides: Bool {
        feedIntervalMinutes != nil || feedsMin != nil || feedsMax != nil || bottleMl != nil
            || milkMlMin != nil || milkMlMax != nil || peeMin != nil || poopMin != nil
    }
}

struct ServerState: Decodable {
    let nextFeedAt: Date?
    let intervalMinutes: Int
    let profile: Profile
    let checkups: [Checkup]
    let activeCheckupId: String?
    let today: TodaySummary
    let events: [ServerEvent]

    /// Latest checkup that has already happened.
    var activeCheckup: Checkup? {
        activeCheckupId.flatMap { id in checkups.first { $0.id == id } }
    }

    /// Most recent recorded weight from any past checkup.
    var currentWeightKg: Double? {
        let now = Date()
        return checkups.first { $0.occurredAt <= now && $0.weightKg != nil }?.weightKg
    }
}

struct MutationResponse: Decodable {
    let ok: Bool
    let state: ServerState
}

struct FeedDraft: Identifiable, Hashable {
    let id = UUID()
    var eventID: String?
    var occurredAt = Date()
    var milkType: MilkType = .formula
    var amountMl: Double?
    var notes = ""
    var resetsTimer = true
}

struct DiaperDraft: Identifiable, Hashable {
    let id = UUID()
    var eventID: String?
    var occurredAt = Date()
    var pee = false
    var poop = false
    var notes = ""
}

enum EditorRoute: Identifiable, Hashable {
    case feed(FeedDraft)
    case diaper(DiaperDraft)

    var id: String {
        switch self {
        case .feed(let draft): "feed-\(draft.id)"
        case .diaper(let draft): "diaper-\(draft.id)"
        }
    }

    init(event: ServerEvent) {
        switch event.content {
        case .feed(let feed):
            var draft = FeedDraft()
            draft.eventID = event.id
            draft.occurredAt = event.occurredAt
            draft.milkType = feed.milkType
            draft.amountMl = feed.amountMl
            draft.notes = event.notes
            draft.resetsTimer = feed.resetsTimer
            self = .feed(draft)
        case .diaper(let diaper):
            var draft = DiaperDraft()
            draft.eventID = event.id
            draft.occurredAt = event.occurredAt
            draft.pee = diaper.pee
            draft.poop = diaper.poop
            draft.notes = event.notes
            self = .diaper(draft)
        }
    }
}
