import Foundation
import Observation

/// The app's data, as the views see it. It is loaded from a `LabService` (the demo data or
/// lucentAPI) and sends changes there, replacing its copies with what comes back.
///
/// The rules follow lucentBASE: a collection's values are its planned effects; their raw
/// values are the readings. The limits of a raw value are the thresholds of its parameter in
/// the documents of its action.
@MainActor
@Observable
final class LabStore {
    let now: Date
    let calendar: Calendar
    let numbering = NumberingScheme.lucent

    // Reference data
    let organizations: [Organization]
    let crs: [CRS]
    let matrices: [Matrix]
    let collectionClasses: [String]
    let dimensions: [PhysicalDimension]
    let units: [LabUnit]
    let parameters: [Parameter]
    let documents: [Document]
    let actions: [LabAction]
    let effects: [Effect]
    let thresholds: [Threshold]
    let coefficients: [Coefficient]
    let samplingTimeParameterID: Int?
    let roleDescriptions: [LabRole: String]
    let service: any LabService

    /// The message of the last change that failed, for an alert.
    var errorMessage: String?

    // What the lab changes
    private(set) var sites: [Site]
    private(set) var spots: [Spot]
    private(set) var people: [Person]
    /// Who is signed in, and what lucentBASE lets them do.
    private(set) var currentUser: Person
    private(set) var roles: Set<LabRole>
    var devices: [Device]
    private(set) var collections: [LabCollection]
    private(set) var valuesByCollection: [Int: [LabValue]]
    private(set) var rawValuesByValue: [Int: [RawValue]]
    var tasks: [LabTask]
    var messages: [Message]

    private let organizationsByID: [Int: Organization]
    private var peopleByID: [Int: Person]
    private var sitesByID: [Int: Site]
    private var spotsByID: [Int: Spot]
    private let matricesByID: [Int: Matrix]
    private let dimensionsByID: [Int: PhysicalDimension]
    private let unitsByID: [Int: LabUnit]
    private let parametersByID: [Int: Parameter]
    private let documentsByID: [Int: Document]
    private let actionsByID: [Int: LabAction]
    private let effectsByID: [Int: Effect]

    init(snapshot: LabSnapshot, service: any LabService, now: Date = .now, calendar: Calendar = .current) {
        let data = snapshot.data
        self.now = now
        self.calendar = calendar
        self.service = service
        roles = snapshot.roles

        organizations = data.organizations
        people = data.people
        crs = data.crs
        sites = data.sites
        spots = data.spots
        matrices = data.matrices
        collectionClasses = data.collectionClasses
        dimensions = data.dimensions
        units = data.units
        parameters = data.parameters
        documents = data.documents
        actions = data.actions
        effects = data.effects
        thresholds = data.thresholds
        coefficients = data.coefficients
        samplingTimeParameterID = data.samplingTimeParameterID
        roleDescriptions = data.roleDescriptions
        devices = data.devices
        collections = data.collections
        valuesByCollection = Dictionary(grouping: data.values, by: \.collectionID)
        rawValuesByValue = Dictionary(grouping: data.rawValues, by: \.valueID)
            .mapValues { $0.sorted { ($0.t ?? .distantPast, $0.id) < ($1.t ?? .distantPast, $1.id) } }
        tasks = data.tasks
        messages = data.messages
        currentUser = data.people.first { $0.id == snapshot.currentUserID }
            ?? Person(id: snapshot.currentUserID, givenName: "", surname: "?", linuxUser: "")

        organizationsByID = Self.index(data.organizations)
        peopleByID = Self.index(data.people)
        sitesByID = Self.index(data.sites)
        spotsByID = Self.index(data.spots)
        matricesByID = Self.index(data.matrices)
        dimensionsByID = Self.index(data.dimensions)
        unitsByID = Self.index(data.units)
        parametersByID = Self.index(data.parameters)
        documentsByID = Self.index(data.documents)
        actionsByID = Self.index(data.actions)
        effectsByID = Self.index(data.effects)
    }

    /// The demo data. Like lucentAndShiny, the user is whoever is logged in to the machine.
    static func demo(now: Date = .now, calendar: Calendar = .current, userName: String = NSUserName()) -> LabStore {
        let data = MockData.make(now: now, calendar: calendar)
        return LabStore(snapshot: MockLabService.snapshot(of: data, userName: userName),
                        service: MockLabService(data: data, userName: userName), now: now, calendar: calendar)
    }

