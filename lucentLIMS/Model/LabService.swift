import Foundation

/// What a user may do: lucentBASE's roles. `admin` may do everything.
enum LabRole: String, CaseIterable, Comparable, Hashable, Sendable {
    case sampler, analyst, reviewer, admin

    static func < (lhs: Self, rhs: Self) -> Bool { allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)! }
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

/// A new person, or the changes to one. Roles are set on their own.
struct PersonDraft: Hashable, Sendable {
    var givenName = ""
    var surname = ""
    var linuxUser = ""
    var organizationID: Int?
    var position = ""
    var active = true

    init() {}

    init(_ person: Person) {
        givenName = person.givenName
        surname = person.surname
        linuxUser = person.linuxUser
        organizationID = person.organizationID
        position = person.position ?? ""
        active = person.active
    }
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
    /// Adds a person with roles (admin). `reason` goes into lucentBASE's log.
    func createPerson(_ draft: PersonDraft, roles: Set<LabRole>, reason: String?) async throws -> Person
    /// Changes what differs from `person` (admin).
    func updatePerson(_ person: Person, to draft: PersonDraft, reason: String?) async throws -> Person
    /// Grants and revokes so the person has exactly `roles` (admin).
    func setRoles(_ roles: Set<LabRole>, of person: Person, reason: String?) async throws -> Person
    /// Changes to the person, their roles and their organization, newest first.
    func history(of person: Person) async throws -> [HistoryEntry]
}

struct LabServiceError: LocalizedError, Sendable {
    var message: String
    var errorDescription: String? { message }

    static let fourEyes = LabServiceError(
        message: String(localized: "Raw values have to be accepted by someone other than who measured them."))
    static let lastAdmin = LabServiceError(
        message: String(localized: "This is the last active admin. Make someone else admin first."))
    static let deactivateYourself = LabServiceError(message: String(localized: "Nobody can deactivate themselves."))
    static func linuxUserTaken(_ name: String) -> LabServiceError {
        LabServiceError(message: String(localized: "Another person already signs in as “\(name)”."))
    }
    static let samplingTimeNotPlanned = LabServiceError(
        message: String(localized: "A sampling time needs an action whose effects include the sampling-time parameter."))
}
