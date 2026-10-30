import Foundation
import LucentAPIClient

/// lucentBASE through lucentAPI. Loads the reference data and the collections of the last
/// `history` with their values and raw values, and sends changes to the API.
struct APILabService: LabService {
    let client: LucentAPIClient
    var history: TimeInterval = 26 * 7 * 86_400

    func load() async throws -> LabSnapshot {
        let since = Date.now.addingTimeInterval(-history)
        async let me = client.me()
        async let configuration = client.configuration()
        async let organizations = client.organizations()
        async let people = client.people()
        async let crs = client.referenceSystems()
        async let sites = client.sites()
        async let spots = client.spots()
        async let matrices = client.matrices()
        async let dimensions = client.dimensions()
        async let units = client.units()
        async let parameters = client.parameters()
        async let devices = client.devices()
        async let documents = client.documents()
        async let actions = client.actions()
        async let thresholds = client.thresholds()
        async let coefficients = client.coefficients()
        async let collections = client.allCollections(sampledFrom: since)
        async let values = client.allValues(sampledFrom: since)
        async let tasks = client.tasks()
        async let messages = client.messages()

        let loadedConfiguration = try await configuration
        let loadedActions = try await actions
        let loadedValues = try await values
        let data = LabData(
            organizations: try await organizations.map(Organization.init),
            people: try await people.map(Person.init),
            crs: try await crs.map(CRS.init),
            sites: try await sites.map(Site.init),
            spots: try await spots.map(Spot.init),
            matrices: try await matrices.map(Matrix.init),
            collectionClasses: loadedConfiguration.collectionClasses,
            dimensions: try await dimensions.map(PhysicalDimension.init),
            units: try await units.map(LabUnit.init),
            parameters: try await parameters.map(Parameter.init),
            devices: try await devices.map(Device.init),
            documents: try await documents.map(Document.init),
            actions: loadedActions.map(LabAction.init),
            effects: loadedActions.flatMap(\.effects).map(Effect.init),
            thresholds: try await thresholds.map(Threshold.init),
            coefficients: try await coefficients.map(Coefficient.init),
            collections: try await collections.map(LabCollection.init),
            values: loadedValues.map(LabValue.init),
            rawValues: loadedValues.flatMap(\.rawValues).map(RawValue.init),
            tasks: try await tasks.map(LabTask.init),
            messages: try await messages.map(Message.init),
            samplingTimeParameterID: loadedConfiguration.samplingTimeParameterId)
        let caller = try await me
        return LabSnapshot(data: data, currentUserID: caller.person.id,
                           roles: Set(caller.roles.compactMap { LabRole(rawValue: $0.rawValue) }))
    }

    func register(_ new: NewCollection) async throws -> Registration {
        let detail: LucentAPI.CollectionDetail
        do {
            detail = try await client.registerCollection(.init(
                matrixId: new.matrixID, collectionClass: new.collectionClass, spotId: new.spotID, siteId: new.siteID,
                actionIds: new.actionIDs, sampledAt: new.sampledAt))
        } catch let error as LucentAPIError where error.code == "sampling_time_not_planned" {
            throw LabServiceError.samplingTimeNotPlanned
        }
        return Registration(collection: LabCollection(detail.collection), values: detail.values.map(LabValue.init),
                            rawValues: detail.values.flatMap(\.rawValues).map(RawValue.init))
    }

    func record(_ reading: Reading, for value: LabValue) async throws -> RawValue {
        RawValue(try await client.recordRawValue(.init(reading: .init(reading)), for: value.id))
    }

    func setAccepted(_ accepted: Bool, rawValue: RawValue) async throws -> RawValue {
        RawValue(accepted
                 ? try await client.acceptRawValue(id: rawValue.id, etag: rawValue.etag)
                 : try await client.withdrawRawValue(id: rawValue.id, etag: rawValue.etag))
    }

