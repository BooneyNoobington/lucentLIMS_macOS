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

/// A spot or a site being drawn on the map: a new one, or one being changed.
struct LocationDraft: Hashable, Sendable {
    enum Kind: Hashable, Sendable { case spot, site }

    var kind: Kind
    /// The spot or site being changed; nil for a new one.
    var editing: LocationRef?
    var name = ""
    var description = ""
    /// Where the spot is.
    var point: GeoPoint?
    /// The site's corners, in order.
    var border: [GeoPoint] = []
    /// The site the spot lies in.
    var siteID: Int?

    /// lucentBASE's limits: a spot's name has at most 50 characters, a site's 20.
    var nameLimit: Int { kind == .spot ? 50 : 20 }

    init(kind: Kind, name: String = "", description: String = "", point: GeoPoint? = nil, border: [GeoPoint] = [],
         siteID: Int? = nil) {
        self.kind = kind
        self.name = name
        self.description = description
        self.point = point
        self.border = border
        self.siteID = siteID
    }

    init(editing spot: Spot) {
        self.init(kind: .spot, name: spot.name, description: spot.description, point: spot.point, siteID: spot.siteID)
        editing = .spot(spot.id)
    }

    init(editing site: Site) {
        self.init(kind: .site, name: site.name, description: site.description, border: site.border)
        editing = .site(site.id)
    }

    /// A corner where it fits: at the end while drawing, into the nearest edge when changing a border.
    mutating func addCorner(_ point: GeoPoint) {
        guard editing != nil, border.count >= 3 else {
            border.append(point)
            return
        }
        // Distances on a plane, longitude scaled to the latitude so the nearest edge is the one that looks nearest.
        let scale = cos(point.latitude * .pi / 180)
        func distance(_ p: GeoPoint, _ a: GeoPoint, _ b: GeoPoint) -> Double {
            let (px, py) = (p.longitude * scale, p.latitude), (ax, ay) = (a.longitude * scale, a.latitude)
            let (bx, by) = (b.longitude * scale, b.latitude)
            let (dx, dy) = (bx - ax, by - ay)
            let t = dx == 0 && dy == 0 ? 0 : max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
            return hypot(px - (ax + t * dx), py - (ay + t * dy))
        }
        let nearest = border.indices.min { i, j in
            distance(point, border[i], border[(i + 1) % border.count])
                < distance(point, border[j], border[(j + 1) % border.count])
        }!
        border.insert(point, at: nearest + 1)
    }

    var problem: String? {
        let name = name.trimmingCharacters(in: .whitespaces)
        switch kind {
        case .spot where point == nil:
            return String(localized: "Click the map to place the spot.")
        case .site where !Border.isLargeEnough(border):
            return String(localized: "Click the map at least three times to draw the border.")
        case .site where Border.crossesItself(border):
            return String(localized: "The border crosses itself. Undo corners until it doesn't.")
        default:
            break
        }
        if name.isEmpty { return String(localized: "Give it a name.") }
        if name.count > nameLimit { return String(localized: "The name is longer than \(nameLimit) characters.") }
        if description.count > 50 { return String(localized: "The description is longer than 50 characters.") }
        return nil
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
    /// Adds a spot (sampler).
    func createSpot(_ draft: LocationDraft) async throws -> Spot
    /// Adds a site by its border (sampler).
    func createSite(_ draft: LocationDraft) async throws -> Site
    /// Changes what differs from `spot` (sampler).
    func updateSpot(_ spot: Spot, to draft: LocationDraft) async throws -> Spot
    /// Changes what differs from `site`, the border included (sampler).
    func updateSite(_ site: Site, to draft: LocationDraft) async throws -> Site
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
    static let borderCrossesItself = LabServiceError(
        message: String(localized: "The border crosses itself. Draw its corners in order."))
    static func nameTaken(_ name: String) -> LabServiceError {
        LabServiceError(message: String(localized: "There already is a location called “\(name)”."))
    }
    static let samplingTimeNotPlanned = LabServiceError(
        message: String(localized: "A sampling time needs an action whose effects include the sampling-time parameter."))
}
