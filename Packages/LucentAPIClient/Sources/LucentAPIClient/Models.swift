import Foundation

/// The types of lucentAPI, as described in its `openapi.json`. Property names are the JSON
/// names in camel case (`matrix_id` becomes `matrixId`).
public enum LucentAPI {}

// MARK: - People

extension LucentAPI {
    public enum Role: String, Codable, Hashable, Sendable, CaseIterable {
        case sampler, analyst, reviewer, admin
    }

    public struct Organization: Codable, Hashable, Sendable {
        public var id: Int
        public var name: String
        public var shorthand: String?
    }

    public struct Person: Codable, Hashable, Sendable {
        public var id: Int
        public var givenName: String?
        public var surname: String
        public var unixAccount: String?
        public var organizationId: Int?
        public var position: String?
    }

    /// The person behind the token and the roles it grants.
    public struct Me: Codable, Hashable, Sendable {
        public var person: Person
        public var roles: [Role]
    }
}

// MARK: - Locations

extension LucentAPI {
    public struct GeoPoint: Codable, Hashable, Sendable {
        public var latitude: Double
        public var longitude: Double
    }

    public struct Address: Codable, Hashable, Sendable {
        public var street: String?
        public var houseNumber: String?
        public var addition: String?
        public var zip: String?
        public var district: String?
        public var city: String?
    }

    public struct ReferenceSystem: Codable, Hashable, Sendable {
        public var id: Int
        public var epsg: Int?
        public var name: String
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
        public var crsId: Int?
        public var siteId: Int?
    }
}

// MARK: - Catalog

extension LucentAPI {
    public struct Matrix: Codable, Hashable, Sendable {
        public var id: Int
        public var name: String
        public var description: String?
    }

    public struct CollectionClass: Codable, Hashable, Sendable {
        public var id: Int
        public var name: String
        public var description: String?
        /// The actions this class plans.
        public var actionIds: [Int]
    }

    public struct Dimension: Codable, Hashable, Sendable {
        public var id: Int
        public var name: String
        public var description: String?
    }

    public struct Unit: Codable, Hashable, Sendable {
        public var id: Int
        public var name: String
        public var notations: [String]
        public var dimensionId: Int?
    }

    public enum ValueClass: String, Codable, Hashable, Sendable {
        case decimal, text, boolean, datetime
    }

    public struct Variable: Codable, Hashable, Sendable {
        public var id: Int
        public var name: String
        public var valueClass: ValueClass
        public var description: String?
        public var dimensionId: Int?
    }

    public struct Device: Codable, Hashable, Sendable {
        public var id: Int
        public var name: String
        public var number: String?
        public var manufacturerId: Int?
        public var operatorId: Int?
        public var active: Bool
        /// Send it as `If-Match` when changing the device.
        public var etag: String
    }

    public struct Assignment: Codable, Hashable, Sendable {
        public var personId: Int
        public var role: String?
    }

    public struct SOPDocument: Codable, Hashable, Sendable {
        public var id: Int
        public var name: String
        public var url: String?
        public var filePath: String?
        public var accepted: Bool
        public var sha256: String?
    }

    public struct SOP: Codable, Hashable, Sendable {
        public var id: Int
        public var name: String
        public var active: Bool
        public var documents: [SOPDocument]
        public var people: [Assignment]
    }

    /// A variable an action measures, with unit, uncertainty and limits.
    public struct ActionVariable: Codable, Hashable, Sendable {
        public var id: Int
        public var actionId: Int
        public var variableId: Int
        public var unitId: Int?
        public var uncertainty: Double?
        public var uncertaintyClass: String?
        public var uncertaintyUnitId: Int?
        public var calculation: String?
        public var decimals: Int?
        public var lowerLimit: Double?
        public var upperLimit: Double?
    }

    /// A method.
    public struct Action: Codable, Hashable, Sendable {
        public var id: Int
        public var name: String
        public var standard: String?
        public var iteration: Int?
        public var active: Bool
        public var description: String?
        public var sopId: Int?
        public var deviceIds: [Int]
        public var people: [Assignment]
        public var dependsOn: [Int]
        public var implies: [Int]
        public var collectionClassIds: [Int]
        public var variables: [ActionVariable]
    }
}

// MARK: - Collections and values

extension LucentAPI {
    /// Exactly one of four kinds, matching the variable's value class.
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

    public struct Value: Codable, Hashable, Sendable {
        public var id: Int
        public var collectionId: Int
        public var actionVariableId: Int
        public var repetition: Int
        public var reading: Reading
        public var accepted: Bool
        public var measuredAt: Date?
        /// Who measured it.
        public var personId: Int?
        public var deviceId: Int?
        /// Outside the action variable's limits.
        public var exceeds: Bool
        public var etag: String
    }

    public enum Status: String, Codable, Hashable, Sendable {
        case registered
        case inAnalysis = "in_analysis"
        case inReview = "in_review"
        case approved
    }

    public struct Collection: Codable, Hashable, Sendable {
        public var id: Int
        public var name: String
        public var matrixId: Int?
        public var classId: Int?
        public var spotId: Int?
        public var siteId: Int?
        public var sampledAt: Date?
        public var samplerId: Int?
        public var status: Status
        /// Planned variables with at least one value.
        public var measured: Int
        public var planned: Int
        public var exceedances: Int
    }

    /// A collection with all its values.
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
        public var valueId: Int
        public var collectionId: Int
        public var sampledAt: Date?
        public var value: Double
        public var exceeds: Bool
    }

    public struct NewCollection: Encodable, Sendable {
        public var matrixId: Int
        public var classId: Int
        public var spotId: Int?
        public var siteId: Int?
        public var sampledAt: Date?
        public var samplerId: Int?
        public var note: String?

        public init(matrixId: Int, classId: Int, spotId: Int? = nil, siteId: Int? = nil, sampledAt: Date? = nil,
                    samplerId: Int? = nil, note: String? = nil) {
            self.matrixId = matrixId
            self.classId = classId
            self.spotId = spotId
            self.siteId = siteId
            self.sampledAt = sampledAt
            self.samplerId = samplerId
            self.note = note
        }
    }

    public struct NewValue: Encodable, Sendable {
        public var actionVariableId: Int
        public var reading: Reading
        public var deviceId: Int?
        public var measuredAt: Date?
        public var note: String?

        public init(actionVariableId: Int, reading: Reading, deviceId: Int? = nil, measuredAt: Date? = nil,
                    note: String? = nil) {
            self.actionVariableId = actionVariableId
            self.reading = reading
            self.deviceId = deviceId
            self.measuredAt = measuredAt
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
        public var assignerId: Int?
        public var assigneeId: Int?
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
        public var senderId: Int?
        public var receiverId: Int?
        public var subject: String?
        public var body: String?
        public var read: Bool
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
