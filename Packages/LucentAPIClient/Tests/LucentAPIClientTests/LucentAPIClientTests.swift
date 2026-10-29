import Foundation
import Testing
@testable import LucentAPIClient

/// Answers requests from fixture files and remembers what was sent.
actor FakeServer {
    var requests: [URLRequest] = []
    var status = 200
    var responseFile = "collection"

    func respond(_ status: Int, with file: String) {
        self.status = status
        responseFile = file
    }

    func handle(_ request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (try fixture(responseFile), response)
    }

    var last: URLRequest? { requests.last }
}

func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

func client(_ server: FakeServer, base: String = "https://lims.example.org") -> LucentAPIClient {
    LucentAPIClient(baseURL: URL(string: base)!, transport: { try await server.handle($0) }) { "token-123" }
}

func json(_ request: URLRequest?) throws -> [String: Any] {
    let body = try #require(request?.httpBody)
    return try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
}

struct DecodingTests {
    let decoder = LucentAPIClient.decoder

    @Test func referenceData() throws {
        #expect(try decoder.decode([LucentAPI.Person].self, from: fixture("people")).count == 6)
        #expect(try decoder.decode([LucentAPI.Organization].self, from: fixture("organizations")).count == 6)
        #expect(try decoder.decode([LucentAPI.ReferenceSystem].self, from: fixture("crs")).first?.epsg == 4326)
        #expect(try decoder.decode([LucentAPI.Matrix].self, from: fixture("matrices")).count == 4)
        #expect(try decoder.decode([LucentAPI.Dimension].self, from: fixture("dimensions")).count == 5)
        #expect(try decoder.decode([LucentAPI.Variable].self, from: fixture("variables")).last?.valueClass == .boolean)
        #expect(try decoder.decode([LucentAPI.Device].self, from: fixture("devices")).allSatisfy { !$0.etag.isEmpty })
        #expect(try decoder.decode([LucentAPI.Task].self, from: fixture("tasks")).isEmpty == false)
        #expect(try decoder.decode([LucentAPI.Message].self, from: fixture("messages")).first?.read == false)
        #expect(try decoder.decode(LucentAPI.Me.self, from: fixture("me")).roles == [])
    }

    @Test func nestedCatalog() throws {
        let classes = try decoder.decode([LucentAPI.CollectionClass].self, from: fixture("collection-classes"))
        #expect(classes.first { $0.id == 2 }?.actionIds == [8, 9])
        let units = try decoder.decode([LucentAPI.Unit].self, from: fixture("units"))
        #expect(units.first { $0.id == 3 }?.notations == ["µS/cm", "µS cm⁻¹"])
        let actions = try decoder.decode([LucentAPI.Action].self, from: fixture("actions"))
        let anions = try #require(actions.first { $0.id == 5 })
        #expect(anions.variables.map(\.variableId) == [4, 5, 6])
        #expect(anions.variables.first?.upperLimit == 50)
        #expect(anions.dependsOn == [1] && anions.implies == [4])
        let sops = try decoder.decode([LucentAPI.SOP].self, from: fixture("sops"))
        #expect(sops.first { $0.id == 4 }?.documents.count == 2)
    }

    @Test func locations() throws {
        let sites = try decoder.decode([LucentAPI.Site].self, from: fixture("sites"))
        let works = try #require(sites.first { $0.id == 2 })
        #expect(works.address?.city == "Karlsruhe")
        #expect(works.border.first == LucentAPI.GeoPoint(latitude: 48.999, longitude: 8.451))
        let spots = try decoder.decode([LucentAPI.Spot].self, from: fixture("spots"))
        #expect(spots.first { $0.name == "Garten" }?.x == 49.006097)
    }

    @Test func collectionWithValues() throws {
        let detail = try decoder.decode(LucentAPI.CollectionDetail.self, from: fixture("collection"))
        #expect(detail.collection.status == .inAnalysis)
        #expect(detail.collection.sampledAt == Date(timeIntervalSince1970: 1_793_266_200))  // 2026-10-29T09:30:00Z
        #expect(detail.values.map(\.repetition) == [1, 2])
        #expect(detail.values.first?.reading == .decimal(12.4))
        #expect(detail.values.allSatisfy { $0.exceeds })

        let page = try decoder.decode(LucentAPI.Page<LucentAPI.Collection>.self, from: fixture("collections"))
        #expect(page.items.count == 3 && page.total > 3)
        let values = try decoder.decode(LucentAPI.Page<LucentAPI.Value>.self, from: fixture("values"))
        #expect(values.items.count == 3)
        let series = try decoder.decode([LucentAPI.SeriesPoint].self, from: fixture("series"))
        #expect(series.contains { $0.exceeds })
    }

    @Test func readingsOfEveryKind() throws {
        let decode = { (text: String) in try self.decoder.decode(LucentAPI.Reading.self, from: Data(text.utf8)) }
        #expect(try decode(#"{"decimal": null, "text": "farblos", "boolean": null, "datetime": null}"#) == .text("farblos"))
        #expect(try decode(#"{"boolean": false}"#) == .boolean(false))
        #expect(try decode(#"{"datetime": "2026-10-29T09:30:00.250000Z"}"#)
            == .datetime(Date(timeIntervalSince1970: 1_793_266_200.25)))
        #expect(throws: DecodingError.self) { try decode("{}") }

