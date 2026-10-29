import Foundation

/// The demo data in memory. It follows the same rules as lucentAPI: the next identifier from
/// the numbering scheme, repetitions, and nobody accepts what they measured themselves.
actor MockLabService: LabService {
    private var data: LabData
    private let currentUserID: Int
    private let numbering = NumberingScheme.lucent

    init(data: LabData, userName: String) {
        self.data = data
        currentUserID = (data.people.first { $0.unixAccount == userName } ?? data.people[0]).id
    }

    /// The snapshot without awaiting the actor, for building a store synchronously.
    nonisolated static func snapshot(of data: LabData, userName: String) -> LabSnapshot {
        let user = data.people.first { $0.unixAccount == userName } ?? data.people[0]
        return LabSnapshot(data: data, currentUserID: user.id, roles: Set(LabRole.allCases))
    }

    func load() -> LabSnapshot {
        LabSnapshot(data: data, currentUserID: currentUserID, roles: Set(LabRole.allCases))
    }

    func register(_ new: NewCollection) -> LabCollection {
        let last = data.collections.compactMap { numbering.sequence(of: $0.name) }.max()
        let collection = LabCollection(
            id: (data.collections.map(\.id).max() ?? 0) + 1,
            name: numbering.identifier(for: last.map { $0 + 1 } ?? 0) ?? "¯\\_(ツ)_/¯",
            matrixID: new.matrixID, classID: new.classID, spotID: new.spotID, siteID: new.siteID,
            sampledAt: new.sampledAt, sampledByID: new.sampledByID)
        data.collections.append(collection)
        return collection
    }

    func record(_ reading: Reading, for actionVariable: ActionVariable, in collectionID: Int) -> LabValue {
        let action = data.actions.first { $0.id == actionVariable.actionID }
        let deviceID = action?.deviceIDs.first { id in data.devices.first { $0.id == id }?.active == true }
        let repetition = (data.values
            .filter { $0.collectionID == collectionID && $0.actionVariableID == actionVariable.id }
            .map(\.repetition).max() ?? 0) + 1
        let value = LabValue(id: (data.values.map(\.id).max() ?? 0) + 1, collectionID: collectionID,
                             actionVariableID: actionVariable.id, repetition: repetition, reading: reading,
                             accepted: false, measuredAt: .now, personID: currentUserID, deviceID: deviceID)
        data.values.append(value)
        return value
    }

    func setAccepted(_ accepted: Bool, value: LabValue) throws -> LabValue {
        guard let index = data.values.firstIndex(where: { $0.id == value.id }) else { return value }
        if accepted && data.values[index].personID == currentUserID { throw LabServiceError.fourEyes }
        data.values[index].accepted = accepted
        return data.values[index]
    }

    func acceptAll(in collectionID: Int) throws -> [LabValue] {
        let open = data.values.indices.filter { data.values[$0].collectionID == collectionID && !data.values[$0].accepted }
        if open.contains(where: { data.values[$0].personID == currentUserID }) { throw LabServiceError.fourEyes }
        for index in open { data.values[index].accepted = true }
        return data.values.filter { $0.collectionID == collectionID }
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
