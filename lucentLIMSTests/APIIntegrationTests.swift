import Foundation
import LucentAPIClient
import Testing
@testable import lucentLIMS

/// Runs against a real lucentAPI, e.g. the development server with demo data, when these
/// environment variables are set (xcodebuild passes TEST_RUNNER_<name> on as <name>):
///
/// - LUCENT_TEST_SERVER: e.g. http://localhost:8765
/// - LUCENT_TEST_ANALYST: a token of a sampler and analyst (dev/mint_token.py worf sampler analyst)
/// - LUCENT_TEST_REVIEWER: a token of a reviewer (dev/mint_token.py xx121 reviewer)
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
