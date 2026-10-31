import Foundation

/// The demo data in memory. It follows the same rules as lucentAPI: the next identifier from
/// the numbering scheme, a value for every effect of the planned actions, repetitions, nobody
/// accepts what they measured themselves, nobody deactivates themselves, and the last admin
/// stays admin. People changes are logged with notes like lucentAPI writes them.
actor MockLabService: LabService {
    private var data: LabData
    private let currentUserID: Int
    private let numbering = NumberingScheme.lucent
    /// lucentBASE's log of people, their roles and organizations.
    private var log: [(personID: Int, entry: HistoryEntry)]

    init(data: LabData, userName: String) {
        self.data = data
        currentUserID = Self.snapshot(of: data, userName: userName).currentUserID
        // Everyone was entered by the system user before the first collection.
        let entered = (data.collections.map(\.sampledAt).min() ?? .now).addingTimeInterval(-30 * 86_400)
        var log: [(personID: Int, entry: HistoryEntry)] = []
        for person in data.people {
            let subjects = [HistoryEntry.Subject.person, .organization] + person.roles.sorted().map { .role($0) }
            for subject in subjects {
                log.append((person.id, HistoryEntry(id: log.count + 1, t: entered, editorID: MockData.system,
                                                    created: true, subject: subject, note: "Demo data")))
            }
        }
        self.log = log
    }

    /// The snapshot without awaiting the actor, for building a store synchronously.
    nonisolated static func snapshot(of data: LabData, userName: String) -> LabSnapshot {
        let user = data.people.first { $0.linuxUser == userName } ?? data.people[0]
        return LabSnapshot(data: data, currentUserID: user.id, roles: user.roles)
    }

    func load() -> LabSnapshot {
        let user = data.people.first { $0.id == currentUserID }
        return LabSnapshot(data: data, currentUserID: currentUserID, roles: user?.roles ?? [])
    }

    func register(_ new: NewCollection) throws -> Registration {
        let last = data.collections.compactMap { numbering.sequence(of: $0.name) }.max()
        let collection = LabCollection(
            id: (data.collections.map(\.id).max() ?? 0) + 1,
            name: numbering.identifier(for: last.map { $0 + 1 } ?? 0) ?? "¯\\_(ツ)_/¯",
            matrixID: new.matrixID, collectionClass: new.collectionClass, spotID: new.spotID, siteID: new.siteID,
            sampledAt: new.sampledAt ?? .now, sampledByID: currentUserID)
        var values: [LabValue] = []
        for effect in data.effects where new.actionIDs.contains(effect.actionID) {
            values.append(LabValue(id: (data.values.map(\.id).max() ?? 0) + values.count + 1,
                                   collectionID: collection.id, effectID: effect.id))
        }
        var rawValues: [RawValue] = []
        if let sampledAt = new.sampledAt {
            guard let slot = values.first(where: { value in
                data.effects.first { $0.id == value.effectID }?.parameterID == data.samplingTimeParameterID
            }) else { throw LabServiceError.samplingTimeNotPlanned }
            rawValues.append(RawValue(id: (data.rawValues.map(\.id).max() ?? 0) + 1, valueID: slot.id, t: sampledAt,
                                      personID: currentUserID, reading: .datetime(sampledAt), accepted: false))
        }
        data.collections.append(collection)
        data.values += values
        data.rawValues += rawValues
        return Registration(collection: collection, values: values, rawValues: rawValues)
    }

    func record(_ reading: Reading, for value: LabValue) -> RawValue {
        let effect = data.effects.first { $0.id == value.effectID }
        let action = data.actions.first { $0.id == effect?.actionID }
        let parameter = data.parameters.first { $0.id == effect?.parameterID }
        let raw = RawValue(
            id: (data.rawValues.map(\.id).max() ?? 0) + 1, valueID: value.id, t: .now, personID: currentUserID,
            deviceID: action?.deviceIDs.first { id in data.devices.first { $0.id == id }?.active == true },
            unitID: parameter?.unitID, reading: reading, accepted: false)
        data.rawValues.append(raw)
        return raw
    }

    func setAccepted(_ accepted: Bool, rawValue: RawValue) throws -> RawValue {
        guard let index = data.rawValues.firstIndex(where: { $0.id == rawValue.id }) else { return rawValue }
        if accepted && data.rawValues[index].personID == currentUserID { throw LabServiceError.fourEyes }
        data.rawValues[index].accepted = accepted
        return data.rawValues[index]
    }

    func acceptAll(in collectionID: Int) throws -> [RawValue] {
        let valueIDs = Set(data.values.filter { $0.collectionID == collectionID }.map(\.id))
        let open = data.rawValues.indices.filter { valueIDs.contains(data.rawValues[$0].valueID) && !data.rawValues[$0].accepted }
        if open.contains(where: { data.rawValues[$0].personID == currentUserID }) { throw LabServiceError.fourEyes }
        for index in open { data.rawValues[index].accepted = true }
        return data.rawValues.filter { valueIDs.contains($0.valueID) }
    }

    func setDone(_ done: Bool, task: LabTask) -> LabTask {
        guard let index = data.tasks.firstIndex(where: { $0.id == task.id }) else { return task }
        data.tasks[index].done = done
        return data.tasks[index]
    }

    func setActive(_ active: Bool, device: Device) -> Device {
        guard let index = data.devices.firstIndex(where: { $0.id == device.id }) else { return device }
        data.devices[index].active = active
        return data.devices[index]
    }

    func setRead(_ read: Bool, message: Message) -> Message {
        guard let index = data.messages.firstIndex(where: { $0.id == message.id }) else { return message }
        data.messages[index].read = read
        return data.messages[index]
    }

    // MARK: Locations

    func createSpot(_ draft: LocationDraft) throws -> Spot {
        guard let point = draft.point else { throw LabServiceError(message: draft.problem ?? "") }
        let name = draft.name.trimmingCharacters(in: .whitespaces)
        if data.spots.contains(where: { $0.name == name }) { throw LabServiceError.nameTaken(name) }
        let spot = Spot(id: (data.spots.map(\.id).max() ?? 0) + 1, name: name, description: draft.description,
                        x: point.latitude, y: point.longitude, crsID: data.crs.first { $0.epsg == 4326 }?.id,
                        siteID: draft.siteID)
        data.spots.append(spot)
        return spot
    }

    func createSite(_ draft: LocationDraft) throws -> Site {
        if Border.crossesItself(draft.border) { throw LabServiceError.borderCrossesItself }
        if let problem = draft.problem { throw LabServiceError(message: problem) }
        let name = draft.name.trimmingCharacters(in: .whitespaces)
        if data.sites.contains(where: { $0.name == name }) { throw LabServiceError.nameTaken(name) }
        let site = Site(id: (data.sites.map(\.id).max() ?? 0) + 1, name: name, description: draft.description,
                        border: draft.border, crsID: data.crs.first { $0.epsg == 4326 }?.id)
        data.sites.append(site)
        return site
    }

    func updateSpot(_ spot: Spot, to draft: LocationDraft) throws -> Spot {
        guard let index = data.spots.firstIndex(where: { $0.id == spot.id }), let point = draft.point else { return spot }
        let name = draft.name.trimmingCharacters(in: .whitespaces)
        if data.spots.contains(where: { $0.name == name && $0.id != spot.id }) { throw LabServiceError.nameTaken(name) }
        data.spots[index].name = name
        data.spots[index].description = draft.description
        data.spots[index].x = point.latitude
        data.spots[index].y = point.longitude
        data.spots[index].siteID = draft.siteID
        return data.spots[index]
    }

    func updateSite(_ site: Site, to draft: LocationDraft) throws -> Site {
        guard let index = data.sites.firstIndex(where: { $0.id == site.id }) else { return site }
        if Border.crossesItself(draft.border) { throw LabServiceError.borderCrossesItself }
        if let problem = draft.problem { throw LabServiceError(message: problem) }
        let name = draft.name.trimmingCharacters(in: .whitespaces)
        if data.sites.contains(where: { $0.name == name && $0.id != site.id }) { throw LabServiceError.nameTaken(name) }
        data.sites[index].name = name
        data.sites[index].description = draft.description
        data.sites[index].border = draft.border
        return data.sites[index]
    }

    // MARK: People

    func createPerson(_ draft: PersonDraft, roles: Set<LabRole>, reason: String?) throws -> Person {
        try requireFree(draft.linuxUser)
        let person = Person(
            id: (data.people.map(\.id).max() ?? 0) + 1, givenName: draft.givenName, surname: draft.surname,
            linuxUser: draft.linuxUser, organizationID: draft.organizationID,
            position: draft.position.isEmpty ? nil : draft.position, roles: roles)
        data.people.append(person)
        record(person.id, .person, created: true, note("Created", reason))
        if person.organizationID != nil { record(person.id, .organization, created: true, note("Joined the organization", reason)) }
        for role in roles.sorted() { record(person.id, .role(role), created: true, note("Granted \(role.rawValue)", reason)) }
        return person
    }

    func updatePerson(_ person: Person, to draft: PersonDraft, reason: String?) throws -> Person {
        guard let index = data.people.firstIndex(where: { $0.id == person.id }) else { return person }
        var current = data.people[index]
        if draft.linuxUser != current.linuxUser { try requireFree(draft.linuxUser, except: person.id) }
        if !draft.active && current.active {
            if person.id == currentUserID { throw LabServiceError.deactivateYourself }
            if activeAdmins == [person.id] { throw LabServiceError.lastAdmin }
        }
        var said: [String] = []
        if draft.givenName != current.givenName { said.append("given name") }
        if draft.surname != current.surname { said.append("surname") }
        if draft.linuxUser != current.linuxUser { said.append("Linux user") }
        if draft.organizationID != current.organizationID { said.append("organization") }
        var what: [String] = draft.active == current.active ? [] : [draft.active ? "Reactivated" : "Deactivated"]
        if !said.isEmpty { what.append("Changed " + said.joined(separator: ", ")) }
        if !what.isEmpty { record(person.id, .person, created: false, note(what.joined(separator: "; "), reason)) }
        let position = draft.position.isEmpty ? nil : draft.position
        if position != current.position || draft.organizationID != current.organizationID {
            record(person.id, .organization, created: false, note("Changed position", reason))
        }
        current.givenName = draft.givenName
        current.surname = draft.surname
        current.linuxUser = draft.linuxUser
        current.organizationID = draft.organizationID
        current.position = position
        current.active = draft.active
        data.people[index] = current
        return current
    }

    func setRoles(_ roles: Set<LabRole>, of person: Person, reason: String?) throws -> Person {
        guard let index = data.people.firstIndex(where: { $0.id == person.id }) else { return person }
        let current = data.people[index].roles
        if current.contains(.admin) && !roles.contains(.admin) && activeAdmins == [person.id] {
            throw LabServiceError.lastAdmin
        }
        for role in LabRole.allCases where roles.contains(role) != current.contains(role) {
            let what = roles.contains(role) ? "Granted \(role.rawValue)" : "Revoked \(role.rawValue)"
            record(person.id, .role(role), created: false, note(what, reason))
        }
        data.people[index].roles = roles
        return data.people[index]
    }

    func history(of person: Person) -> [HistoryEntry] {
        log.filter { $0.personID == person.id }.map(\.entry)
            .sorted { ($0.t ?? .distantPast, $0.id) > ($1.t ?? .distantPast, $1.id) }
    }

    private var activeAdmins: Set<Int> {
        Set(data.people.filter { $0.active && $0.roles.contains(.admin) }.map(\.id))
    }

    private func requireFree(_ linuxUser: String, except id: Int? = nil) throws {
        guard !linuxUser.isEmpty else { return }
        if data.people.contains(where: { $0.linuxUser == linuxUser && $0.id != id }) {
            throw LabServiceError.linuxUserTaken(linuxUser)
        }
    }

    private func note(_ what: String, _ reason: String?) -> String {
        guard let reason, !reason.isEmpty else { return what }
        return "\(what): \(reason)"
    }

    private func record(_ personID: Int, _ subject: HistoryEntry.Subject, created: Bool, _ note: String) {
        log.append((personID, HistoryEntry(id: log.count + 1, t: .now, editorID: currentUserID, created: created,
                                           subject: subject, note: note)))
    }
}
