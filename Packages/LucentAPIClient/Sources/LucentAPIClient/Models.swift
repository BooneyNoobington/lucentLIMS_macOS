import Foundation

/// The types of lucentAPI, as described in its `openapi.json`. They follow lucentBASE. Property
/// names are the JSON names in camel case (`matrix_id` becomes `matrixId`).
public enum LucentAPI {}

// MARK: - People

extension LucentAPI {
    public enum Role: String, Codable, Hashable, Sendable, CaseIterable {
        case sampler, analyst, reviewer, admin
    }

    public struct Organization: Codable, Hashable, Sendable {
        public var id: Int
        public var name: String?
        public var shorthand: String?
        public var relation: String?
    }

    public struct Person: Codable, Hashable, Sendable {
        public var id: Int
        public var givenName: String
        public var surname: String
        /// The account the person signs in with: the token's username.
        public var linuxUser: String?
        public var organizationId: Int?
        /// In their organization, from j_person_organization.
        public var position: String?
        /// Whether the person can sign in. Inactive people stay in the history.
        public var active: Bool
        /// What the person may do, from lucentBASE's j_person_role.
        public var roles: [Role]
        /// Send it as `If-Match` when changing the person or their roles.
        public var etag: String
    }

    /// The person behind the token and their roles.
    public struct Me: Codable, Hashable, Sendable {
        public var person: Person
        public var roles: [Role]
    }

    public struct RoleInfo: Codable, Hashable, Sendable {
        public var name: Role
        public var description: String?
    }

    public struct NewPerson: Encodable, Sendable {
        public var givenName: String
        public var surname: String
        /// Must be unique.
        public var linuxUser: String?
        public var organizationId: Int?
        /// Needs an organization.
        public var position: String?
        public var roles: [Role]
        public var note: String?

        public init(givenName: String, surname: String, linuxUser: String? = nil, organizationId: Int? = nil,
                    position: String? = nil, roles: [Role] = [], note: String? = nil) {
            self.givenName = givenName
            self.surname = surname
            self.linuxUser = linuxUser
            self.organizationId = organizationId
            self.position = position
            self.roles = roles
            self.note = note
        }
    }

    /// Fields left `nil` stay as they are.
    public struct PersonChange: Encodable, Sendable {
        public var givenName: String?
        public var surname: String?
        public var linuxUser: String?
        public var organizationId: Int?
        public var position: String?
        public var active: Bool?
        public var note: String?

        public init(givenName: String? = nil, surname: String? = nil, linuxUser: String? = nil,
                    organizationId: Int? = nil, position: String? = nil, active: Bool? = nil, note: String? = nil) {
            self.givenName = givenName
            self.surname = surname
            self.linuxUser = linuxUser
            self.organizationId = organizationId
            self.position = position
            self.active = active
            self.note = note
        }
    }

    /// A change to a person, one of their roles or their organization, from lucentBASE's log.
    public struct HistoryEntry: Codable, Hashable, Sendable {
        public enum Modification: String, Codable, Hashable, Sendable { case created, changed }
        public enum Subject: String, Codable, Hashable, Sendable { case person, role, organization }

        public var t: Date?
        public var editorId: Int?
        public var modification: Modification
        public var subject: Subject
        public var role: Role?
        /// What changed and why, as the API wrote it.
        public var note: String?
    }

    /// What clients need to know about this lucentBASE.
    public struct Configuration: Codable, Hashable, Sendable {
        /// The parameter whose datetime raw value is a collection's sampling time.
        public var samplingTimeParameterId: Int?
        public var collectionClasses: [String]
    }
}

// MARK: - Locations

extension LucentAPI {
    public struct GeoPoint: Codable, Hashable, Sendable {
        public var latitude: Double
        public var longitude: Double

        public init(latitude: Double, longitude: Double) {
            self.latitude = latitude
            self.longitude = longitude
        }
    }

    public struct Address: Codable, Hashable, Sendable {
        public var street: String?
        public var houseNumber: Int?
        public var addition: String?
        public var zip: String?
        public var district: String?
        public var city: String?
    }