        let encoded = try LucentAPIClient.encoder.encode(LucentAPI.Reading.decimal(7.5))
        #expect(String(decoding: encoded, as: UTF8.self) == #"{"decimal":7.5}"#)
    }
}

@Suite struct RequestTests {
    @Test func bearerTokenAndPathUnderABasePath() async throws {
        let server = FakeServer()
        await server.respond(200, with: "people")
        _ = try await client(server, base: "https://apps.example.org/lucent").people()
        let request = try #require(await server.last)
        #expect(request.url?.absoluteString == "https://apps.example.org/lucent/v1/people")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token-123")
        #expect(request.httpMethod == "GET")
    }

    @Test func healthNeedsNoToken() async throws {
        let server = FakeServer()
        await server.respond(200, with: "health-ok")
        _ = try? await client(server).health()
        #expect(await server.last?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func registerSendsSnakeCase() async throws {
        let server = FakeServer()
        await server.respond(201, with: "collection-created")
        let created = try await client(server).registerCollection(.init(
            matrixId: 9, classId: 3, spotId: 4, sampledAt: Date(timeIntervalSince1970: 1_793_266_200), note: "Example"))
        #expect(created.collection.name == "1·Blue·6·Phi")
        let request = await server.last
        #expect(request?.httpMethod == "POST")
        #expect(request?.url?.path == "/v1/collections")
        let body = try json(request)
        #expect(body["matrix_id"] as? Int == 9 && body["spot_id"] as? Int == 4)
        #expect(body["sampled_at"] as? String == "2026-10-29T09:30:00Z")
        #expect(body["site_id"] == nil)
    }

    @Test func recordValue() async throws {
        let server = FakeServer()
        await server.respond(201, with: "value-recorded")
        let value = try await client(server).recordValue(.init(actionVariableId: 9, reading: .decimal(11.9)), in: 44)
        #expect(value.repetition == 2)
        let body = try json(await server.last)
        #expect(body["action_variable_id"] as? Int == 9)
        #expect((body["reading"] as? [String: Double]) == ["decimal": 11.9])
        #expect(await server.last?.url?.path == "/v1/collections/44/values")
    }

    @Test func updateTaskSendsIfMatch() async throws {
        let server = FakeServer()
        await server.respond(200, with: "value-recorded")  // the body doesn't matter here
        _ = try? await client(server).updateTask(id: 3, etag: "\"abc\"", .init(done: true))
        let request = await server.last
        #expect(request?.httpMethod == "PATCH")
        #expect(request?.value(forHTTPHeaderField: "If-Match") == "\"abc\"")
        let body = try json(request) as NSDictionary
        #expect(body == ["done": true])
    }

    @Test func queryParameters() async throws {
        let server = FakeServer()
        await server.respond(200, with: "values")
        _ = try await client(server).values(collectionIds: [1, 2], sampledFrom: Date(timeIntervalSince1970: 1_793_266_200))
        let query = try #require(await server.last?.url?.query())
        #expect(query == "collection_id=1&collection_id=2&sampled_from=2026-10-29T09:30:00Z&limit=1000&offset=0")
    }

    @Test func errorsCarryTheirCode() async throws {
        let server = FakeServer()
        await server.respond(403, with: "error-four-eyes")
        await #expect(throws: LucentAPIError(status: 403, code: "four_eyes",
                                             message: "Values have to be accepted by someone other than who measured them.",
                                             requestId: "example")) {
            try await client(server).acceptValue(id: 232)
        }
    }

    @Test func pagesAreFollowed() async throws {
        let server = FakeServer()
        await server.respond(200, with: "collections")  // three items of a larger total, every time
        let total = try LucentAPIClient.decoder.decode(LucentAPI.Page<LucentAPI.Collection>.self,
                                                        from: fixture("collections")).total
        let all = try await client(server).allCollections(pageSize: 3)
        #expect(all.count >= total)
        #expect(await server.requests.count == (total + 2) / 3)
    }
}

struct ContractTests {
    /// Every endpoint the client calls exists in the API description.
    @Test func endpointsExistInTheOpenAPIDocument() throws {
        let document = try #require(JSONSerialization.jsonObject(with: fixture("openapi")) as? [String: Any])
        let paths = try #require(document["paths"] as? [String: [String: Any]])
        for (method, path) in LucentAPIClient.endpoints {
            #expect(paths[path]?[method.lowercased()] != nil, "\(method) \(path)")
        }
    }

    /// The client covers every endpoint of the API.
    @Test func everyEndpointIsCovered() throws {
        let document = try #require(JSONSerialization.jsonObject(with: fixture("openapi")) as? [String: Any])
        let paths = try #require(document["paths"] as? [String: [String: Any]])
        let offered = Set(paths.flatMap { path, operations in operations.keys.map { "\($0.uppercased()) \(path)" } })
        let used = Set(LucentAPIClient.endpoints.map { "\($0.method) \($0.path)" })
        #expect(offered == used)
    }
}