    func acceptAll(in collectionID: Int) async throws -> [RawValue] {
        try await client.acceptCollection(id: collectionID).values.flatMap(\.rawValues).map(RawValue.init)
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
    init(_ o: LucentAPI.Organization) { self.init(id: o.id, name: o.name ?? "", shorthand: o.shorthand ?? "") }
}

extension Person {
    init(_ p: LucentAPI.Person) {
        self.init(id: p.id, givenName: p.givenName, surname: p.surname, linuxUser: p.linuxUser ?? "",
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
                      Address(street: $0.street ?? "", houseNumber: $0.houseNumber.map(String.init) ?? "",
                              addition: $0.addition, zip: $0.zip ?? "", district: $0.district ?? "",
                              city: $0.city ?? "")
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

extension PhysicalDimension {
    init(_ d: LucentAPI.Dimension) { self.init(id: d.id, name: d.name, description: d.description ?? "") }
}

extension LabUnit {
    init(_ u: LucentAPI.Unit) { self.init(id: u.id, name: u.name, notations: u.notations, dimensionID: u.dimensionId) }
}

extension Parameter {
    init(_ p: LucentAPI.Parameter) {
        self.init(id: p.id, name: p.name, description: p.description ?? "", unitID: p.unitId,
                  valueClass: ValueClass(rawValue: p.valueClass.rawValue) ?? .text)
    }
}

extension Device {
    init(_ d: LucentAPI.Device) {
        self.init(id: d.id, name: d.name, number: d.number, manufacturerID: d.manufacturerId,
                  operatorID: d.operatorId, active: d.active, etag: d.etag)
    }
}

extension Document {
    init(_ d: LucentAPI.Document) {
        self.init(id: d.id, name: d.name, url: d.uri.flatMap(URL.init(string:)), filePath: d.filePath,
                  accepted: d.accepted, sha256: d.sha256 ?? "")
    }
}

extension LabAction {
    init(_ a: LucentAPI.Action) {
        self.init(id: a.id, name: a.name, iteration: a.iteration, active: a.active, description: a.description ?? "",
                  documentIDs: a.documentIds, deviceIDs: a.deviceIds,
                  people: a.people.map { Assignment(personID: $0.personId, role: $0.role) },
                  dependencies: a.dependencies.map {
                      Dependency(actionID: $0.actionId, kind: Dependency.Kind(rawValue: $0.dependencyClass) ?? .strict,
                                 description: $0.description ?? "")
                  })
    }
}

extension Effect {
    init(_ e: LucentAPI.Effect) {
        self.init(id: e.id, actionID: e.actionId, parameterID: e.parameterId, uncertainty: e.uncertainty,
                  uncertaintyClass: e.uncertaintyClass == "relative" ? .relative : .absolute,
                  calculation: e.calculation, uncertaintyUnitID: e.uncertaintyUnitId)
    }
}

extension Threshold {
    init(_ t: LucentAPI.Threshold) {
        self.init(id: t.id, parameterID: t.parameterId, documentID: t.documentId, lowerLimit: t.lowerLimit,
                  upperLimit: t.upperLimit, description: t.description ?? "")
    }
}

extension Coefficient {
    init(_ c: LucentAPI.Coefficient) {
        self.init(id: c.id, effectIDs: [c.effect1Id, c.effect2Id].compactMap { $0 }, description: c.description ?? "")
    }
}

extension LabCollection {
    init(_ c: LucentAPI.Collection) {
        self.init(id: c.id, name: c.name ?? "", matrixID: c.matrixId, collectionClass: c.collectionClass,
                  spotID: c.spotId, siteID: c.siteId, sampledAt: c.sampledAt ?? c.registeredAt ?? .distantPast,
                  sampledByID: c.sampledBy ?? c.registeredBy)
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
    init(_ v: LucentAPI.Value) { self.init(id: v.id, collectionID: v.collectionId, effectID: v.effectId) }
}

extension RawValue {
    init(_ r: LucentAPI.RawValue) {
        self.init(id: r.id, valueID: r.valueId, t: r.t, personID: r.personId, deviceID: r.deviceId, unitID: r.unitId,
                  reading: r.reading.map(Reading.init), accepted: r.accepted, etag: r.etag)
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
