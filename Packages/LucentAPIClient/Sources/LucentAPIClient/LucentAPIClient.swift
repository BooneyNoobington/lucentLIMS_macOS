import Foundation

/// An error answer of lucentAPI: `{"error": {"code", "message", "request_id", "details"?}}`.
public struct LucentAPIError: Error, LocalizedError, Hashable, Sendable {
    /// The HTTP status, e.g. 403.
    public var status: Int
    /// A stable code, e.g. `four_eyes`, `precondition_failed`, `unknown_person`.
    public var code: String
    public var message: String
    public var requestId: String?

    public var errorDescription: String? { message }
}

/// A client for lucentAPI, without dependencies: Codable types and an async transport.
///
/// ```swift
/// let api = LucentAPIClient(baseURL: URL(string: "https://lims.example.org")!) {
///     try await tokens.accessToken()
/// }
/// let open = try await api.collections(status: .inReview)
/// ```
public struct LucentAPIClient: Sendable {
    /// Returns a current access token; called before every request.
    public typealias TokenProvider = @Sendable () async throws -> String
    /// Sends a request. The default is `URLSession.shared`; tests pass their own.
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public let baseURL: URL
    private let token: TokenProvider
    private let transport: Transport

    public init(baseURL: URL, transport: @escaping Transport = { try await URLSession.shared.data(for: $0) },
                token: @escaping TokenProvider) {
        self.baseURL = baseURL
        self.transport = transport
        self.token = token
    }

    /// The endpoints this client uses, as in `openapi.json` (checked by the tests).
    public static let endpoints: [(method: String, path: String)] = [
        ("GET", "/health"), ("GET", "/v1/me"), ("GET", "/v1/people"), ("GET", "/v1/organizations"),
        ("GET", "/v1/crs"), ("GET", "/v1/sites"), ("GET", "/v1/spots"), ("GET", "/v1/matrices"),
        ("GET", "/v1/collection-classes"), ("GET", "/v1/dimensions"), ("GET", "/v1/units"),
        ("GET", "/v1/variables"), ("GET", "/v1/devices"), ("PATCH", "/v1/devices/{device_id}"), ("GET", "/v1/sops"),
        ("GET", "/v1/actions"), ("GET", "/v1/collections"), ("POST", "/v1/collections"),
        ("GET", "/v1/collections/{collection_id}"), ("POST", "/v1/collections/{collection_id}/values"),
        ("POST", "/v1/collections/{collection_id}/accept"), ("GET", "/v1/values"),
        ("POST", "/v1/values/{value_id}/accept"), ("POST", "/v1/values/{value_id}/withdraw"), ("GET", "/v1/series"),
        ("GET", "/v1/tasks"), ("POST", "/v1/tasks"), ("PATCH", "/v1/tasks/{task_id}"), ("GET", "/v1/messages"),
        ("POST", "/v1/messages"), ("POST", "/v1/messages/{message_id}/read"),
    ]

    // MARK: Reference data

    public func health() async throws -> LucentAPI.Health { try await send("GET", "/health", authorized: false) }
    public func me() async throws -> LucentAPI.Me { try await send("GET", "/v1/me") }
    public func people() async throws -> [LucentAPI.Person] { try await send("GET", "/v1/people") }
    public func organizations() async throws -> [LucentAPI.Organization] { try await send("GET", "/v1/organizations") }
    public func referenceSystems() async throws -> [LucentAPI.ReferenceSystem] { try await send("GET", "/v1/crs") }
    public func sites() async throws -> [LucentAPI.Site] { try await send("GET", "/v1/sites") }
    public func spots() async throws -> [LucentAPI.Spot] { try await send("GET", "/v1/spots") }
    public func matrices() async throws -> [LucentAPI.Matrix] { try await send("GET", "/v1/matrices") }
    public func collectionClasses() async throws -> [LucentAPI.CollectionClass] {
        try await send("GET", "/v1/collection-classes")
    }
    public func dimensions() async throws -> [LucentAPI.Dimension] { try await send("GET", "/v1/dimensions") }
    public func units() async throws -> [LucentAPI.Unit] { try await send("GET", "/v1/units") }
    public func variables() async throws -> [LucentAPI.Variable] { try await send("GET", "/v1/variables") }
    public func devices() async throws -> [LucentAPI.Device] { try await send("GET", "/v1/devices") }
    public func sops() async throws -> [LucentAPI.SOP] { try await send("GET", "/v1/sops") }
    public func actions() async throws -> [LucentAPI.Action] { try await send("GET", "/v1/actions") }

