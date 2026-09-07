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

struct DailySummary: Decodable, Equatable {
    let milkMl: Double
    let feeds: Int
    let pees: Int
    let poops: Int

    static let empty = DailySummary(milkMl: 0, feeds: 0, pees: 0, poops: 0)
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
    let timezone: String
    let now: Date
    let nextFeedAt: Date?
    let intervalMinutes: Int
    let profile: Profile
    let checkups: [Checkup]
    let activeCheckupId: String?
    let today: DailySummary
    let events: [ServerEvent]

    var careCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timezone) ?? .current
        return calendar
    }

    /// Latest checkup that had happened by the supplied time.
    func activeCheckup(at date: Date) -> Checkup? {
        checkups.first { $0.occurredAt <= date }
    }

    /// Most recent weight that had been recorded by the supplied time.
    func currentWeightKg(at date: Date) -> Double? {
        checkups.first { $0.occurredAt <= date && $0.weightKg != nil }?.weightKg
    }

    var activeCheckup: Checkup? {
        activeCheckup(at: now)
    }

    var currentWeightKg: Double? {
        currentWeightKg(at: now)
    }

    func summary(on date: Date) -> DailySummary {
        let calendar = careCalendar
        if calendar.isDate(date, inSameDayAs: now) {
            return today
        }

        var milkMl = 0.0
        var feeds = 0
        var pees = 0
        var poops = 0

        for event in events where calendar.isDate(event.occurredAt, inSameDayAs: date) {
            switch event.content {
            case .feed(let feed):
                feeds += 1
                milkMl += feed.amountMl ?? 0
            case .diaper(let diaper):
                if diaper.pee { pees += 1 }
                if diaper.poop { poops += 1 }
            }
        }

        return DailySummary(
            milkMl: milkMl,
            feeds: feeds,
            pees: pees,
            poops: poops
        )
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
