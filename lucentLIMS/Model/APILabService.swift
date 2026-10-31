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
        async let roles = client.roles()

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
            samplingTimeParameterID: loadedConfiguration.samplingTimeParameterId,
            roleDescriptions: Dictionary(try await roles.compactMap { info in
                LabRole(rawValue: info.name.rawValue).map { ($0, info.description ?? "") }
            }, uniquingKeysWith: { first, _ in first }))
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

    func createPerson(_ draft: PersonDraft, roles: Set<LabRole>, reason: String?) async throws -> Person {
        Person(try await client.createPerson(.init(
            givenName: draft.givenName, surname: draft.surname, linuxUser: draft.linuxUser.isEmpty ? nil : draft.linuxUser,
            organizationId: draft.organizationID, position: draft.position.isEmpty ? nil : draft.position,
            roles: roles.sorted().map(LucentAPI.Role.init), note: reason)))
    }

    /// Sends only what differs from `person`. lucentAPI can't remove a Linux user, only change it.
    func updatePerson(_ person: Person, to draft: PersonDraft, reason: String?) async throws -> Person {
        let before = PersonDraft(person)
        func changed<T: Equatable>(_ path: KeyPath<PersonDraft, T>) -> T? {
            draft[keyPath: path] == before[keyPath: path] ? nil : draft[keyPath: path]
        }
        let change = LucentAPI.PersonChange(
            givenName: changed(\.givenName), surname: changed(\.surname),
            linuxUser: changed(\.linuxUser).flatMap { $0.isEmpty ? nil : $0 },
            organizationId: changed(\.organizationID) ?? nil, position: changed(\.position), active: changed(\.active),
            note: reason)
        return Person(try await client.updatePerson(id: person.id, etag: person.etag ?? "*", change))
    }

    func setRoles(_ roles: Set<LabRole>, of person: Person, reason: String?) async throws -> Person {
        Person(try await client.setRoles(roles.sorted().map(LucentAPI.Role.init), of: person.id,
                                         etag: person.etag ?? "*", note: reason))
    }

    func history(of person: Person) async throws -> [HistoryEntry] {
        try await client.history(ofPerson: person.id).enumerated().map { index, entry in
            HistoryEntry(id: index, t: entry.t, editorID: entry.editorId, created: entry.modification == .created,
                         subject: HistoryEntry.Subject(entry), note: entry.note ?? "")
        }
    }

    func createSpot(_ draft: LocationDraft) async throws -> Spot {
        guard let point = draft.point else { throw LabServiceError(message: draft.problem ?? "") }
        return Spot(try await client.createSpot(.init(
            name: draft.name.trimmingCharacters(in: .whitespaces),
            description: draft.description.isEmpty ? nil : draft.description,
            x: point.latitude, y: point.longitude, siteId: draft.siteID)))
    }

    func createSite(_ draft: LocationDraft) async throws -> Site {
        Site(try await client.createSite(.init(
            name: draft.name.trimmingCharacters(in: .whitespaces),
            description: draft.description.isEmpty ? nil : draft.description,
            border: draft.border.map { LucentAPI.GeoPoint(latitude: $0.latitude, longitude: $0.longitude) })))
    }

    /// Sends only what differs from `spot`.
    func updateSpot(_ spot: Spot, to draft: LocationDraft) async throws -> Spot {
        let name = draft.name.trimmingCharacters(in: .whitespaces)
        let moved = draft.point != spot.point
        let change = LucentAPI.SpotChange(
            name: name == spot.name ? nil : name,
            description: draft.description == spot.description ? nil : draft.description,
            x: moved ? draft.point?.latitude : nil, y: moved ? draft.point?.longitude : nil,
            siteId: draft.siteID == spot.siteID ? nil : .some(draft.siteID))
        return Spot(try await client.updateSpot(id: spot.id, etag: spot.etag ?? "*", change))
    }

    /// Sends only what differs from `site`; a changed border is sent whole.
    func updateSite(_ site: Site, to draft: LocationDraft) async throws -> Site {
        let name = draft.name.trimmingCharacters(in: .whitespaces)
        let change = LucentAPI.SiteChange(
            name: name == site.name ? nil : name,
            description: draft.description == site.description ? nil : draft.description,
            border: draft.border == site.border ? nil
                : draft.border.map { LucentAPI.GeoPoint(latitude: $0.latitude, longitude: $0.longitude) })
        return Site(try await client.updateSite(id: site.id, etag: site.etag ?? "*", change))
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
                  organizationID: p.organizationId, position: p.position, active: p.active,
                  roles: Set(p.roles.compactMap { LabRole(rawValue: $0.rawValue) }), etag: p.etag)
    }
}

extension HistoryEntry.Subject {
    init(_ entry: LucentAPI.HistoryEntry) {
        switch entry.subject {
        case .person: self = .person
        case .organization: self = .organization
        case .role: self = .role(entry.role.flatMap { LabRole(rawValue: $0.rawValue) })
        }
    }
}

extension LucentAPI.Role {
    init(_ role: LabRole) { self = LucentAPI.Role(rawValue: role.rawValue)! }
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
                  crsID: s.crsId, etag: s.etag)
    }
}

extension Spot {
    init(_ s: LucentAPI.Spot) {
        self.init(id: s.id, name: s.name, description: s.description ?? "", x: s.x, y: s.y, crsID: s.crsId,
                  siteID: s.siteId, etag: s.etag)
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
