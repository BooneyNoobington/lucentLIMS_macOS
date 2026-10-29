import Foundation

/// What a user may do, as lucentAPI's roles. `admin` may do everything.
enum LabRole: String, CaseIterable, Hashable, Sendable {
    case sampler, analyst, reviewer, admin
}

/// Everything the app shows, plus who is looking.
struct LabSnapshot: Sendable {
    var data: LabData
    var currentUserID: Int
    var roles: Set<LabRole>
}

struct NewCollection: Sendable {
    var matrixID: Int
    var classID: Int
    var spotID: Int?
    var siteID: Int?
    var sampledAt: Date
    var sampledByID: Int
}

/// Where `LabStore` gets its data and sends its changes: the demo data in memory
/// (`MockLabService`) or lucentAPI (`APILabService`). Changes return the record as it is now,
/// and the store replaces its copy with it.
protocol LabService: Sendable {
    func load() async throws -> LabSnapshot
    func register(_ collection: NewCollection) async throws -> LabCollection
    func record(_ reading: Reading, for actionVariable: ActionVariable, in collectionID: Int) async throws -> LabValue
    func setAccepted(_ accepted: Bool, value: LabValue) async throws -> LabValue
    /// Accepts all open values of a collection and returns all its values.
    func acceptAll(in collectionID: Int) async throws -> [LabValue]
    func setDone(_ done: Bool, task: LabTask) async throws -> LabTask
    func setActive(_ active: Bool, device: Device) async throws -> Device
    func setRead(_ read: Bool, message: Message) async throws -> Message
}

struct LabServiceError: LocalizedError, Sendable {
    var message: String
    var errorDescription: String? { message }

    static let fourEyes = LabServiceError(
        message: String(localized: "Values have to be accepted by someone other than who measured them."))
}
