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
        #expect(first.rawValues == second.rawValues)
    }

    @Test func mockCollectionsAreNumberedInSamplingOrder() {
        let store = makeStore()
        let sorted = store.collections.sorted { $0.sampledAt < $1.sampledAt }
        let sequences = sorted.map { store.numbering.sequence(of: $0.name) }
        #expect(sequences == Array(3001..<3001 + sorted.count))
        #expect(store.collections.allSatisfy { $0.sampledAt <= Self.now })
    }

    @Test func mockSamplingTimesAreRawValues() throws {
        let store = makeStore()
        let sampledByAction = store.collections.filter { collection in
            store.plannedActions(of: collection).contains { $0.id == 1 || $0.id == 8 }
        }
        #expect(!sampledByAction.isEmpty)
        for collection in sampledByAction.prefix(20) {
            let slot = try #require(store.values(of: collection.id).first {
                store.effect($0.effectID)?.parameterID == store.samplingTimeParameterID
            })
            #expect(store.rawValues(of: slot).first?.reading == .datetime(collection.sampledAt))
        }
    }

    @Test func currentUserIsTheLoggedInAccount() {
        #expect(makeStore(userName: "xx121").currentUser.surname == "Ripley")
        #expect(makeStore(userName: "nobody").currentUser.linuxUser == "grindel")
    }

    /// pH and conductivity on drinking water at Hochbehälter Nord.
    static let pHAndConductivity = NewCollection(matrixID: 3, collectionClass: "spot sample", spotID: 5, siteID: nil,
                                                 actionIDs: [3, 4], sampledAt: nil)

    @Test func everyEffectOfThePlannedActionsIsAValue() async throws {
        let store = makeStore()
        let collection = try await store.registerCollection(Self.pHAndConductivity)
        #expect(store.values(of: collection.id).map(\.effectID) == [5, 6])
        #expect(store.plannedActions(of: collection).map(\.id) == [3, 4])
        #expect(collection.collectionClass == "spot sample")
    }

    @Test func statusFollowsTheRawValues() async throws {
        let store = makeStore()
        let collection = try await store.registerCollection(Self.pHAndConductivity)
        #expect(store.status(of: collection) == .registered)

        let values = store.values(of: collection.id)
        try await store.record(.decimal(7.4), for: values[0])
        #expect(store.status(of: collection) == .inAnalysis)
        #expect(store.progress(of: collection) == (1, 2))

        try await store.record(.decimal(512), for: values[1])
        #expect(store.status(of: collection) == .inReview)
        #expect(values.flatMap { store.rawValues(of: $0) }.allSatisfy { $0.personID == store.currentUser.id })
    }

    @Test func samplingTimeIsRecordedAsARawValue() async throws {
        let store = makeStore()
        let sampledAt = Self.now.addingTimeInterval(-3 * 3600)
        var new = Self.pHAndConductivity
        new.actionIDs = [1, 3]
        new.sampledAt = sampledAt
        let collection = try await store.registerCollection(new)
        #expect(collection.sampledAt == sampledAt)
        let slot = try #require(store.values(of: collection.id).first { store.effect($0.effectID)?.parameterID == 1 })
        #expect(store.rawValues(of: slot).map(\.reading) == [.datetime(sampledAt)])
        #expect(store.progress(of: collection) == (1, 3))
    }

    @Test func samplingTimeNeedsItsParameter() async throws {
        let store = makeStore()
        var new = Self.pHAndConductivity
        new.sampledAt = Self.now
        await #expect(throws: LabServiceError.self) { try await store.registerCollection(new) }
        #expect(store.collections.count == makeStore().collections.count)
    }

    @Test func nobodyAcceptsTheirOwnRawValues() async throws {
        let store = makeStore()
        let collection = try await store.registerCollection(Self.pHAndConductivity)
        let pH = try #require(store.values(of: collection.id).first)
        try await store.record(.decimal(7.5), for: pH)
        await #expect(throws: LabServiceError.self) { try await store.acceptAll(in: [collection.id]) }
        let raw = try #require(store.rawValues(of: pH).first)
        await #expect(throws: LabServiceError.self) { try await store.setAccepted(true, rawValue: raw) }
        #expect(store.rawValues(of: pH).first?.accepted == false)
    }

    @Test func reviewingSomeoneElsesRawValues() async throws {
        let store = makeStore()
        let inReview = try #require(store.collections.first { store.status(of: $0) == .inReview })
        try await store.acceptAll(in: [inReview.id])
        #expect(store.status(of: inReview) == .approved)

        let value = try #require(store.values(of: inReview.id).first)
        let raw = try #require(store.rawValues(of: value).first)
        try await store.setAccepted(false, rawValue: raw)
        #expect(store.status(of: inReview) == .inReview)
    }

    @Test func registeringUsesTheNextIdentifier() async throws {
        let store = makeStore()
        let expected = store.nextIdentifier
        let collection = try await store.registerCollection(Self.pHAndConductivity)
        #expect(collection.name == expected)
        #expect(store.nextIdentifier == store.numbering.next(after: expected))
    }

    @Test func recordingAgainAddsARepetition() async throws {
        let store = makeStore()
        let collection = try await store.registerCollection(NewCollection(
            matrixID: 2, collectionClass: "spot sample", spotID: 3, siteID: nil, actionIDs: [6], sampledAt: nil))
        let lead = try #require(store.values(of: collection.id).first { store.effect($0.effectID)?.parameterID == 10 })
        try await store.record(.decimal(12), for: lead)
        try await store.record(.decimal(11.5), for: lead)
        #expect(store.rawValues(of: lead).compactMap(\.reading?.number) == [12, 11.5])
        #expect(store.exceedances(of: collection).count == 2)
    }

    @Test func demoUserIsAdmin() {
        let store = makeStore()
        #expect(store.roles == [.admin] && LabRole.allCases.allSatisfy { store.can($0) })
        #expect(store.isDemo)
        #expect(makeStore(userName: "xx121").roles == [.analyst])
        #expect(!makeStore(userName: "xx121").can(.reviewer))
    }

    // MARK: Planning

    @Test func actionSetsAreRankedByHowOftenTheyWerePlanned() throws {
        let store = makeStore()
        let drinkingWater = store.actionSets(for: 3)  // Trinkwasser: routine weekly, full every four weeks
        let routine = try #require(drinkingWater.first)
        #expect(routine.actionIDs == [1, 2, 3, 4, 7])
        #expect(drinkingWater.dropFirst().contains { $0.actionIDs == [1, 2, 3, 4, 5, 6, 7] })
        #expect(drinkingWater.map(\.count) == drinkingWater.map(\.count).sorted(by: >))
        #expect(drinkingWater.map(\.count).reduce(0, +) == store.collections.filter { $0.matrixID == 3 }.count)
        #expect(store.usualActions(for: 1).map(\.id) == [8, 9])  // air: dust and NO2 only
    }

    @Test func actionsAreFoundByParameterAndDocument() throws {
        let store = makeStore()
        let anions = try #require(store.action(5))
        #expect(store.action(anions, matches: "Nitrat"))  // a parameter
        #expect(store.action(anions, matches: "IC-3"))  // a document, the device manual
        #expect(store.action(anions, matches: ""))
        #expect(!store.action(anions, matches: "Feinstaub"))
    }

    // MARK: Locations

    static let harbour = [GeoPoint(latitude: 49.016, longitude: 8.325), GeoPoint(latitude: 49.016, longitude: 8.332),
                          GeoPoint(latitude: 49.012, longitude: 8.332), GeoPoint(latitude: 49.012, longitude: 8.325)]

    @Test func drawingASiteAndASpotInIt() async throws {
        let store = makeStore()
        var site = LocationDraft(kind: .site, name: "Rheinhafen", border: Self.harbour)
        #expect(site.problem == nil)
        let siteRef = try await store.create(site)
        let created = try #require(store.sites.first { $0.name == "Rheinhafen" })
        #expect(siteRef == .site(created.id) && created.border == Self.harbour && created.crsID == 1)

        let inside = GeoPoint(latitude: 49.014, longitude: 8.329)
        #expect(store.site(containing: inside)?.id == created.id)
        #expect(store.site(containing: GeoPoint(latitude: 49.02, longitude: 8.329)) == nil)
        let spot = LocationDraft(kind: .spot, name: "Pegel Hafen", point: inside, siteID: created.id)
        guard case .spot(let id) = try await store.create(spot) else { Issue.record("not a spot"); return }
        #expect(store.spot(id)?.siteID == created.id && store.spot(id)?.point == inside)

        site.name = "GWM 12"  // names are unique per kind; a site may share a spot's name
        try await store.create(site)
        await #expect(throws: LabServiceError.self) { try await store.create(spot) }
    }

    @Test func editingASpot() async throws {
        let store = makeStore()
        let gwm = try #require(store.spots.first { $0.name == "GWM 12" })
        #expect(gwm.siteID == 3)
        var draft = LocationDraft(editing: gwm)
        #expect(draft.editing == .spot(gwm.id) && draft.problem == nil)
        draft.name = "GWM 12a"
        draft.point = GeoPoint(latitude: 49.0320, longitude: 8.3050)
        draft.siteID = nil
        #expect(try await store.save(draft) == .spot(gwm.id))
        let moved = try #require(store.spot(gwm.id))
        #expect(moved.name == "GWM 12a" && moved.point == draft.point && moved.siteID == nil)
        #expect(store.spots.count == makeStore().spots.count)  // changed, not added

        draft.name = "Garten"  // another spot's name
        await #expect(throws: LabServiceError.self) { try await store.save(draft) }
    }

    @Test func redrawingASite() async throws {
        let store = makeStore()
        let site = try #require(store.site(2))
        var draft = LocationDraft(editing: site)
        draft.border.remove(at: 3)
        draft.description = "Nur noch drei Ecken"
        try await store.save(draft)
        #expect(store.site(2)?.border.count == 3 && store.site(2)?.description == "Nur noch drei Ecken")
        #expect(store.sites.count == makeStore().sites.count)
    }

    @Test func aClickNearAnEdgeAddsACornerThere() {
        let square = [GeoPoint(latitude: 1, longitude: 0), GeoPoint(latitude: 1, longitude: 1),
                      GeoPoint(latitude: 0, longitude: 1), GeoPoint(latitude: 0, longitude: 0)]
        var editing = LocationDraft(kind: .site, border: square)
        editing.editing = .site(1)
        editing.addCorner(GeoPoint(latitude: 0.5, longitude: 1.1))  // beside the right edge, corners 2 and 3
        #expect(editing.border.firstIndex(of: GeoPoint(latitude: 0.5, longitude: 1.1)) == 2)
        editing.addCorner(GeoPoint(latitude: 0.6, longitude: -0.1))  // beside the left edge, from the last corner to the first
        #expect(editing.border.last == GeoPoint(latitude: 0.6, longitude: -0.1))
        #expect(!Border.crossesItself(editing.border))

        var drawing = LocationDraft(kind: .site, border: square)  // a new drawing just goes on
        drawing.addCorner(GeoPoint(latitude: 0.5, longitude: 1.1))
        #expect(drawing.border.last == GeoPoint(latitude: 0.5, longitude: 1.1))
    }

    @Test func aBorderMustNotCrossItself() {
        let bowtie = [Self.harbour[0], Self.harbour[2], Self.harbour[1], Self.harbour[3]]
        #expect(Border.crossesItself(bowtie) && !Border.crossesItself(Self.harbour))
        #expect(LocationDraft(kind: .site, name: "Schleife", border: bowtie).problem != nil)
        #expect(LocationDraft(kind: .site, name: "Zwei", border: Array(Self.harbour.prefix(2))).problem != nil)
        #expect(LocationDraft(kind: .site, name: "Viel zu langer Name für eine Site", border: Self.harbour).problem != nil)
        #expect(LocationDraft(kind: .spot, name: "Ohne Ort").problem != nil)
    }

    // MARK: People

    @Test func grantingReviewerToRipley() async throws {
        let store = makeStore()
        let ripley = try #require(store.person(MockData.ripley))
        let saved = try await store.save(ripley, as: PersonDraft(ripley), roles: [.analyst, .reviewer],
                                         reason: "Übernimmt die QS")
        #expect(saved.roles == [.analyst, .reviewer] && store.person(MockData.ripley)?.roles == [.analyst, .reviewer])
        let history = try await store.history(of: saved)
        #expect(history.first?.note == "Granted reviewer: Übernimmt die QS")
        #expect(history.first?.subject == .role(.reviewer) && history.first?.editorID == MockData.system)
    }

    @Test func addingAPerson() async throws {
        let store = makeStore()
        var draft = PersonDraft()
        draft.givenName = "Ash"
        draft.surname = "Science Officer"
        draft.linuxUser = "ash"
        draft.organizationID = 2
        draft.position = "Mikrobiologie"
        let ash = try await store.createPerson(draft, roles: [.analyst], reason: nil)
        #expect(store.people.contains(ash) && ash.active && ash.roles == [.analyst])
        #expect(try await store.history(of: ash).map(\.note).last == "Created")

        draft.linuxUser = "worf"
        await #expect(throws: LabServiceError.self) { try await store.createPerson(draft, roles: [], reason: nil) }
    }

    @Test func theLastAdminStaysAdminAndActive() async throws {
        let store = makeStore()
        let picard = try #require(store.person(MockData.picard))
        try await store.save(picard, as: PersonDraft(picard), roles: [.reviewer], reason: nil)
        let you = store.currentUser
        await #expect(throws: LabServiceError.self) {
            try await store.save(you, as: PersonDraft(you), roles: [], reason: nil)
        }
        var inactive = PersonDraft(you)
        inactive.active = false
        await #expect(throws: LabServiceError.self) {
            try await store.save(you, as: inactive, roles: you.roles, reason: nil)
        }
        #expect(store.can(.admin))
    }

    @Test func deactivatingSomeoneElse() async throws {
        let store = makeStore()
        let dorn = try #require(store.person(MockData.dorn))
        var draft = PersonDraft(dorn)
        draft.active = false
        let saved = try await store.save(dorn, as: draft, roles: dorn.roles, reason: "Zur Enterprise gewechselt")
        #expect(!saved.active && store.people.contains { $0.id == MockData.dorn && !$0.active })
        #expect(try await store.history(of: saved).first?.note == "Deactivated: Zur Enterprise gewechselt")
    }

    @Test func changingYourOwnRolesChangesWhatYouMay() async throws {
        let store = makeStore()
        let you = store.currentUser
        try await store.save(you, as: PersonDraft(you), roles: [.admin, .reviewer], reason: nil)
        #expect(store.roles == [.admin, .reviewer] && store.currentUser.roles == [.admin, .reviewer])
    }

    func raw(_ reading: Reading) -> RawValue { RawValue(id: 0, valueID: 0, reading: reading, accepted: false) }

    @Test func limitsComeFromTheDocumentsOfTheAction() throws {
        let store = makeStore()
        let pH = try #require(store.effect(5))
        #expect(store.limits(of: pH).map(\.documentID) == [12])
        #expect(!store.exceeds(raw(.decimal(7.2)), of: pH))
        #expect(store.exceeds(raw(.decimal(6.4)), of: pH))
        #expect(store.exceeds(raw(.decimal(9.6)), of: pH))

        // The old pH method refers to its SOP only, not to the drinking water ordinance.
        let oldPH = try #require(store.effect(19))
        #expect(store.limits(of: oldPH).isEmpty)
        #expect(!store.exceeds(raw(.decimal(9.6)), of: oldPH))

        // Groundwater and drinking water: nitrate has a threshold in both.
        let nitrate = try #require(store.effect(7))
        #expect(Set(store.limits(of: nitrate).map(\.documentID)) == [12, 13])

        let odour = try #require(store.effect(4))
        #expect(!store.exceeds(raw(.boolean(false)), of: odour))
        #expect(store.exceeds(raw(.boolean(true)), of: odour))

        let colour = try #require(store.effect(3))
        #expect(!store.exceeds(raw(.text("braun")), of: colour))
    }

    @Test func seriesIsChronologicalAndFlagsExceedances() throws {
        let store = makeStore()
        let nitrate = try #require(store.parameter(7))
        let series = store.series(at: .spot(9), for: nitrate)
        #expect(!series.isEmpty)
        #expect(series.map(\.date) == series.map(\.date).sorted())
        #expect(series.allSatisfy { $0.exceeded == ($0.value > 50) })
        #expect(series.contains { $0.exceeded })
    }

    @Test func siteIncludesItsSpots() {
        let store = makeStore()
        let atSite = Set(store.collections(at: .site(2)).map(\.id))
        for spot in [6, 7, 8] {
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