    func can(_ role: LabRole) -> Bool { roles.contains(role) || roles.contains(.admin) }

    /// Whether the data is the demo data in memory rather than lucentAPI.
    var isDemo: Bool { service is MockLabService }

    private static func index<T: Identifiable>(_ items: [T]) -> [Int: T] where T.ID == Int {
        Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: Lookups

    func organization(_ id: Int?) -> Organization? { id.flatMap { organizationsByID[$0] } }
    func person(_ id: Int?) -> Person? { id.flatMap { peopleByID[$0] } }
    func site(_ id: Int?) -> Site? { id.flatMap { sitesByID[$0] } }
    func spot(_ id: Int?) -> Spot? { id.flatMap { spotsByID[$0] } }
    func matrix(_ id: Int?) -> Matrix? { id.flatMap { matricesByID[$0] } }
    func dimension(_ id: Int?) -> PhysicalDimension? { id.flatMap { dimensionsByID[$0] } }
    func unit(_ id: Int?) -> LabUnit? { id.flatMap { unitsByID[$0] } }
    func parameter(_ id: Int?) -> Parameter? { id.flatMap { parametersByID[$0] } }
    func document(_ id: Int?) -> Document? { id.flatMap { documentsByID[$0] } }
    func action(_ id: Int?) -> LabAction? { id.flatMap { actionsByID[$0] } }
    func effect(_ id: Int?) -> Effect? { id.flatMap { effectsByID[$0] } }
    func device(_ id: Int?) -> Device? { id.flatMap { id in devices.first { $0.id == id } } }
    func collection(_ id: Int?) -> LabCollection? { id.flatMap { id in collections.first { $0.id == id } } }
    func referenceSystem(_ id: Int?) -> CRS? { id.flatMap { id in crs.first { $0.id == id } } }

    func members(of organization: Organization) -> [Person] {
        people.filter { $0.organizationID == organization.id }
    }

    /// The parameter an effect yields.
    func parameter(of effect: Effect) -> Parameter? { parameter(effect.parameterID) }

    // MARK: Actions

    func effects(of action: LabAction) -> [Effect] { effects.filter { $0.actionID == action.id } }

    func effects(of parameter: Parameter) -> [Effect] { effects.filter { $0.parameterID == parameter.id } }

    func actions(using device: Device) -> [LabAction] { actions.filter { $0.deviceIDs.contains(device.id) } }

    func actions(referringTo document: Document) -> [LabAction] {
        actions.filter { $0.documentIDs.contains(document.id) }
    }

    func actions(involving person: Person) -> [(action: LabAction, role: String)] {
        actions.flatMap { action in
            action.people.filter { $0.personID == person.id }.map { (action, $0.role) }
        }
    }

    /// The limits that apply to an effect's raw values: the thresholds of its parameter in the
    /// documents of its action.
    func limits(of effect: Effect) -> [Threshold] {
        let documents = Set(action(effect.actionID)?.documentIDs ?? [])
        return thresholds.filter { $0.parameterID == effect.parameterID && documents.contains($0.documentID) }
    }

    func exceeds(_ raw: RawValue, of effect: Effect) -> Bool {
        guard let number = raw.reading?.number else { return false }
        return limits(of: effect).contains { $0.excludes(number) }
    }

    // MARK: Collections

    func values(of collectionID: Int) -> [LabValue] { valuesByCollection[collectionID] ?? [] }

    func rawValues(of value: LabValue) -> [RawValue] { rawValuesByValue[value.id] ?? [] }

    /// The collection's values for the effects of an action.
    func values(of collectionID: Int, for action: LabAction) -> [LabValue] {
        values(of: collectionID).filter { effect($0.effectID)?.actionID == action.id }
    }

    /// The actions with at least one value in the collection, in action order.
    func plannedActions(of collection: LabCollection) -> [LabAction] {
        let ids = Set(values(of: collection.id).compactMap { effect($0.effectID)?.actionID })
        return actions.filter { ids.contains($0.id) }
    }

    func progress(of collection: LabCollection) -> (measured: Int, planned: Int) {
        let values = values(of: collection.id)
        return (values.filter { !rawValues(of: $0).isEmpty }.count, values.count)
    }

    func status(of collection: LabCollection) -> CollectionStatus {
        let (measured, planned) = progress(of: collection)
        if measured == 0 { return .registered }
        if measured < planned { return .inAnalysis }
        let all = values(of: collection.id).flatMap { rawValues(of: $0) }
        return all.allSatisfy(\.accepted) ? .approved : .inReview
    }

    /// The collection's raw values outside their limits, with their values and effects.
    func exceedances(of collection: LabCollection) -> [Exceedance] {
        values(of: collection.id).flatMap { value -> [Exceedance] in
            guard let effect = effect(value.effectID) else { return [] }
            return rawValues(of: value).filter { exceeds($0, of: effect) }
                .map { Exceedance(raw: $0, value: value, collection: collection, effect: effect) }
        }
    }

    func locationName(of collection: LabCollection) -> String {
        spot(collection.spotID)?.name ?? site(collection.siteID)?.name ?? "—"
    }

    func location(of collection: LabCollection) -> LocationRef? {
        if let id = collection.spotID { return .spot(id) }
        if let id = collection.siteID { return .site(id) }
        return nil
    }

    func rows() -> [CollectionRow] {
        collections.map { collection in
            let (measured, planned) = progress(of: collection)
            return CollectionRow(
                id: collection.id,
                name: collection.name,
                sequence: numbering.sequence(of: collection.name) ?? collection.id,
                matrix: matrix(collection.matrixID)?.name ?? "—",
                matrixID: collection.matrixID,
                collectionClass: collection.collectionClass,
                location: locationName(of: collection),
                isSite: collection.spotID == nil,
                sampledAt: collection.sampledAt,
                sampler: person(collection.sampledByID)?.fullName ?? "—",
                status: status(of: collection),
                measured: measured,
                planned: planned,
                exceedances: exceedances(of: collection).count
            )
        }
    }

    var nextIdentifier: String {
        guard let last = collections.compactMap({ numbering.sequence(of: $0.name) }).max() else {
            return numbering.identifier(for: 0)!
        }
        return numbering.identifier(for: last + 1) ?? "¯\\_(ツ)_/¯"
    }

    // MARK: Planning

    /// The combinations of active actions planned for collections of a matrix, most often first
    /// (then most recent first).
    func actionSets(for matrixID: Int) -> [ActionSet] {
        var sets: [[Int]: (count: Int, last: Date)] = [:]
        for collection in collections where collection.matrixID == matrixID {
            let ids = plannedActions(of: collection).filter(\.active).map(\.id)
            guard !ids.isEmpty else { continue }
            let seen = sets[ids]
            sets[ids] = ((seen?.count ?? 0) + 1, max(seen?.last ?? .distantPast, collection.sampledAt))
        }
        return sets.map { ActionSet(actionIDs: $0.key, count: $0.value.count, last: $0.value.last) }
            .sorted { ($0.count, $0.last) > ($1.count, $1.last) }
    }

    /// Active actions by how often they were planned for a matrix, most often first; actions never
    /// planned for it are left out.
    func usualActions(for matrixID: Int) -> [LabAction] {
        var counts: [Int: Int] = [:]
        for set in actionSets(for: matrixID) {
            for id in set.actionIDs { counts[id, default: 0] += set.count }
        }
        return actions.filter { counts[$0.id] != nil }
            .sorted { (counts[$0.id]!, -$0.id) > (counts[$1.id]!, -$1.id) }
    }

    /// Whether an action matches a search: by its name, description, parameters or documents.
    func action(_ action: LabAction, matches search: String) -> Bool {
        let search = search.trimmingCharacters(in: .whitespaces)
        guard !search.isEmpty else { return true }
        let words = [action.name, action.description]
            + effects(of: action).compactMap { parameter($0.parameterID)?.name }
            + action.documentIDs.compactMap { document($0)?.name }
        return words.contains { $0.localizedStandardContains(search) }
    }

    // MARK: Locations

    func collections(at location: LocationRef) -> [LabCollection] {
        switch location {
        case .spot(let id):
            return collections.filter { $0.spotID == id }
        case .site(let id):
            let spotIDs = Set(spots.filter { $0.siteID == id }.map(\.id))
            return collections.filter { $0.siteID == id || $0.spotID.map(spotIDs.contains) == true }
        }
    }

    func spots(in site: Site) -> [Spot] { spots.filter { $0.siteID == site.id } }

    /// The matrix sampled most often at a location.
    func primaryMatrix(at location: LocationRef) -> Matrix? {
        let counts = Dictionary(grouping: collections(at: location), by: \.matrixID).mapValues(\.count)
        return matrix(counts.max { $0.value < $1.value }?.key)
    }

    /// Numeric parameters with readings at a location.
    func measuredParameters(at location: LocationRef) -> [Parameter] {
        let ids = Set(collections(at: location).flatMap { values(of: $0.id) }
            .filter { !rawValues(of: $0).isEmpty }
            .compactMap { effect($0.effectID)?.parameterID })
        return parameters.filter { ids.contains($0.id) && $0.valueClass == .decimal }
    }

    /// A parameter over time at a location: the latest reading per collection.
    func series(at location: LocationRef, for parameter: Parameter) -> [SeriesPoint] {
        collections(at: location).compactMap { collection in
            for value in values(of: collection.id) {
                guard let effect = effect(value.effectID), effect.parameterID == parameter.id,
                      let raw = rawValues(of: value).last, let number = raw.reading?.number else { continue }
                return SeriesPoint(id: raw.id, collectionID: collection.id, date: collection.sampledAt, value: number,
                                   exceeded: exceeds(raw, of: effect), limits: limits(of: effect))
            }
            return nil
        }
        .sorted { $0.date < $1.date }
    }

    // MARK: Dashboard

    func weeklyCounts(weeks: Int = 10) -> [WeeklyCount] {
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
              let start = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeek) else { return [] }
        let recent = collections.filter { $0.sampledAt >= start }
        let grouped = Dictionary(grouping: recent) { collection in
            WeeklyCount.Key(week: calendar.dateInterval(of: .weekOfYear, for: collection.sampledAt)!.start,
                            matrixID: collection.matrixID)
        }
        return grouped.map { key, items in
            WeeklyCount(week: key.week, matrix: matrix(key.matrixID)?.name ?? "—", count: items.count)
        }
        .sorted { ($0.week, $0.matrix) < ($1.week, $1.matrix) }
    }

