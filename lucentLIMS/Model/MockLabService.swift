import Foundation

/// The demo data in memory. It follows the same rules as lucentAPI: the next identifier from
/// the numbering scheme, a value for every effect of the planned actions, repetitions, and
/// nobody accepts what they measured themselves.
actor MockLabService: LabService {
    private var data: LabData
    private let currentUserID: Int
    private let numbering = NumberingScheme.lucent

    init(data: LabData, userName: String) {
        self.data = data
        currentUserID = Self.snapshot(of: data, userName: userName).currentUserID
    }

    /// The snapshot without awaiting the actor, for building a store synchronously.
    nonisolated static func snapshot(of data: LabData, userName: String) -> LabSnapshot {
        let user = data.people.first { $0.linuxUser == userName } ?? data.people[0]
        return LabSnapshot(data: data, currentUserID: user.id, roles: Set(LabRole.allCases))
    }

    func load() -> LabSnapshot {
        LabSnapshot(data: data, currentUserID: currentUserID, roles: Set(LabRole.allCases))
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
}
