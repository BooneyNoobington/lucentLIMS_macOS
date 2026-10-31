import Foundation
import LucentAPIClient
import Testing
@testable import lucentLIMS

/// Runs against a real lucentAPI, e.g. the development server with demo data, when these
/// environment variables are set (xcodebuild passes TEST_RUNNER_<name> on as <name>):
///
/// - LUCENT_TEST_SERVER: e.g. http://localhost:8765
/// - LUCENT_TEST_ANALYST: a token of Dorn, a sampler and analyst (dev/mint_token.py worf)
/// - LUCENT_TEST_REVIEWER: a token of Picard, a reviewer and admin (dev/mint_token.py p47at)
///
/// The roles are the demo data's: lucentBASE grants them, the tokens only say who is calling.
private let testServer = ProcessInfo.processInfo.environment["LUCENT_TEST_SERVER"].flatMap(URL.init(string:))

@MainActor
@Suite(.enabled(if: testServer != nil, "set LUCENT_TEST_SERVER to run against lucentAPI"))
struct APIIntegrationTests {

    func store(_ tokenVariable: String) async throws -> LabStore {
        let token = try #require(ProcessInfo.processInfo.environment[tokenVariable])
        let service = APILabService(client: LucentAPIClient(baseURL: try #require(testServer)) { token })
        return LabStore(snapshot: try await service.load(), service: service)
    }

    @Test func registerMeasureAndReview() async throws {
        let analyst = try await store("LUCENT_TEST_ANALYST")
        #expect(analyst.can(.sampler) && analyst.can(.analyst) && !analyst.can(.reviewer))
        #expect(!analyst.collections.isEmpty && !analyst.effects.isEmpty && !analyst.thresholds.isEmpty)
        #expect(analyst.samplingTimeParameterID != nil)

        // Register pH and conductivity of drinking water at Hochbehälter Nord as the analyst.
        let collection = try await analyst.registerCollection(NewCollection(
            matrixID: 3, collectionClass: "spot sample", spotID: 6, siteID: nil, actionIDs: [3, 4], sampledAt: nil))
        #expect(analyst.numbering.sequence(of: collection.name) != nil)
        #expect(analyst.values(of: collection.id).map(\.effectID) == [5, 6])
        let pH = try #require(analyst.values(of: collection.id).first)
        try await analyst.record(.decimal(9.8), for: pH)
        try await analyst.record(.decimal(9.7), for: pH)
        #expect(analyst.rawValues(of: pH).count == 2)
        #expect(analyst.exceedances(of: collection).count == 2)
        #expect(analyst.rawValues(of: pH).allSatisfy { $0.etag != nil && $0.t != nil })

        // The analyst can't review; the API says so.
        #expect(await status { try await analyst.acceptAll(in: [collection.id]) } == 403)

        // A reviewer sees the new collection after loading and accepts a raw value.
        let reviewer = try await store("LUCENT_TEST_REVIEWER")
        let loaded = try #require(reviewer.collection(collection.id))
        #expect(reviewer.status(of: loaded) == .inAnalysis)
        let first = try #require(reviewer.rawValues(of: pH).first)
        try await reviewer.setAccepted(true, rawValue: first)
        #expect(reviewer.rawValues(of: pH).first?.accepted == true)

        // The analyst's copy of that raw value is now outdated: its ETag no longer matches.
        let stale = try #require(analyst.rawValues(of: pH).first)
        #expect(await status { _ = try await reviewer.service.setAccepted(false, rawValue: stale) } == 412)
    }

    @Test func samplingTimeIsARawValue() async throws {
        let analyst = try await store("LUCENT_TEST_ANALYST")
        let sampledAt = Date(timeIntervalSince1970: (Date.now.timeIntervalSince1970 - 3600).rounded(.down))
        let collection = try await analyst.registerCollection(NewCollection(
            matrixID: 3, collectionClass: "spot sample", spotID: 6, siteID: nil, actionIDs: [1, 3],
            sampledAt: sampledAt))
        #expect(collection.sampledAt == sampledAt)
        #expect(analyst.progress(of: collection) == (1, 3))

        // Without the sampling action, there's nowhere to put the time.
        await #expect(throws: LabServiceError.self) {
            try await analyst.registerCollection(NewCollection(
                matrixID: 3, collectionClass: "spot sample", spotID: 6, siteID: nil, actionIDs: [3], sampledAt: sampledAt))
        }
    }

    @Test func managingPeople() async throws {
        let admin = try await store("LUCENT_TEST_REVIEWER")  // Picard is admin too
        #expect(admin.can(.admin) && admin.roleDescriptions.count == 4)

        var draft = PersonDraft()
        draft.givenName = "Ash"
        draft.surname = "Test \(Int.random(in: 1000...9999))"
        draft.linuxUser = "ash-\(UUID().uuidString.prefix(8).lowercased())"
        draft.organizationID = 2
        draft.position = "Mikrobiologie"
        let ash = try await admin.createPerson(draft, roles: [.analyst], reason: "Integrationstest")
        #expect(ash.roles == [.analyst] && ash.position == "Mikrobiologie" && ash.etag != nil)

        let promoted = try await admin.save(ash, as: PersonDraft(ash), roles: [.analyst, .reviewer], reason: "QS")
        #expect(promoted.roles == [.analyst, .reviewer])
        // The ETag changed; the old copy is refused.
        #expect(await status { _ = try await admin.service.setRoles([], of: ash, reason: nil) } == 412)

        var gone = PersonDraft(promoted)
        gone.active = false
        let deactivated = try await admin.save(promoted, as: gone, roles: promoted.roles, reason: "Testende")
        #expect(!deactivated.active)
        // lucentBASE logs to the second, so the order of these quick changes isn't certain.
        let history = try await admin.history(of: deactivated)
        #expect(history.contains { $0.note == "Deactivated: Testende" && $0.subject == .person })
        #expect(history.contains { $0.note == "Granted reviewer: QS" && $0.subject == .role(.reviewer) })
        #expect(history.contains { $0.note == "Created: Integrationstest" && $0.created })
    }

    @Test func drawingLocations() async throws {
        let sampler = try await store("LUCENT_TEST_ANALYST")  // Dorn is a sampler too
        let suffix = String(UUID().uuidString.prefix(6))
        let border = [GeoPoint(latitude: 49.016, longitude: 8.325), GeoPoint(latitude: 49.016, longitude: 8.332),
                      GeoPoint(latitude: 49.012, longitude: 8.332), GeoPoint(latitude: 49.012, longitude: 8.325)]
        let siteRef = try await sampler.create(LocationDraft(kind: .site, name: "Hafen \(suffix)", border: border))
        guard case .site(let siteID) = siteRef else { Issue.record("not a site"); return }
        #expect(sampler.site(siteID)?.border == border)

        let point = GeoPoint(latitude: 49.014, longitude: 8.329)
        #expect(sampler.site(containing: point)?.id == siteID)
        let spotRef = try await sampler.create(LocationDraft(kind: .spot, name: "Pegel \(suffix)", point: point,
                                                             siteID: siteID))
        guard case .spot(let spotID) = spotRef else { Issue.record("not a spot"); return }
        #expect(sampler.spot(spotID)?.siteID == siteID)

        // lucentAPI refuses a border that crosses itself, too.
        let bowtie = [border[0], border[2], border[1], border[3]]
        #expect(await status { _ = try await sampler.service.createSite(
            LocationDraft(kind: .site, name: "Schleife \(suffix)", border: bowtie)) } == 422)
    }

    /// The HTTP status a call fails with, or nil if it succeeds.
    func status(_ call: () async throws -> Void) async -> Int? {
        do {
            try await call()
            return nil
        } catch {
            return (error as? LucentAPIError)?.status
        }
    }

    @Test func tasksNeedTheCurrentVersion() async throws {
        let analyst = try await store("LUCENT_TEST_ANALYST")
        let task = try #require(analyst.tasks.first { $0.assigneeID == analyst.currentUser.id || $0.assignerID == analyst.currentUser.id })
        try await analyst.setDone(!task.done, task: task)
        #expect(analyst.tasks.first { $0.id == task.id }?.done == !task.done)
        #expect(await status { try await analyst.setDone(task.done, task: task) } == 412)  // old ETag
        let current = try #require(analyst.tasks.first { $0.id == task.id })
        try await analyst.setDone(task.done, task: current)
    }
}
