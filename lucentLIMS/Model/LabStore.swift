import Foundation
import Observation

/// The app's data. For now it holds mock data in memory; later this is where lucentBASE
/// comes in.
@MainActor
@Observable
final class LabStore {
    let now: Date
    let calendar: Calendar
    let numbering = NumberingScheme.lucent

    // Reference data
    let organizations: [Organization]
    let people: [Person]
    let crs: [CRS]
    let sites: [Site]
    let spots: [Spot]
    let matrices: [Matrix]
    let collectionClasses: [CollectionClass]
    let dimensions: [PhysicalDimension]
    let units: [LabUnit]
    let variables: [Variable]
    let sops: [SOP]
    let actions: [LabAction]
    let actionVariables: [ActionVariable]
    let currentUser: Person

    // What the lab changes
    var devices: [Device]
    private(set) var collections: [LabCollection]
    private(set) var valuesByCollection: [Int: [LabValue]]
    var tasks: [LabTask]
    var messages: [Message]

    private let classActions: [Int: [Int]]
    private let organizationsByID: [Int: Organization]
    private let peopleByID: [Int: Person]
    private let sitesByID: [Int: Site]
    private let spotsByID: [Int: Spot]
    private let matricesByID: [Int: Matrix]
    private let classesByID: [Int: CollectionClass]
    private let dimensionsByID: [Int: PhysicalDimension]
    private let unitsByID: [Int: LabUnit]
    private let variablesByID: [Int: Variable]
    private let sopsByID: [Int: SOP]
    private let actionsByID: [Int: LabAction]
    private let actionVariablesByID: [Int: ActionVariable]
    @ObservationIgnored private var nextValueID: Int

    init(data: LabData? = nil, now: Date = .now, calendar: Calendar = .current, userName: String = NSUserName()) {
        let data = data ?? MockData.make(now: now, calendar: calendar)
        self.now = now
        self.calendar = calendar

        organizations = data.organizations
        people = data.people
        crs = data.crs
        sites = data.sites
        spots = data.spots
        matrices = data.matrices
        collectionClasses = data.collectionClasses
        dimensions = data.dimensions
        units = data.units
        variables = data.variables
        sops = data.sops
        actions = data.actions
        actionVariables = data.actionVariables
        devices = data.devices
        collections = data.collections
        valuesByCollection = Dictionary(grouping: data.values, by: \.collectionID)
        tasks = data.tasks
        messages = data.messages
        classActions = data.classActions

        // Like lucentAndShiny, the user is whoever is logged in to the machine.
        currentUser = data.people.first { $0.unixAccount == userName } ?? data.people[0]

        organizationsByID = Self.index(data.organizations)
        peopleByID = Self.index(data.people)
        sitesByID = Self.index(data.sites)
        spotsByID = Self.index(data.spots)
        matricesByID = Self.index(data.matrices)
        classesByID = Self.index(data.collectionClasses)
        dimensionsByID = Self.index(data.dimensions)
        unitsByID = Self.index(data.units)
        variablesByID = Self.index(data.variables)
        sopsByID = Self.index(data.sops)
        actionsByID = Self.index(data.actions)
        actionVariablesByID = Self.index(data.actionVariables)
        nextValueID = (data.values.map(\.id).max() ?? 0) + 1
    }

    private static func index<T: Identifiable>(_ items: [T]) -> [Int: T] where T.ID == Int {
        Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }

    // MARK: Lookups