    public struct ReferenceSystem: Codable, Hashable, Sendable {
        public var id: Int
        public var epsg: Int
        public var name: String
        public var description: String?
    }

    public struct Site: Codable, Hashable, Sendable {
        public var id: Int
        public var name: String
        public var description: String?
        public var address: Address?
        public var border: [GeoPoint]
        public var crsId: Int?
    }

    /// As in lucentBASE, `x` is the latitude and `y` the longitude.
    public struct Spot: Codable, Hashable, Sendable {
        public var id: Int
        public var name: String
        public var description: String?
        public var x: Double?
        public var y: Double?
        public var z: Double?
        public var crsId: Int?
        public var siteId: Int?
    }

    /// A new point where samples are taken. As in lucentBASE, `x` is the latitude and `y` the longitude.
    public struct NewSpot: Encodable, Sendable {
        /// Unique among spots, at most 50 characters.
        public var name: String
        public var description: String?
        public var x: Double
        public var y: Double
        /// The site the spot lies in, if any.
        public var siteId: Int?
        /// Defaults to WGS 84.
        public var crsId: Int?
        public var note: String?

        public init(name: String, description: String? = nil, x: Double, y: Double, siteId: Int? = nil,
                    crsId: Int? = nil, note: String? = nil) {
            self.name = name
            self.description = description
            self.x = x
            self.y = y
            self.siteId = siteId
            self.crsId = crsId
            self.note = note
        }
    }

    /// A new area. Its border's corners come in order, without repeating the first, and must not
    /// cross each other.
    public struct NewSite: Encodable, Sendable {
        /// Unique among sites, at most 20 characters.
        public var name: String
        public var description: String?
        public var border: [GeoPoint]
        /// Defaults to WGS 84.
        public var crsId: Int?
        public var note: String?

        public init(name: String, description: String? = nil, border: [GeoPoint], crsId: Int? = nil,
                    note: String? = nil) {
            self.name = name
            self.description = description
            self.border = border
            self.crsId = crsId
            self.note = note
        }
    }
}

// MARK: - Catalog

extension LucentAPI {
    public struct Matrix: Codable, Hashable, Sendable {
        public var id: Int
        public var name: String
        public var description: String?
    }

    public struct Dimension: Codable, Hashable, Sendable {
        public var id: Int
        public var name: String
        public var description: String?
    }

    public struct Unit: Codable, Hashable, Sendable {
        public var id: Int
        public var name: String
        public var description: String?
        public var notations: [String]
        public var dimensionId: Int?
    }

    public enum ValueClass: String, Codable, Hashable, Sendable {
        case decimal, text, boolean, datetime
    }

    public struct Parameter: Codable, Hashable, Sendable {
        public var id: Int
        public var name: String
        public var description: String?
        public var unitId: Int?
        public var valueClass: ValueClass
    }

    public struct Device: Codable, Hashable, Sendable {
        public var id: Int
        public var name: String
        public var number: Int
        /// An organization.
        public var manufacturerId: Int?
        /// An organization, as in lucentBASE.
        public var operatorId: Int?
        public var active: Bool
        /// Send it as `If-Match` when changing the device.
        public var etag: String
    }

    /// A link: an SOP, a standard, a regulation, any file or web page.
    public struct Document: Codable, Hashable, Sendable {
        public var id: Int
        public var name: String
        public var uri: String?
        public var filePath: String?
        public var accepted: Bool
        public var sha256: String?
        /// Actions that refer to it.
        public var actionIds: [Int]
    }

    /// What an action yields: one parameter, with method-specific uncertainty.
    public struct Effect: Codable, Hashable, Sendable {
        public var id: Int
        public var actionId: Int
        public var parameterId: Int
        public var uncertainty: Double?
        public var uncertaintyClass: String?
        public var uncertaintyUnitId: Int?
        public var calculation: String?
    }

    public struct ActionPerson: Codable, Hashable, Sendable {
        public var personId: Int
        /// auditor, manager or worker.
        public var role: String
    }

