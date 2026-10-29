import Foundation
import LucentAPIClient

/// lucentBASE through lucentAPI. Loads the reference data and the collections of the last
/// `history` with their values, and sends changes to the API.
struct APILabService: LabService {
    let client: LucentAPIClient
    var history: TimeInterval = 26 * 7 * 86_400

    func load() async throws -> LabSnapshot {
        let since = Date.now.addingTimeInterval(-history)
        async let me = client.me()
        async let organizations = client.organizations()
        async let people = client.people()
        async let crs = client.referenceSystems()
        async let sites = client.sites()
        async let spots = client.spots()
        async let matrices = client.matrices()
        async let classes = client.collectionClasses()
        async let dimensions = client.dimensions()
        async let units = client.units()
        async let variables = client.variables()
        async let devices = client.devices()
        async let sops = client.sops()
        async let actions = client.actions()
        async let collections = client.allCollections(sampledFrom: since)
        async let values = client.allValues(sampledFrom: since)
        async let tasks = client.tasks()
        async let messages = client.messages()

        let loadedClasses = try await classes
        let loadedActions = try await actions
        let data = LabData(
            organizations: try await organizations.map(Organization.init),
            people: try await people.map(Person.init),
            crs: try await crs.map(CRS.init),
            sites: try await sites.map(Site.init),
            spots: try await spots.map(Spot.init),
            matrices: try await matrices.map(Matrix.init),
            collectionClasses: loadedClasses.map(CollectionClass.init),
            classActions: Dictionary(uniqueKeysWithValues: loadedClasses.map { ($0.id, $0.actionIds) }),
            dimensions: try await dimensions.map(PhysicalDimension.init),
            units: try await units.map(LabUnit.init),
            variables: try await variables.map(Variable.init),
            devices: try await devices.map(Device.init),
            sops: try await sops.map(SOP.init),
            actions: loadedActions.map(LabAction.init),
            actionVariables: loadedActions.flatMap(\.variables).map(ActionVariable.init),
            collections: try await collections.map(LabCollection.init),
            values: try await values.map(LabValue.init),
            tasks: try await tasks.map(LabTask.init),
            messages: try await messages.map(Message.init))
        let caller = try await me
        return LabSnapshot(data: data, currentUserID: caller.person.id,
                           roles: Set(caller.roles.compactMap { LabRole(rawValue: $0.rawValue) }))
    }

    func register(_ new: NewCollection) async throws -> LabCollection {
        let detail = try await client.registerCollection(.init(
            matrixId: new.matrixID, classId: new.classID, spotId: new.spotID, siteId: new.siteID,
            sampledAt: new.sampledAt, samplerId: new.sampledByID))
        return LabCollection(detail.collection)
    }

    func record(_ reading: Reading, for actionVariable: ActionVariable, in collectionID: Int) async throws -> LabValue {
        LabValue(try await client.recordValue(.init(actionVariableId: actionVariable.id, reading: .init(reading)),
                                              in: collectionID))
    }

    func setAccepted(_ accepted: Bool, value: LabValue) async throws -> LabValue {
        LabValue(accepted
                 ? try await client.acceptValue(id: value.id, etag: value.etag)
                 : try await client.withdrawValue(id: value.id, etag: value.etag))
    }

    func acceptAll(in collectionID: Int) async throws -> [LabValue] {
        try await client.acceptCollection(id: collectionID).values.map(LabValue.init)
    }

    func setDone(_ done: Bool, task: LabTask) async throws -> LabTask {
        LabTask(try await client.updateTask(id: task.id, etag: task.etag ?? "*", .init(done: done)))
    }

    func setActive(_ active: Bool, device: Device) async throws -> Device {
        Device(try await client.updateDevice(id: device.id, etag: device.etag ?? "*", active: active))
    }

    func setRead(_ read: Bool, message: Message) async throws -> Message {
        Message(try await client.markMessage(id: message.id, read: read))
    }
}

// MARK: - From the API's types to the app's

extension Organization {
    init(_ o: LucentAPI.Organization) { self.init(id: o.id, name: o.name, shorthand: o.shorthand ?? "") }
}

extension Person {
    init(_ p: LucentAPI.Person) {
        self.init(id: p.id, givenName: p.givenName ?? "", surname: p.surname, unixAccount: p.unixAccount ?? "",
                  organizationID: p.organizationId, position: p.position)
    }
}

extension CRS {
    init(_ c: LucentAPI.ReferenceSystem) { self.init(id: c.id, epsg: c.epsg, name: c.name) }
}

extension Site {
    init(_ s: LucentAPI.Site) {
        self.init(id: s.id, name: s.name, description: s.description ?? "",
                  address: s.address.map {
                      Address(street: $0.street ?? "", houseNumber: $0.houseNumber ?? "", addition: $0.addition,
                              zip: $0.zip ?? "", district: $0.district ?? "", city: $0.city ?? "")
                  },
                  border: s.border.map { GeoPoint(latitude: $0.latitude, longitude: $0.longitude) },
                  crsID: s.crsId)
    }
}