    func organization(_ id: Int?) -> Organization? { id.flatMap { organizationsByID[$0] } }
    func person(_ id: Int?) -> Person? { id.flatMap { peopleByID[$0] } }
    func site(_ id: Int?) -> Site? { id.flatMap { sitesByID[$0] } }
    func spot(_ id: Int?) -> Spot? { id.flatMap { spotsByID[$0] } }
    func matrix(_ id: Int?) -> Matrix? { id.flatMap { matricesByID[$0] } }
    func collectionClass(_ id: Int?) -> CollectionClass? { id.flatMap { classesByID[$0] } }
    func dimension(_ id: Int?) -> PhysicalDimension? { id.flatMap { dimensionsByID[$0] } }
    func unit(_ id: Int?) -> LabUnit? { id.flatMap { unitsByID[$0] } }
    func variable(_ id: Int?) -> Variable? { id.flatMap { variablesByID[$0] } }
    func sop(_ id: Int?) -> SOP? { id.flatMap { sopsByID[$0] } }
    func action(_ id: Int?) -> LabAction? { id.flatMap { actionsByID[$0] } }
    func actionVariable(_ id: Int?) -> ActionVariable? { id.flatMap { actionVariablesByID[$0] } }
    func device(_ id: Int?) -> Device? { id.flatMap { id in devices.first { $0.id == id } } }
    func collection(_ id: Int?) -> LabCollection? { id.flatMap { id in collections.first { $0.id == id } } }
    func referenceSystem(_ id: Int?) -> CRS? { id.flatMap { id in crs.first { $0.id == id } } }

    func members(of organization: Organization) -> [Person] {
        people.filter { $0.organizationID == organization.id }
    }

    // MARK: Methods

    func actions(forClass classID: Int) -> [LabAction] {
        (classActions[classID] ?? []).compactMap { actionsByID[$0] }
    }

    func classes(using action: LabAction) -> [CollectionClass] {
        collectionClasses.filter { classActions[$0.id]?.contains(action.id) == true }
    }

    func actionVariables(of action: LabAction) -> [ActionVariable] {
        actionVariables.filter { $0.actionID == action.id }
    }

    func actionVariables(of variable: Variable) -> [ActionVariable] {
        actionVariables.filter { $0.variableID == variable.id }
    }

    func actions(using device: Device) -> [LabAction] {
        actions.filter { $0.deviceIDs.contains(device.id) }
    }

    func actions(involving person: Person) -> [(action: LabAction, role: String)] {
        actions.flatMap { action in
            action.people.filter { $0.personID == person.id }.map { (action, $0.role) }
        }
    }

    func sops(involving person: Person) -> [(sop: SOP, role: String)] {
        sops.flatMap { sop in sop.people.filter { $0.personID == person.id }.map { (sop, $0.role) } }
    }

    func actions(following sop: SOP) -> [LabAction] {
        actions.filter { $0.sopID == sop.id }
    }

    // MARK: Collections

    func plannedVariables(for collection: LabCollection) -> [ActionVariable] {
        actions(forClass: collection.classID).flatMap(actionVariables(of:))
    }

    func values(of collectionID: Int) -> [LabValue] {
        valuesByCollection[collectionID] ?? []
    }

    func values(of collectionID: Int, for actionVariable: ActionVariable) -> [LabValue] {
        values(of: collectionID).filter { $0.actionVariableID == actionVariable.id }.sorted { $0.repetition < $1.repetition }
    }

    func progress(of collection: LabCollection) -> (measured: Int, planned: Int) {
        let planned = Set(plannedVariables(for: collection).map(\.id))
        let measured = Set(values(of: collection.id).map(\.actionVariableID)).intersection(planned)
        return (measured.count, planned.count)
    }

    func status(of collection: LabCollection) -> CollectionStatus {
        let (measured, planned) = progress(of: collection)
        if measured == 0 { return .registered }
        if measured < planned { return .inAnalysis }
        return values(of: collection.id).allSatisfy(\.accepted) ? .approved : .inReview
    }

    func exceedances(of collectionID: Int) -> [LabValue] {
        values(of: collectionID).filter { value in
            actionVariable(value.actionVariableID)?.exceeds(value.reading) == true
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
            let matrix = self.matrix(collection.matrixID)
            return CollectionRow(
                id: collection.id,
                name: collection.name,
                sequence: numbering.sequence(of: collection.name) ?? collection.id,
                matrix: matrix?.name ?? "—",
                matrixID: collection.matrixID,
                collectionClass: collectionClass(collection.classID)?.name ?? "—",
                location: locationName(of: collection),
                isSite: collection.spotID == nil,
                sampledAt: collection.sampledAt,
                sampler: person(collection.sampledByID)?.fullName ?? "—",
                status: status(of: collection),
                measured: measured,
                planned: planned,
                exceedances: exceedances(of: collection.id).count
            )
        }
    }

