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
    var collectionClass: String
    var spotID: Int?
    var siteID: Int?
    /// Every effect of these actions becomes one of the collection's values.
    var actionIDs: [Int]
    /// Recorded as the sampling-time raw value, if that parameter is among the planned effects.
    var sampledAt: Date?
}

/// A registered collection, with its values and raw values as they are now.
struct Registration: Sendable {
    var collection: LabCollection
    var values: [LabValue]
    var rawValues: [RawValue]
}

/// Where `LabStore` gets its data and sends its changes: the demo data in memory
/// (`MockLabService`) or lucentAPI (`APILabService`). Changes return the records as they are
/// now, and the store replaces its copies with them.
protocol LabService: Sendable {
    func load() async throws -> LabSnapshot
    func register(_ collection: NewCollection) async throws -> Registration
    func record(_ reading: Reading, for value: LabValue) async throws -> RawValue
    func setAccepted(_ accepted: Bool, rawValue: RawValue) async throws -> RawValue
    /// Accepts all open raw values of a collection and returns all its raw values.
    func acceptAll(in collectionID: Int) async throws -> [RawValue]
    func setDone(_ done: Bool, task: LabTask) async throws -> LabTask
    func setActive(_ active: Bool, device: Device) async throws -> Device
    func setRead(_ read: Bool, message: Message) async throws -> Message
}

struct LabServiceError: LocalizedError, Sendable {
    var message: String
    var errorDescription: String? { message }

    static let fourEyes = LabServiceError(
        message: String(localized: "Raw values have to be accepted by someone other than who measured them."))
    static let samplingTimeNotPlanned = LabServiceError(
        message: String(localized: "A sampling time needs an action whose effects include the sampling-time parameter."))
}