    /// Switches a device on or off (role admin). Pass the device's current `etag`.
    public func updateDevice(id: Int, etag: String, active: Bool, note: String? = nil) async throws -> LucentAPI.Device {
        struct Change: Encodable { var active: Bool; var note: String? }
        return try await send("PATCH", "/v1/devices/\(id)", body: Change(active: active, note: note), ifMatch: etag)
    }

    // MARK: Collections and values

    public func collections(status: LucentAPI.Status? = nil, matrixId: Int? = nil, classId: Int? = nil,
                            spotId: Int? = nil, siteId: Int? = nil, sampledFrom: Date? = nil,
                            sampledUntil: Date? = nil, limit: Int = 200,
                            offset: Int = 0) async throws -> LucentAPI.Page<LucentAPI.Collection> {
        try await send("GET", "/v1/collections", query: [
            item("status", status?.rawValue), item("matrix_id", matrixId), item("class_id", classId),
            item("spot_id", spotId), item("site_id", siteId), item("sampled_from", sampledFrom),
            item("sampled_until", sampledUntil), item("limit", limit), item("offset", offset),
        ])
    }

    /// Every collection sampled since `sampledFrom`, fetched page by page.
    public func allCollections(sampledFrom: Date? = nil, pageSize: Int = 1000) async throws -> [LucentAPI.Collection] {
        try await allPages { try await collections(sampledFrom: sampledFrom, limit: pageSize, offset: $0) }
    }

    public func collection(id: Int) async throws -> LucentAPI.CollectionDetail {
        try await send("GET", "/v1/collections/\(id)")
    }

    /// Registers a collection (role sampler). The server picks the identifier.
    public func registerCollection(_ collection: LucentAPI.NewCollection) async throws -> LucentAPI.CollectionDetail {
        try await send("POST", "/v1/collections", body: collection)
    }

    /// Records a reading (role analyst); a further reading of a variable is its next repetition.
    public func recordValue(_ value: LucentAPI.NewValue, in collectionId: Int) async throws -> LucentAPI.Value {
        try await send("POST", "/v1/collections/\(collectionId)/values", body: value)
    }

    public func values(collectionIds: [Int] = [], sampledFrom: Date? = nil, sampledUntil: Date? = nil,
                       limit: Int = 1000, offset: Int = 0) async throws -> LucentAPI.Page<LucentAPI.Value> {
        try await send("GET", "/v1/values", query: collectionIds.map { URLQueryItem(name: "collection_id", value: "\($0)") } + [
            item("sampled_from", sampledFrom), item("sampled_until", sampledUntil), item("limit", limit),
            item("offset", offset),
        ])
    }

    /// Every value of the collections sampled since `sampledFrom`, fetched page by page.
    public func allValues(sampledFrom: Date? = nil, pageSize: Int = 5000) async throws -> [LucentAPI.Value] {
        try await allPages { try await values(sampledFrom: sampledFrom, limit: pageSize, offset: $0) }
    }

    /// Accepts a value (role reviewer, never for whoever measured it). `etag` guards against
    /// accepting something that changed meanwhile.
    public func acceptValue(id: Int, etag: String? = nil, note: String? = nil) async throws -> LucentAPI.Value {
        try await send("POST", "/v1/values/\(id)/accept", body: note.map(Note.init), ifMatch: etag)
    }

    public func withdrawValue(id: Int, etag: String? = nil, note: String? = nil) async throws -> LucentAPI.Value {
        try await send("POST", "/v1/values/\(id)/withdraw", body: note.map(Note.init), ifMatch: etag)
    }