    /// The action depends on `actionId`: strictly, or as a possibility.
    public struct Dependency: Codable, Hashable, Sendable {
        public var actionId: Int
        public var dependencyClass: String
        public var description: String?
    }

    public struct Action: Codable, Hashable, Sendable {
        public var id: Int
        public var name: String
        /// The version of the action, as a point in time.
        public var iteration: Date
        public var active: Bool
        public var description: String?
        public var documentIds: [Int]
        public var deviceIds: [Int]
        public var people: [ActionPerson]
        public var dependencies: [Dependency]
        public var effects: [Effect]
    }

    /// Two effects that belong together.
    public struct Coefficient: Codable, Hashable, Sendable {
        public var id: Int
        public var effect1Id: Int?
        public var effect2Id: Int?
        public var description: String?
    }

    /// Limits of a parameter in the context of a document, in the parameter's unit.
    public struct Threshold: Codable, Hashable, Sendable {
        public var id: Int
        public var parameterId: Int
        public var documentId: Int
        public var lowerLimit: Double?
        public var upperLimit: Double?
        public var description: String?
    }
}

// MARK: - Collections, values, raw values

extension LucentAPI {
    /// What a raw value holds: exactly one of four kinds, matching the parameter's value class.
    public enum Reading: Codable, Hashable, Sendable {
        case decimal(Double)
        case text(String)
        case boolean(Bool)
        case datetime(Date)

        enum CodingKeys: String, CodingKey { case decimal, text, boolean, datetime }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let value = try container.decodeIfPresent(Double.self, forKey: .decimal) {
                self = .decimal(value)
            } else if let value = try container.decodeIfPresent(String.self, forKey: .text) {
                self = .text(value)
            } else if let value = try container.decodeIfPresent(Bool.self, forKey: .boolean) {
                self = .boolean(value)
            } else if let value = try container.decodeIfPresent(Date.self, forKey: .datetime) {
                self = .datetime(value)
            } else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                        debugDescription: "A reading needs one of its four fields."))
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .decimal(let value): try container.encode(value, forKey: .decimal)
            case .text(let value): try container.encode(value, forKey: .text)
            case .boolean(let value): try container.encode(value, forKey: .boolean)
            case .datetime(let value): try container.encode(value, forKey: .datetime)
            }
        }
    }

    public struct Limit: Codable, Hashable, Sendable {
        public var thresholdId: Int
        public var documentId: Int
        public var lowerLimit: Double?
        public var upperLimit: Double?
    }

    /// A reading of a value.
    public struct RawValue: Codable, Hashable, Sendable {
        public var id: Int
        public var valueId: Int
        public var t: Date?
        /// Who measured it.
        public var personId: Int?
        public var deviceId: Int?
        public var unitId: Int?
        /// `nil` if the raw value holds nothing.
        public var reading: Reading?
        public var accepted: Bool
        /// Outside one of the limits that apply.
        public var exceeds: Bool
        /// Send it as `If-Match` when accepting or withdrawing.
        public var etag: String
    }

    /// A collection's slot for one effect, with its readings, oldest first.
    public struct Value: Codable, Hashable, Sendable {
        public var id: Int
        public var collectionId: Int
        public var effectId: Int
        public var name: String?
        /// The thresholds of the parameter in the documents of the effect's action.
        public var limits: [Limit]
        public var rawValues: [RawValue]
    }

    public enum Status: String, Codable, Hashable, Sendable {
        case registered
        case inAnalysis = "in_analysis"
        case inReview = "in_review"
        case approved
    }

    public struct Collection: Codable, Hashable, Sendable {
        public var id: Int
        public var name: String?
        public var matrixId: Int
        public var collectionClass: String
        public var spotId: Int?
        public var siteId: Int?
        public var registeredAt: Date?
        public var registeredBy: Int?
        /// The sampling-time raw value, else the registration time.
        public var sampledAt: Date?
        public var sampledBy: Int?
        public var status: Status
        /// Values planned for the collection.
        public var planned: Int
        /// Values with at least one raw value.
        public var measured: Int
        public var exceedances: Int
    }

    /// A collection with its values and their raw values.
    public struct CollectionDetail: Codable, Hashable, Sendable {
        public var collection: Collection
        public var values: [Value]

        enum CodingKeys: String, CodingKey { case values }

        public init(from decoder: Decoder) throws {
            collection = try Collection(from: decoder)
            values = try decoder.container(keyedBy: CodingKeys.self).decode([Value].self, forKey: .values)
        }

        public func encode(to encoder: Encoder) throws {
            try collection.encode(to: encoder)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(values, forKey: .values)
        }
    }

    public struct Page<Item: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
        public var items: [Item]
        public var total: Int
        public var limit: Int
        public var offset: Int
    }

    public struct SeriesPoint: Codable, Hashable, Sendable {
        public var rawValueId: Int
        public var valueId: Int
        public var collectionId: Int
        public var sampledAt: Date?
        public var value: Double
        public var exceeds: Bool
    }

    public struct NewCollection: Encodable, Sendable {
        public var matrixId: Int
        public var collectionClass: String
        public var spotId: Int?
        public var siteId: Int?
        /// Plan every effect of these actions as a value.
        public var actionIds: [Int]
        /// Recorded as the sampling-time raw value; needs that parameter planned.
        public var sampledAt: Date?
        public var note: String?

        public init(matrixId: Int, collectionClass: String, spotId: Int? = nil, siteId: Int? = nil,
                    actionIds: [Int] = [], sampledAt: Date? = nil, note: String? = nil) {
            self.matrixId = matrixId
            self.collectionClass = collectionClass
            self.spotId = spotId
            self.siteId = siteId
            self.actionIds = actionIds
            self.sampledAt = sampledAt
            self.note = note
        }
    }

    public struct NewRawValue: Encodable, Sendable {
        public var reading: Reading
        /// When it was measured; defaults to now.
        public var t: Date?
        /// Defaults to the first active device of the action.
        public var deviceId: Int?
        /// Defaults to the parameter's unit.
        public var unitId: Int?
        public var note: String?

        public init(reading: Reading, t: Date? = nil, deviceId: Int? = nil, unitId: Int? = nil, note: String? = nil) {
            self.reading = reading
            self.t = t
            self.deviceId = deviceId
            self.unitId = unitId
            self.note = note
        }
    }
}

