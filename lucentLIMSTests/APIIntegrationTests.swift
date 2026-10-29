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
        #expect(!analyst.collections.isEmpty && !analyst.actions.isEmpty)

        // Register and measure as the analyst.
        let collection = try await analyst.registerCollection(
            matrixID: 10, classID: 1, spotID: 6, siteID: nil, sampledAt: .now, sampledByID: analyst.currentUser.id)
        #expect(analyst.numbering.sequence(of: collection.name) != nil)
        let pH = try #require(analyst.actionVariable(4))
        try await analyst.record(.decimal(9.8), for: pH, in: collection.id)
        try await analyst.record(.decimal(9.7), for: pH, in: collection.id)
        #expect(analyst.values(of: collection.id).map(\.repetition) == [1, 2])
        #expect(analyst.exceedances(of: collection.id).count == 2)
        #expect(analyst.values(of: collection.id).allSatisfy { $0.etag != nil && $0.measuredAt != nil })

        // The analyst can't review; the API says so.
        #expect(await status { try await analyst.acceptAll(in: [collection.id]) } == 403)

        // A reviewer sees the new collection after loading and accepts its values.
        let reviewer = try await store("LUCENT_TEST_REVIEWER")
        let loaded = try #require(reviewer.collection(collection.id))
        #expect(reviewer.status(of: loaded) == .inAnalysis)
        let first = try #require(reviewer.values(of: collection.id).first)
        try await reviewer.setAccepted(true, value: first)
        #expect(reviewer.values(of: collection.id).first?.accepted == true)

        // The analyst's copy of that value is now outdated: its ETag no longer matches.
        let stale = try #require(analyst.values(of: collection.id).first)
        #expect(await status { _ = try await reviewer.service.setAccepted(false, value: stale) } == 412)
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