    /// Accepts all open values of a collection, or none if the caller measured any of them.
    public func acceptCollection(id: Int, note: String? = nil) async throws -> LucentAPI.CollectionDetail {
        try await send("POST", "/v1/collections/\(id)/accept", body: note.map(Note.init))
    }

    public func series(actionVariableId: Int, spotId: Int? = nil,
                       siteId: Int? = nil) async throws -> [LucentAPI.SeriesPoint] {
        try await send("GET", "/v1/series", query: [
            item("action_variable_id", actionVariableId), item("spot_id", spotId), item("site_id", siteId),
        ])
    }

    // MARK: Tasks and messages

    public func tasks(onlyMine: Bool = false, open: Bool? = nil) async throws -> [LucentAPI.Task] {
        try await send("GET", "/v1/tasks", query: [item("assignee", onlyMine ? "me" : "anyone"), item("open", open)])
    }

    public func createTask(_ task: LucentAPI.NewTask) async throws -> LucentAPI.Task {
        try await send("POST", "/v1/tasks", body: task)
    }

    /// Changes a task. Pass its current `etag`; if someone changed it meanwhile, this throws 412.
    public func updateTask(id: Int, etag: String, _ change: LucentAPI.TaskChange) async throws -> LucentAPI.Task {
        try await send("PATCH", "/v1/tasks/\(id)", body: change, ifMatch: etag)
    }

    public func messages() async throws -> [LucentAPI.Message] { try await send("GET", "/v1/messages") }

    public func sendMessage(_ message: LucentAPI.NewMessage) async throws -> LucentAPI.Message {
        try await send("POST", "/v1/messages", body: message)
    }

    public func markMessage(id: Int, read: Bool = true) async throws -> LucentAPI.Message {
        try await send("POST", "/v1/messages/\(id)/read", query: [item("read", read)])
    }

    // MARK: Plumbing

    private struct Note: Encodable { var note: String? }

    private struct ErrorBody: Decodable {
        struct Detail: Decodable { var code: String; var message: String; var requestId: String? }
        var error: Detail
    }

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            // The API sends "…T09:30:00Z", or "…T09:30:00.123456Z" with fractional seconds.
            if let date = try? Date(text, strategy: .iso8601) { return date }
            if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Not an ISO 8601 time: \(text)"))
        }
        return decoder
    }()

    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private func item(_ name: String, _ value: (any CustomStringConvertible)?) -> URLQueryItem {
        URLQueryItem(name: name, value: value.map { "\($0)" })
    }

    private func item(_ name: String, _ date: Date?) -> URLQueryItem {
        URLQueryItem(name: name, value: date?.formatted(.iso8601))
    }

    private func allPages<Item>(
        _ page: (Int) async throws -> LucentAPI.Page<Item>
    ) async throws -> [Item] {
        var items: [Item] = []
        while true {
            let next = try await page(items.count)
            items += next.items
            if next.items.isEmpty || items.count >= next.total { return items }
        }
    }

    private func send<Response: Decodable>(
        _ method: String, _ path: String, query: [URLQueryItem] = [], body: (any Encodable)? = nil,
        ifMatch: String? = nil, authorized: Bool = true
    ) async throws -> Response {
        var components = URLComponents(url: baseURL.appending(path: String(path.dropFirst())),
                                       resolvingAgainstBaseURL: false)!
        let query = query.filter { $0.value != nil }
        components.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authorized {
            request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        }
        if let ifMatch {
            request.setValue(ifMatch, forHTTPHeaderField: "If-Match")
        }
        if let body {
            request.httpBody = try Self.encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await transport(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if let body = try? Self.decoder.decode(ErrorBody.self, from: data) {
                throw LucentAPIError(status: status, code: body.error.code, message: body.error.message,
                                     requestId: body.error.requestId)
            }
            throw LucentAPIError(status: status, code: "http_\(status)",
                                 message: HTTPURLResponse.localizedString(forStatusCode: status))
        }
        return try Self.decoder.decode(Response.self, from: data)
    }
}