    var nextIdentifier: String {
        guard let last = collections.compactMap({ numbering.sequence(of: $0.name) }).max() else {
            return numbering.identifier(for: 0)!
        }
        return numbering.identifier(for: last + 1) ?? "¯\\_(ツ)_/¯"
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

    /// Numeric variables measured at a location, in method order.
    func measuredVariables(at location: LocationRef) -> [ActionVariable] {
        let ids = Set(collections(at: location).flatMap { values(of: $0.id) }.map(\.actionVariableID))
        return actionVariables.filter { ids.contains($0.id) && variable($0.variableID)?.valueClass == .decimal }
    }

    func series(at location: LocationRef, for actionVariable: ActionVariable) -> [SeriesPoint] {
        collections(at: location).compactMap { collection in
            let values = self.values(of: collection.id, for: actionVariable)
            guard let value = values.last, let number = value.reading.number else { return nil }
            return SeriesPoint(id: value.id, collectionID: collection.id, date: collection.sampledAt,
                               value: number, exceeded: actionVariable.exceeds(value.reading))
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

    /// Values above or below their limits in the last `days` days, newest first.
    func recentExceedances(days: Int = 30) -> [Exceedance] {
        let since = now.addingTimeInterval(-Double(days) * 86_400)
        return collections.filter { $0.sampledAt >= since }.flatMap { collection in
            exceedances(of: collection.id)
                .filter { $0.repetition == 1 }
                .compactMap { value in
                    actionVariable(value.actionVariableID).map {
                        Exceedance(value: value, collection: collection, actionVariable: $0)
                    }
                }
        }
        .sorted { $0.collection.sampledAt > $1.collection.sampledAt }
    }

    var openTasks: [LabTask] { tasks.filter { !$0.done }.sorted { $0.deadline < $1.deadline } }

    func isOverdue(_ task: LabTask) -> Bool { !task.done && task.deadline < now }

    var inbox: [Message] {
        messages.filter { $0.receiverID == currentUser.id }.sorted { $0.sentAt > $1.sentAt }
    }

    // MARK: Changes

    @discardableResult
    func registerCollection(matrixID: Int, classID: Int, spotID: Int?, siteID: Int?,
                            sampledAt: Date, sampledByID: Int) -> LabCollection {
        let collection = LabCollection(
            id: (collections.map(\.id).max() ?? 0) + 1, name: nextIdentifier,
            matrixID: matrixID, classID: classID, spotID: spotID, siteID: siteID,
            sampledAt: sampledAt, sampledByID: sampledByID)
        collections.append(collection)
        return collection
    }

    func record(_ reading: Reading, for actionVariable: ActionVariable, in collectionID: Int) {
        let action = self.action(actionVariable.actionID)
        let deviceID = action?.deviceIDs.first { id in device(id)?.active == true }
        let repetition = (values(of: collectionID, for: actionVariable).map(\.repetition).max() ?? 0) + 1
        let value = LabValue(id: nextValueID, collectionID: collectionID, actionVariableID: actionVariable.id,
                             repetition: repetition, reading: reading, accepted: false,
                             measuredAt: .now, personID: currentUser.id, deviceID: deviceID)
        nextValueID += 1
        valuesByCollection[collectionID, default: []].append(value)
    }

    func setAccepted(_ accepted: Bool, valueID: Int, in collectionID: Int) {
        guard let index = valuesByCollection[collectionID]?.firstIndex(where: { $0.id == valueID }) else { return }
        valuesByCollection[collectionID]?[index].accepted = accepted
    }

    func acceptAll(in collectionIDs: some Sequence<Int>) {
        for id in collectionIDs {
            guard var values = valuesByCollection[id] else { continue }
            for index in values.indices { values[index].accepted = true }
            valuesByCollection[id] = values
        }
    }

    func setDone(_ done: Bool, taskID: Int) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].done = done
    }

    func setActive(_ active: Bool, deviceID: Int) {
        guard let index = devices.firstIndex(where: { $0.id == deviceID }) else { return }
        devices[index].active = active
    }

    func setRead(_ read: Bool, messageID: Int) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        messages[index].read = read
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

struct Exceedance: Identifiable, Hashable {
    let value: LabValue
    let collection: LabCollection
    let actionVariable: ActionVariable

    var id: Int { value.id }
}