    func collections(sampledIn interval: DateInterval) -> [LabCollection] {
        collections.filter { interval.contains($0.sampledAt) }
    }

    /// Readings outside their limits in the last `days` days, newest first; one per value.
    func recentExceedances(days: Int = 30) -> [Exceedance] {
        let since = now.addingTimeInterval(-Double(days) * 86_400)
        return collections.filter { $0.sampledAt >= since }
            .flatMap { collection in
                Dictionary(grouping: exceedances(of: collection), by: \.value.id).values.compactMap(\.first)
            }
            .sorted { ($0.collection.sampledAt, $0.raw.id) > ($1.collection.sampledAt, $1.raw.id) }
    }

    var openTasks: [LabTask] { tasks.filter { !$0.done }.sorted { $0.deadline < $1.deadline } }

    func isOverdue(_ task: LabTask) -> Bool { !task.done && task.deadline < now }

    var inbox: [Message] {
        messages.filter { $0.receiverID == currentUser.id }.sorted { $0.sentAt > $1.sentAt }
    }

    // MARK: Changes

    /// Runs a change in the background; if it fails, `errorMessage` says why.
    func perform(_ change: @escaping @MainActor () async throws -> Void) {
        Task {
            do {
                try await change()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    @discardableResult
    func registerCollection(_ new: NewCollection) async throws -> LabCollection {
        let registration = try await service.register(new)
        collections.append(registration.collection)
        valuesByCollection[registration.collection.id] = registration.values
        for raw in registration.rawValues { rawValuesByValue[raw.valueID, default: []].append(raw) }
        return registration.collection
    }

    func record(_ reading: Reading, for value: LabValue) async throws {
        let raw = try await service.record(reading, for: value)
        rawValuesByValue[value.id, default: []].append(raw)
    }

    func setAccepted(_ accepted: Bool, rawValue: RawValue) async throws {
        replace(try await service.setAccepted(accepted, rawValue: rawValue))
    }

    func acceptAll(in collectionIDs: [Int]) async throws {
        for id in collectionIDs {
            for raw in try await service.acceptAll(in: id) { replace(raw) }
        }
    }

    private func replace(_ raw: RawValue) {
        if let index = rawValuesByValue[raw.valueID]?.firstIndex(where: { $0.id == raw.id }) {
            rawValuesByValue[raw.valueID]?[index] = raw
        }
    }

    func setDone(_ done: Bool, task: LabTask) async throws {
        let changed = try await service.setDone(done, task: task)
        if let index = tasks.firstIndex(where: { $0.id == changed.id }) { tasks[index] = changed }
    }

    func setActive(_ active: Bool, device: Device) async throws {
        let changed = try await service.setActive(active, device: device)
        if let index = devices.firstIndex(where: { $0.id == changed.id }) { devices[index] = changed }
    }

    func setRead(_ read: Bool, message: Message) async throws {
        let changed = try await service.setRead(read, message: message)
        if let index = messages.firstIndex(where: { $0.id == changed.id }) { messages[index] = changed }
    }

    // MARK: Locations

    /// Adds a spot or a site and returns where it is.
    @discardableResult
    func create(_ draft: LocationDraft) async throws -> LocationRef {
        switch draft.kind {
        case .spot:
            let spot = try await service.createSpot(draft)
            spots.append(spot)
            spots.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            spotsByID[spot.id] = spot
            return .spot(spot.id)
        case .site:
            let site = try await service.createSite(draft)
            sites.append(site)
            sites.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            sitesByID[site.id] = site
            return .site(site.id)
        }
    }

    /// Saves a drawing: adds the spot or site, or changes the one it edits. Returns where it is.
    @discardableResult
    func save(_ draft: LocationDraft) async throws -> LocationRef {
        switch draft.editing {
        case nil:
            return try await create(draft)
        case .spot(let id):
            guard let spot = spot(id) else { return .spot(id) }
            let changed = try await service.updateSpot(spot, to: draft)
            spots[spots.firstIndex { $0.id == id }!] = changed
            spotsByID[id] = changed
            return .spot(id)
        case .site(let id):
            guard let site = site(id) else { return .site(id) }
            let changed = try await service.updateSite(site, to: draft)
            sites[sites.firstIndex { $0.id == id }!] = changed
            sitesByID[id] = changed
            return .site(id)
        }
    }

    /// The site a point lies in, if any.
    func site(containing point: GeoPoint) -> Site? {
        sites.first { $0.contains(point) }
    }

    // MARK: People

    @discardableResult
    func createPerson(_ draft: PersonDraft, roles: Set<LabRole>, reason: String?) async throws -> Person {
        let person = try await service.createPerson(draft, roles: roles, reason: reason)
        replace(person)
        return person
    }

    /// Saves what changed: the person first, then their roles. `reason` goes into lucentBASE's log.
    @discardableResult
    func save(_ person: Person, as draft: PersonDraft, roles: Set<LabRole>, reason: String?) async throws -> Person {
        var current = person
        if draft != PersonDraft(person) {
            current = try await service.updatePerson(current, to: draft, reason: reason)
            replace(current)
        }
        if roles != current.roles {
            current = try await service.setRoles(roles, of: current, reason: reason)
            replace(current)
        }
        return current
    }

    func history(of person: Person) async throws -> [HistoryEntry] {
        try await service.history(of: person)
    }

    private func replace(_ person: Person) {
        if let index = people.firstIndex(where: { $0.id == person.id }) {
            people[index] = person
        } else {
            people.append(person)
            people.sort { ($0.surname, $0.givenName, $0.id) < ($1.surname, $1.givenName, $1.id) }
        }
        peopleByID[person.id] = person
        if person.id == currentUser.id {
            currentUser = person
            roles = person.roles
        }
    }
}

// MARK: - Derived types for views

struct CollectionRow: Identifiable, Hashable {
    let id: Int
    let name: String
    let sequence: Int
    let matrix: String
    let matrixID: Int
    let collectionClass: String
    let location: String
    let isSite: Bool
    let sampledAt: Date
    let sampler: String
    let status: CollectionStatus
    let measured: Int
    let planned: Int
    let exceedances: Int

    var progress: Double { planned == 0 ? 0 : Double(measured) / Double(planned) }
}

struct SeriesPoint: Identifiable, Hashable {
    let id: Int
    let collectionID: Int
    let date: Date
    let value: Double
    let exceeded: Bool
    let limits: [Threshold]
}

struct WeeklyCount: Identifiable, Hashable {
    struct Key: Hashable {
        let week: Date
        let matrixID: Int
    }

    let week: Date
    let matrix: String
    let count: Int

    var id: String { "\(week.timeIntervalSince1970)-\(matrix)" }
}

/// Actions planned together for a collection, how often and when last.
struct ActionSet: Identifiable, Hashable {
    let actionIDs: [Int]
    let count: Int
    let last: Date

    var id: [Int] { actionIDs }
}

struct Exceedance: Identifiable, Hashable {
    let raw: RawValue
    let value: LabValue
    let collection: LabCollection
    let effect: Effect

    var id: Int { raw.id }
}
