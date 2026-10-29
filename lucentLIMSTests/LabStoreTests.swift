import Foundation
import Testing
@testable import lucentLIMS

@MainActor
struct LabStoreTests {
    static let now = Date(timeIntervalSince1970: 1_793_300_000)
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    func makeStore(userName: String = "grindel") -> LabStore {
        LabStore.demo(now: Self.now, calendar: Self.calendar, userName: userName)
    }

    @Test func mockDataIsDeterministic() {
        let first = MockData.make(now: Self.now, calendar: Self.calendar)
        let second = MockData.make(now: Self.now, calendar: Self.calendar)
        #expect(first.collections == second.collections)
        #expect(first.values == second.values)
    }

    @Test func mockCollectionsAreNumberedInSamplingOrder() {
        let store = makeStore()
        let sorted = store.collections.sorted { $0.sampledAt < $1.sampledAt }
        let sequences = sorted.map { store.numbering.sequence(of: $0.name) }
        #expect(sequences == Array(3000..<3000 + sorted.count))
        #expect(store.collections.allSatisfy { $0.sampledAt <= Self.now })
    }

    @Test func currentUserIsTheLoggedInAccount() {
        #expect(makeStore(userName: "xx121").currentUser.surname == "Ripley")
        #expect(makeStore(userName: "nobody").currentUser.unixAccount == "grindel")
    }

    @Test func statusFollowsTheValues() async throws {
        let store = makeStore()
        let collection = try await store.registerCollection(matrixID: 10, classID: 1, spotID: 6, siteID: nil,
                                                            sampledAt: Self.now, sampledByID: 26)
        #expect(store.status(of: collection) == .registered)

        let planned = store.plannedVariables(for: collection)
        #expect(planned.count == 7)

        try await store.record(.decimal(12.3), for: planned[0], in: collection.id)
        #expect(store.status(of: collection) == .inAnalysis)
        #expect(store.progress(of: collection) == (1, 7))

        for actionVariable in planned.dropFirst() {
            try await store.record(.decimal(0), for: actionVariable, in: collection.id)
        }
        #expect(store.status(of: collection) == .inReview)
        #expect(store.values(of: collection.id).allSatisfy { $0.personID == store.currentUser.id })
    }

    @Test func nobodyAcceptsTheirOwnValues() async throws {
        let store = makeStore()
        let collection = try await store.registerCollection(matrixID: 10, classID: 1, spotID: 6, siteID: nil,
                                                            sampledAt: Self.now, sampledByID: 26)
        let pH = try #require(store.actionVariable(4))
        try await store.record(.decimal(7.5), for: pH, in: collection.id)
        await #expect(throws: LabServiceError.self) { try await store.acceptAll(in: [collection.id]) }
        let value = try #require(store.values(of: collection.id).first)
        await #expect(throws: LabServiceError.self) { try await store.setAccepted(true, value: value) }
        #expect(store.values(of: collection.id).first?.accepted == false)
    }

    @Test func reviewingSomeoneElsesValues() async throws {
        let store = makeStore()
        let inReview = try #require(store.collections.first { store.status(of: $0) == .inReview })
        try await store.acceptAll(in: [inReview.id])
        #expect(store.status(of: inReview) == .approved)

        let value = try #require(store.values(of: inReview.id).first)
        try await store.setAccepted(false, value: value)
        #expect(store.status(of: inReview) == .inReview)
    }

    @Test func registeringUsesTheNextIdentifier() async throws {
        let store = makeStore()
        let expected = store.nextIdentifier
        let collection = try await store.registerCollection(matrixID: 8, classID: 2, spotID: 3, siteID: nil,
                                                            sampledAt: Self.now, sampledByID: 27)
        #expect(collection.name == expected)
        #expect(store.nextIdentifier == store.numbering.next(after: expected))
    }

    @Test func recordingAgainAddsARepetition() async throws {
        let store = makeStore()
        let collection = try await store.registerCollection(matrixID: 9, classID: 3, spotID: 4, siteID: nil,
                                                            sampledAt: Self.now, sampledByID: 26)
        let lead = try #require(store.actionVariable(9))
        try await store.record(.decimal(12), for: lead, in: collection.id)
        try await store.record(.decimal(11.5), for: lead, in: collection.id)
        #expect(store.values(of: collection.id, for: lead).map(\.repetition) == [1, 2])
        #expect(store.exceedances(of: collection.id).count == 2)
    }

    @Test func demoHasEveryRole() {
        let store = makeStore()
        #expect(LabRole.allCases.allSatisfy { store.can($0) })
        #expect(store.isDemo)
    }

    @Test func limitsAreChecked() throws {
        let store = makeStore()
        let pH = try #require(store.actionVariable(4))
        #expect(!pH.exceeds(.decimal(7.2)))
        #expect(pH.exceeds(.decimal(6.4)))
        #expect(pH.exceeds(.decimal(9.6)))

        let odour = try #require(store.actionVariable(3))
        #expect(!odour.exceeds(.boolean(false)))
        #expect(odour.exceeds(.boolean(true)))

        let colour = try #require(store.actionVariable(2))
        #expect(!colour.exceeds(.text("braun")))
    }

    @Test func seriesIsChronologicalAndFlagsExceedances() throws {
        let store = makeStore()
        let nitrate = try #require(store.actionVariable(6))
        let series = store.series(at: .spot(10), for: nitrate)
        #expect(!series.isEmpty)
        #expect(series.map(\.date) == series.map(\.date).sorted())
        #expect(series.allSatisfy { $0.exceeded == ($0.value > 50) })
    }

    @Test func siteIncludesItsSpots() {
        let store = makeStore()
        let atSite = Set(store.collections(at: .site(2)).map(\.id))
        for spot in [7, 8, 9] {
            #expect(Set(store.collections(at: .spot(spot)).map(\.id)).isSubset(of: atSite))
        }
    }

    @Test func weeklyCountsCoverRecentCollections() throws {
        let store = makeStore()
        let thisWeek = try #require(Self.calendar.dateInterval(of: .weekOfYear, for: Self.now)?.start)
        let start = try #require(Self.calendar.date(byAdding: .weekOfYear, value: -9, to: thisWeek))
        let recent = store.collections.filter { $0.sampledAt >= start }.count
        #expect(store.weeklyCounts().map(\.count).reduce(0, +) == recent)
    }
}