extension Spot {
    init(_ s: LucentAPI.Spot) {
        self.init(id: s.id, name: s.name, description: s.description ?? "", x: s.x, y: s.y, crsID: s.crsId,
                  siteID: s.siteId)
    }
}

extension Matrix {
    init(_ m: LucentAPI.Matrix) { self.init(id: m.id, name: m.name, description: m.description ?? "") }
}

extension CollectionClass {
    init(_ c: LucentAPI.CollectionClass) { self.init(id: c.id, name: c.name, description: c.description ?? "") }
}

extension PhysicalDimension {
    init(_ d: LucentAPI.Dimension) { self.init(id: d.id, name: d.name, description: d.description ?? "") }
}

extension LabUnit {
    init(_ u: LucentAPI.Unit) { self.init(id: u.id, name: u.name, notations: u.notations, dimensionID: u.dimensionId) }
}

extension Variable {
    init(_ v: LucentAPI.Variable) {
        self.init(id: v.id, name: v.name, valueClass: ValueClass(rawValue: v.valueClass.rawValue) ?? .text,
                  description: v.description ?? "", dimensionID: v.dimensionId)
    }
}

extension Device {
    init(_ d: LucentAPI.Device) {
        self.init(id: d.id, name: d.name, number: d.number ?? "", manufacturerID: d.manufacturerId,
                  operatorID: d.operatorId, active: d.active, etag: d.etag)
    }
}

extension SOP {
    init(_ s: LucentAPI.SOP) {
        self.init(id: s.id, name: s.name, active: s.active,
                  documents: s.documents.map {
                      SOPDocument(id: $0.id, name: $0.name, url: $0.url.flatMap(URL.init(string:)),
                                  filePath: $0.filePath, accepted: $0.accepted, sha256: $0.sha256 ?? "")
                  },
                  people: s.people.map { Assignment(personID: $0.personId, role: $0.role ?? "") })
    }
}

extension LabAction {
    init(_ a: LucentAPI.Action) {
        self.init(id: a.id, name: a.name, standard: a.standard ?? "", iteration: a.iteration ?? 1, active: a.active,
                  description: a.description ?? "", sopID: a.sopId, deviceIDs: a.deviceIds,
                  people: a.people.map { Assignment(personID: $0.personId, role: $0.role ?? "") },
                  dependsOn: a.dependsOn, implies: a.implies)
    }
}

extension ActionVariable {
    init(_ v: LucentAPI.ActionVariable) {
        self.init(id: v.id, actionID: v.actionId, variableID: v.variableId, unitID: v.unitId,
                  uncertainty: v.uncertainty, uncertaintyClass: v.uncertaintyClass == "relative" ? .relative : .absolute,
                  calculation: v.calculation, decimals: v.decimals ?? 1, lowerLimit: v.lowerLimit,
                  upperLimit: v.upperLimit)
    }
}

extension LabCollection {
    init(_ c: LucentAPI.Collection) {
        self.init(id: c.id, name: c.name, matrixID: c.matrixId ?? 0, classID: c.classId ?? 0, spotID: c.spotId,
                  siteID: c.siteId, sampledAt: c.sampledAt ?? .distantPast, sampledByID: c.samplerId)
    }
}

extension Reading {
    init(_ r: LucentAPI.Reading) {
        switch r {
        case .decimal(let value): self = .decimal(value)
        case .text(let value): self = .text(value)
        case .boolean(let value): self = .boolean(value)
        case .datetime(let value): self = .datetime(value)
        }
    }
}

extension LucentAPI.Reading {
    init(_ r: Reading) {
        switch r {
        case .decimal(let value): self = .decimal(value)
        case .text(let value): self = .text(value)
        case .boolean(let value): self = .boolean(value)
        case .datetime(let value): self = .datetime(value)
        }
    }
}

extension LabValue {
    init(_ v: LucentAPI.Value) {
        self.init(id: v.id, collectionID: v.collectionId, actionVariableID: v.actionVariableId, repetition: v.repetition,
                  reading: Reading(v.reading), accepted: v.accepted, measuredAt: v.measuredAt, personID: v.personId,
                  deviceID: v.deviceId, etag: v.etag)
    }
}

extension LabTask {
    init(_ t: LucentAPI.Task) {
        self.init(id: t.id, request: t.request, description: t.description ?? "", assignerID: t.assignerId,
                  assigneeID: t.assigneeId, deadline: t.deadline ?? .distantFuture, done: t.done, etag: t.etag)
    }
}

extension Message {
    init(_ m: LucentAPI.Message) {
        self.init(id: m.id, senderID: m.senderId, receiverID: m.receiverId, subject: m.subject ?? "",
                  body: m.body ?? "", read: m.read, sentAt: m.sentAt ?? .distantPast)
    }
}
