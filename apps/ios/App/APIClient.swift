import Foundation

struct APIClient {
    var baseURL: URL {
        if let override = ProcessInfo.processInfo.environment["ENZO_API_BASE_URL"],
           let url = URL(string: override) {
            return url
        }
#if targetEnvironment(simulator)
        return URL(string: "http://127.0.0.1:4318")!
#else
        return URL(string: "https://devbook.tail24b669.ts.net:8443")!
#endif
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

    func deleteEvent(id: String) async throws -> MutationResponse {
        try await request(path: "/api/events/\(id)", method: "DELETE")
    }

    private func request<Response: Decodable>(
        path: String,
        method: String = "GET"
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        return try await perform(request)
    }

    private func request<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
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
