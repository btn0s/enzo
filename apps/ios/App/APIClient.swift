import Foundation

struct APIClient {
    var baseURL: URL {
        if let override = ProcessInfo.processInfo.environment["ENZO_API_BASE_URL"],
           let url = URL(string: override) {
            return url
        }
        return URL(string: "https://enzo-api.btn0s.workers.dev")!
    }

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    func state() async throws -> ServerState {
        try await request(path: "/api/state")
    }

    func createFeed(_ draft: FeedDraft) async throws -> MutationResponse {
        struct FeedBody: Encodable {
            let milkType: MilkType
            let amountMl: Double?
            let resetsTimer: Bool
        }
        struct Body: Encodable {
            let id: String
            let type = EventType.feed
            let feed: FeedBody
            let occurredAt: Date
            let notes: String
        }
        let eventID = draft.eventID ?? UUID().uuidString.lowercased()
        return try await request(
            path: "/api/events",
            method: "POST",
            body: Body(
                id: eventID,
                feed: FeedBody(
                    milkType: draft.milkType,
                    amountMl: draft.amountMl,
                    resetsTimer: draft.resetsTimer
                ),
                occurredAt: draft.occurredAt,
                notes: draft.notes
            )
        )
    }

    func updateFeed(_ draft: FeedDraft) async throws -> MutationResponse {
        guard let eventID = draft.eventID else { throw URLError(.badURL) }
        struct FeedBody: Encodable {
            let milkType: MilkType
            let amountMl: Double?
            let resetsTimer: Bool
        }
        struct Body: Encodable {
            let occurredAt: Date
            let feed: FeedBody
            let notes: String
        }
        return try await request(
            path: "/api/events/\(eventID)",
            method: "PATCH",
            body: Body(
                occurredAt: draft.occurredAt,
                feed: FeedBody(
                    milkType: draft.milkType,
                    amountMl: draft.amountMl,
                    resetsTimer: draft.resetsTimer
                ),
                notes: draft.notes
            )
        )
    }

    func createDiaper(_ draft: DiaperDraft) async throws -> MutationResponse {
        struct DiaperBody: Encodable {
            let pee: Bool
            let poop: Bool
        }
        struct Body: Encodable {
            let id: String
            let type = EventType.diaper
            let occurredAt: Date
            let diaper: DiaperBody
            let notes: String
        }
        return try await request(
            path: "/api/events",
            method: "POST",
            body: Body(
                id: draft.eventID ?? UUID().uuidString.lowercased(),
                occurredAt: draft.occurredAt,
                diaper: DiaperBody(pee: draft.pee, poop: draft.poop),
                notes: draft.notes
            )
        )
    }

    func updateDiaper(_ draft: DiaperDraft) async throws -> MutationResponse {
        guard let eventID = draft.eventID else { throw URLError(.badURL) }
        struct DiaperBody: Encodable { let pee: Bool; let poop: Bool }
        struct Body: Encodable {
            let occurredAt: Date
            let diaper: DiaperBody
            let notes: String
        }
        return try await request(
            path: "/api/events/\(eventID)",
            method: "PATCH",
            body: Body(
                occurredAt: draft.occurredAt,
                diaper: DiaperBody(pee: draft.pee, poop: draft.poop),
                notes: draft.notes
            )
        )
    }

    func updateBirthDate(_ birthAt: Date) async throws -> MutationResponse {
        struct Body: Encodable { let birthAt: Date }
        return try await request(
            path: "/api/profile",
            method: "PATCH",
            body: Body(birthAt: birthAt)
        )
    }

    func updateFeedIntervalMinutes(_ feedIntervalMinutes: Int) async throws -> MutationResponse {
        struct Body: Encodable { let feedIntervalMinutes: Int }
        return try await request(
            path: "/api/profile",
            method: "PATCH",
            body: Body(feedIntervalMinutes: feedIntervalMinutes)
        )
    }

    func registerPushDevice(
        token: String,
        environment: PushEnvironment
    ) async throws {
        struct Body: Encodable {
            let token: String
            let environment: PushEnvironment
        }
        struct Response: Decodable { let ok: Bool }
        let response: Response = try await request(
            path: "/api/push-devices",
            method: "POST",
            body: Body(token: token, environment: environment)
        )
        guard response.ok else { throw URLError(.cannotParseResponse) }
    }

    func registerLiveActivity(
        token: String,
        activityID: String,
        eventID: String,
        environment: PushEnvironment
    ) async throws {
        struct Body: Encodable {
            let token: String
            let activityID: String
            let eventID: String
            let environment: PushEnvironment
        }
        struct Response: Decodable { let ok: Bool }
        let response: Response = try await request(
            path: "/api/live-activities",
            method: "POST",
            body: Body(
                token: token,
                activityID: activityID,
                eventID: eventID,
                environment: environment
            )
        )
        guard response.ok else { throw URLError(.cannotParseResponse) }
    }

    func unregisterLiveActivity(activityID: String) async throws {
        struct Response: Decodable { let ok: Bool }
        let encodedID = activityID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? activityID
        let response: Response = try await request(
            path: "/api/live-activities/\(encodedID)",
            method: "DELETE"
        )
        guard response.ok else { throw URLError(.cannotParseResponse) }
    }

    func createCheckup(_ checkup: Checkup) async throws -> MutationResponse {
        try await request(path: "/api/checkups", method: "POST", body: checkup)
    }

    func updateCheckup(_ checkup: Checkup) async throws -> MutationResponse {
        try await request(path: "/api/checkups/\(checkup.id)", method: "PATCH", body: checkup)
    }

    func deleteCheckup(id: String) async throws -> MutationResponse {
        try await request(path: "/api/checkups/\(id)", method: "DELETE")
    }

    func deleteEvent(id: String) async throws -> MutationResponse {
        try await request(path: "/api/events/\(id)", method: "DELETE")
    }

    private func request<Response: Decodable>(
        path: String,
        method: String = "GET"
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(EnzoSecrets.apiToken)", forHTTPHeaderField: "Authorization")
        return try await perform(request)
    }

    private func request<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(EnzoSecrets.apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return try await perform(request)
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        return try decoder.decode(Response.self, from: data)
    }
}
