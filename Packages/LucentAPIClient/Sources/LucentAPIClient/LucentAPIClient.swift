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
        ("GET", "/health"), ("GET", "/v1/me"), ("GET", "/v1/configuration"), ("GET", "/v1/people"),
        ("GET", "/v1/organizations"), ("GET", "/v1/crs"), ("GET", "/v1/sites"), ("GET", "/v1/spots"),
        ("GET", "/v1/matrices"), ("GET", "/v1/collection-classes"), ("GET", "/v1/dimensions"), ("GET", "/v1/units"),
        ("GET", "/v1/parameters"), ("GET", "/v1/devices"), ("PATCH", "/v1/devices/{device_id}"),
        ("GET", "/v1/documents"), ("GET", "/v1/actions"), ("GET", "/v1/coefficients"), ("GET", "/v1/thresholds"),
        ("GET", "/v1/collections"), ("POST", "/v1/collections"), ("GET", "/v1/collections/{collection_id}"),
        ("POST", "/v1/collections/{collection_id}/plan"), ("POST", "/v1/collections/{collection_id}/accept"),
        ("POST", "/v1/values/{value_id}/raw-values"), ("GET", "/v1/values"),
        ("POST", "/v1/raw-values/{raw_value_id}/accept"), ("POST", "/v1/raw-values/{raw_value_id}/withdraw"),
        ("GET", "/v1/series"), ("GET", "/v1/tasks"), ("POST", "/v1/tasks"), ("PATCH", "/v1/tasks/{task_id}"),
        ("GET", "/v1/messages"), ("POST", "/v1/messages"), ("POST", "/v1/messages/{message_id}/read"),
        ("GET", "/v1/people/{person_id}"), ("POST", "/v1/people"), ("PATCH", "/v1/people/{person_id}"),
        ("PUT", "/v1/people/{person_id}/roles"), ("GET", "/v1/people/{person_id}/history"), ("GET", "/v1/roles"),
        ("POST", "/v1/spots"), ("POST", "/v1/sites"),
    ]

    // MARK: Reference data

    public func health() async throws -> LucentAPI.Health { try await send("GET", "/health", authorized: false) }
    public func me() async throws -> LucentAPI.Me { try await send("GET", "/v1/me") }
    public func configuration() async throws -> LucentAPI.Configuration { try await send("GET", "/v1/configuration") }
    public func people() async throws -> [LucentAPI.Person] { try await send("GET", "/v1/people") }
    public func organizations() async throws -> [LucentAPI.Organization] { try await send("GET", "/v1/organizations") }
    public func referenceSystems() async throws -> [LucentAPI.ReferenceSystem] { try await send("GET", "/v1/crs") }
    public func sites() async throws -> [LucentAPI.Site] { try await send("GET", "/v1/sites") }
    public func spots() async throws -> [LucentAPI.Spot] { try await send("GET", "/v1/spots") }
    public func matrices() async throws -> [LucentAPI.Matrix] { try await send("GET", "/v1/matrices") }
    /// The classes lucentBASE allows for a collection.
    public func collectionClasses() async throws -> [String] { try await send("GET", "/v1/collection-classes") }
    public func dimensions() async throws -> [LucentAPI.Dimension] { try await send("GET", "/v1/dimensions") }
    public func units() async throws -> [LucentAPI.Unit] { try await send("GET", "/v1/units") }
    public func parameters() async throws -> [LucentAPI.Parameter] { try await send("GET", "/v1/parameters") }
    public func devices() async throws -> [LucentAPI.Device] { try await send("GET", "/v1/devices") }
    public func documents() async throws -> [LucentAPI.Document] { try await send("GET", "/v1/documents") }
    public func actions() async throws -> [LucentAPI.Action] { try await send("GET", "/v1/actions") }
    public func coefficients() async throws -> [LucentAPI.Coefficient] { try await send("GET", "/v1/coefficients") }
    public func thresholds() async throws -> [LucentAPI.Threshold] { try await send("GET", "/v1/thresholds") }

    /// Switches a device on or off (role admin). Pass the device's current `etag`.
    public func updateDevice(id: Int, etag: String, active: Bool, note: String? = nil) async throws -> LucentAPI.Device {
        struct Change: Encodable { var active: Bool; var note: String? }
        return try await send("PATCH", "/v1/devices/\(id)", body: Change(active: active, note: note), ifMatch: etag)
    }

    // MARK: Collections, values, raw values

    public func collections(status: LucentAPI.Status? = nil, matrixId: Int? = nil, collectionClass: String? = nil,
                            spotId: Int? = nil, siteId: Int? = nil, sampledFrom: Date? = nil,
                            sampledUntil: Date? = nil, limit: Int = 200,
                            offset: Int = 0) async throws -> LucentAPI.Page<LucentAPI.Collection> {
        try await send("GET", "/v1/collections", query: [
            item("status", status?.rawValue), item("matrix_id", matrixId), item("collection_class", collectionClass),
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

    /// Registers a collection and plans the effects of its actions (role sampler). The server
    /// picks the identifier.
    public func registerCollection(_ collection: LucentAPI.NewCollection) async throws -> LucentAPI.CollectionDetail {
        try await send("POST", "/v1/collections", body: collection)
    }

    /// Plans the effects of further actions for a collection (role sampler).
    public func plan(actionIds: [Int], for collectionId: Int, note: String? = nil) async throws -> LucentAPI.CollectionDetail {
        struct Plan: Encodable { var actionIds: [Int]; var note: String? }
        return try await send("POST", "/v1/collections/\(collectionId)/plan", body: Plan(actionIds: actionIds, note: note))
    }

    /// Records a reading of a value (role analyst); a further reading is a repetition.
    public func recordRawValue(_ rawValue: LucentAPI.NewRawValue, for valueId: Int) async throws -> LucentAPI.RawValue {
        try await send("POST", "/v1/values/\(valueId)/raw-values", body: rawValue)
    }

    public func values(collectionIds: [Int] = [], sampledFrom: Date? = nil, sampledUntil: Date? = nil,
                       limit: Int = 1000, offset: Int = 0) async throws -> LucentAPI.Page<LucentAPI.Value> {
        try await send("GET", "/v1/values", query: collectionIds.map { URLQueryItem(name: "collection_id", value: "\($0)") } + [
            item("sampled_from", sampledFrom), item("sampled_until", sampledUntil), item("limit", limit),
            item("offset", offset),
        ])
    }

    /// Every value (with its raw values) of the collections sampled since `sampledFrom`.
    public func allValues(sampledFrom: Date? = nil, pageSize: Int = 5000) async throws -> [LucentAPI.Value] {
        try await allPages { try await values(sampledFrom: sampledFrom, limit: pageSize, offset: $0) }
    }

    /// Accepts a raw value (role reviewer, never for whoever measured it). `etag` guards
    /// against accepting something that changed meanwhile.
    public func acceptRawValue(id: Int, etag: String? = nil, note: String? = nil) async throws -> LucentAPI.RawValue {
        try await send("POST", "/v1/raw-values/\(id)/accept", body: note.map(Note.init), ifMatch: etag)
    }

    public func withdrawRawValue(id: Int, etag: String? = nil, note: String? = nil) async throws -> LucentAPI.RawValue {
        try await send("POST", "/v1/raw-values/\(id)/withdraw", body: note.map(Note.init), ifMatch: etag)
    }

    /// Accepts all open raw values of a collection, or none if the caller measured any of them.
    public func acceptCollection(id: Int, note: String? = nil) async throws -> LucentAPI.CollectionDetail {
        try await send("POST", "/v1/collections/\(id)/accept", body: note.map(Note.init))
    }

    /// One parameter over time at a spot or site.
    public func series(parameterId: Int, spotId: Int? = nil, siteId: Int? = nil) async throws -> [LucentAPI.SeriesPoint] {
        try await send("GET", "/v1/series", query: [
            item("parameter_id", parameterId), item("spot_id", spotId), item("site_id", siteId),
        ])
    }

    // MARK: Locations

    /// Adds a spot (sampler). Names are unique: 409 `name_taken`.
    public func createSpot(_ spot: LucentAPI.NewSpot) async throws -> LucentAPI.Spot {
        try await send("POST", "/v1/spots", body: spot)
    }

    /// Adds a site by its border (sampler). A border that crosses itself is refused with 422
    /// `border_crosses_itself`.
    public func createSite(_ site: LucentAPI.NewSite) async throws -> LucentAPI.Site {
        try await send("POST", "/v1/sites", body: site)
    }

    // MARK: People and roles

    public func person(id: Int) async throws -> LucentAPI.Person { try await send("GET", "/v1/people/\(id)") }
    public func roles() async throws -> [LucentAPI.RoleInfo] { try await send("GET", "/v1/roles") }

    /// Adds a person (admin). They can sign in once their identity provider account has `linuxUser`
    /// as username.
    public func createPerson(_ person: LucentAPI.NewPerson) async throws -> LucentAPI.Person {
        try await send("POST", "/v1/people", body: person)
    }

    /// Changes a person (admin). Pass their current `etag`; if someone changed them meanwhile, this
    /// throws 412.
    public func updatePerson(id: Int, etag: String, _ change: LucentAPI.PersonChange) async throws -> LucentAPI.Person {
        try await send("PATCH", "/v1/people/\(id)", body: change, ifMatch: etag)
    }

    /// Grants and revokes so the person has exactly `roles` (admin). Throws 409 `last_admin` rather
    /// than leave nobody to administer.
    public func setRoles(_ roles: [LucentAPI.Role], of personId: Int, etag: String,
                         note: String? = nil) async throws -> LucentAPI.Person {
        try await send("PUT", "/v1/people/\(personId)/roles", body: Roles(roles: roles, note: note), ifMatch: etag)
    }

    /// Changes to the person, their roles and their organization, newest first.
    public func history(ofPerson id: Int) async throws -> [LucentAPI.HistoryEntry] {
        try await send("GET", "/v1/people/\(id)/history")
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
    private struct Roles: Encodable { var roles: [LucentAPI.Role]; var note: String? }

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