// MARK: - Management

extension LucentAPI {
    public struct Task: Codable, Hashable, Sendable {
        public var id: Int
        public var request: String
        public var description: String?
        public var assignerId: Int
        public var assigneeId: Int
        public var deadline: Date?
        public var done: Bool
        /// Send it as `If-Match` when changing the task.
        public var etag: String
    }

    public struct NewTask: Encodable, Sendable {
        public var request: String
        public var description: String?
        public var assigneeId: Int
        public var deadline: Date?
        public var note: String?

        public init(request: String, description: String? = nil, assigneeId: Int, deadline: Date? = nil,
                    note: String? = nil) {
            self.request = request
            self.description = description
            self.assigneeId = assigneeId
            self.deadline = deadline
            self.note = note
        }
    }

    /// Fields left `nil` stay as they are.
    public struct TaskChange: Encodable, Sendable {
        public var done: Bool?
        public var deadline: Date?
        public var assigneeId: Int?
        public var note: String?

        public init(done: Bool? = nil, deadline: Date? = nil, assigneeId: Int? = nil, note: String? = nil) {
            self.done = done
            self.deadline = deadline
            self.assigneeId = assigneeId
            self.note = note
        }
    }

    public struct Message: Codable, Hashable, Sendable {
        public var id: Int
        public var senderId: Int
        public var receiverId: Int
        public var subject: String
        public var body: String
        public var read: Bool
        /// From lucentBASE's log.
        public var sentAt: Date?
    }

    public struct NewMessage: Encodable, Sendable {
        public var receiverId: Int
        public var subject: String
        public var body: String

        public init(receiverId: Int, subject: String, body: String) {
            self.receiverId = receiverId
            self.subject = subject
            self.body = body
        }
    }

    public struct Health: Codable, Hashable, Sendable {
        public var status: String
        public var version: String
    }
}
