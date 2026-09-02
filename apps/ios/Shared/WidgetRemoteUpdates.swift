import Foundation

struct WidgetRemoteState: Decodable {
    let nextFeedAt: Date?
    let birthAt: Date
    let milkMl: Double
    let feeds: Int
    let pees: Int
    let poops: Int

    private enum CodingKeys: String, CodingKey {
        case nextFeedAt
        case profile
        case today
    }

    private struct Profile: Decodable {
        let birthAt: Date
    }

    private struct Today: Decodable {
        let milkMl: Double
        let feeds: Int
        let pees: Int
        let poops: Int
    }

    init(
        nextFeedAt: Date?,
        birthAt: Date,
        milkMl: Double,
        feeds: Int,
        pees: Int,
        poops: Int
    ) {
        self.nextFeedAt = nextFeedAt
        self.birthAt = birthAt
        self.milkMl = milkMl
        self.feeds = feeds
        self.pees = pees
        self.poops = poops
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let profile = try values.decode(Profile.self, forKey: .profile)
        let today = try values.decode(Today.self, forKey: .today)
        nextFeedAt = try values.decodeIfPresent(Date.self, forKey: .nextFeedAt)
        birthAt = profile.birthAt
        milkMl = today.milkMl
        feeds = today.feeds
        pees = today.pees
        poops = today.poops
    }

    func snapshot(
        volumeUnit: VolumeUnit,
        now: Date,
        calendar: Calendar
    ) -> WidgetSnapshot {
        let dayOfLife = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: birthAt),
            to: calendar.startOfDay(for: now)
        ).day ?? 0
        return WidgetSnapshot(
            nextFeedAt: nextFeedAt,
            milkMl: milkMl,
            feeds: feeds,
            pees: pees,
            poops: poops,
            dayOfLife: max(0, dayOfLife),
            volumeUnit: volumeUnit,
            updatedAt: now
        )
    }
}

struct WidgetSnapshotRefresher {
    let fetchRemoteState: () async throws -> WidgetRemoteState

    func refresh(
        cached: WidgetSnapshot?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async -> WidgetSnapshot? {
        do {
            let remote = try await fetchRemoteState()
            return remote.snapshot(
                volumeUnit: cached?.volumeUnit ?? .ounces,
                now: now,
                calendar: calendar
            )
        } catch {
            return cached
        }
    }
}

struct WidgetRemoteClient {
    private struct PushRegistration: Encodable {
        let token: String
        let environment: String
        let enabled: Bool
    }

    private struct PushRegistrationResponse: Decodable {
        let ok: Bool
    }

    private var baseURL: URL {
        if let override = ProcessInfo.processInfo.environment["ENZO_API_BASE_URL"],
           let url = URL(string: override) {
            return url
        }
        return URL(string: "https://enzo-api.btn0s.workers.dev")!
    }

    private var environment: String {
#if DEBUG
        "sandbox"
#else
        "production"
#endif
    }

    func state() async throws -> WidgetRemoteState {
        var request = URLRequest(url: baseURL.appending(path: "/api/state"))
        request.setValue("Bearer \(EnzoSecrets.apiToken)", forHTTPHeaderField: "Authorization")
        return try await perform(request)
    }

    func registerPushToken(_ token: Data, enabled: Bool) async throws {
        let tokenString = token.map { String(format: "%02x", $0) }.joined()
        var request = URLRequest(url: baseURL.appending(path: "/api/widget-push-devices"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(EnzoSecrets.apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(PushRegistration(
            token: tokenString,
            environment: environment,
            enabled: enabled
        ))
        let response: PushRegistrationResponse = try await perform(request)
        guard response.ok else { throw URLError(.cannotParseResponse) }
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Response.self, from: data)
    }
}
