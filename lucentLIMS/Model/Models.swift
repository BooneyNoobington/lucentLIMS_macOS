import Foundation
import CoreLocation

// The types follow the tables of lucentBASE. Where a name would clash with Foundation or
// SwiftUI (Collection, Unit, Dimension, Link, …) it gets a prefix. Fields that lucentBASE
// doesn't have yet are marked "not in lucentBASE".

// MARK: - People and organizations

struct Organization: Identifiable, Hashable, Sendable {
    let id: Int
    var name: String
    var shorthand: String
}

struct Person: Identifiable, Hashable, Sendable {
    let id: Int
    var givenName: String
    var surname: String
    var unixAccount: String
    var organizationID: Int?
    /// From `j_person_organization.position`.
    var position: String?

    var fullName: String { "\(givenName) \(surname)" }
    var initials: String { String([givenName.first, surname.first].compactMap { $0 }) }
}

// MARK: - Locations

struct CRS: Identifiable, Hashable, Sendable {
    let id: Int
    var epsg: Int?
    var name: String
}

/// The address of a house, as the view `v_address` joins it.
struct Address: Hashable, Sendable {
    var street: String
    var houseNumber: String
    var addition: String?
    var zip: String
    var district: String
    var city: String

    var line1: String { [street, houseNumber + (addition ?? "")].joined(separator: " ") }
    var line2: String { "\(zip) \(city)-\(district)" }
}

struct GeoPoint: Hashable, Sendable {
    var latitude: Double
    var longitude: Double
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

/// An area, drawn as a polygon.
struct Site: Identifiable, Hashable, Sendable {
    let id: Int
    var name: String
    var description: String
    var address: Address?
    var border: [GeoPoint]
    var crsID: Int?

    var center: GeoPoint {
        let n = Double(max(border.count, 1))
        return GeoPoint(
            latitude: border.map(\.latitude).reduce(0, +) / n,
            longitude: border.map(\.longitude).reduce(0, +) / n
        )
    }
}

/// A point where samples are taken. As in lucentBASE, `x` is the latitude and `y` the longitude.
struct Spot: Identifiable, Hashable, Sendable {
    let id: Int
    var name: String
    var description: String
    var x: Double?
    var y: Double?
    var crsID: Int?
    var siteID: Int?

    var point: GeoPoint? {
        guard let x, let y else { return nil }
        return GeoPoint(latitude: x, longitude: y)
    }
}

enum LocationRef: Hashable, Sendable {
    case spot(Int)
    case site(Int)
}

// MARK: - Scientific

struct Matrix: Identifiable, Hashable, Sendable {
    let id: Int
    var name: String
    var description: String
}

struct CollectionClass: Identifiable, Hashable, Sendable {
    let id: Int
    var name: String
    var description: String
}

struct PhysicalDimension: Identifiable, Hashable, Sendable {
    let id: Int
    var name: String
    var description: String
}

struct LabUnit: Identifiable, Hashable, Sendable {
    let id: Int
    var name: String
    /// From `unit_notation`. The first one is used for display.
    var notations: [String]
    var dimensionID: Int?

    var symbol: String { notations.first ?? "" }
}

enum ValueClass: String, CaseIterable, Hashable, Sendable {
    case decimal, text, boolean, datetime
}

struct Variable: Identifiable, Hashable, Sendable {
    let id: Int
    var name: String
    var valueClass: ValueClass
    var description: String
    var dimensionID: Int?
}

// MARK: - Methods, devices, SOPs

struct Device: Identifiable, Hashable, Sendable {
    let id: Int
    var name: String
    var number: String
    var manufacturerID: Int?
    var operatorID: Int?
    var active: Bool
    /// lucentAPI's version tag, sent back when changing the device.
    var etag: String? = nil
}

/// A document of an SOP (`link`), either a URL or a file path.
struct SOPDocument: Identifiable, Hashable, Sendable {
    let id: Int
    var name: String
    var url: URL?
    var filePath: String?
    var accepted: Bool
    var sha256: String
}

struct Assignment: Hashable, Sendable {
    var personID: Int
    var role: String
}

struct SOP: Identifiable, Hashable, Sendable {
    let id: Int
    var name: String
    var active: Bool
    var documents: [SOPDocument]
    var people: [Assignment]
}

/// An analytical method or procedure (`action`).
struct LabAction: Identifiable, Hashable, Sendable {
    let id: Int
    var name: String
    var standard: String
    var iteration: Int
    var active: Bool
    var description: String
    var sopID: Int?
    var deviceIDs: [Int]
    var people: [Assignment]
    /// Actions that have to be done before this one (`j_action_dependency`).
    var dependsOn: [Int]
    /// Actions that this one entails (`j_action_implication`).
    var implies: [Int]
}

enum UncertaintyClass: String, Hashable, Sendable {
    case absolute, relative
}

/// A variable that an action measures, with unit and uncertainty (`j_action_variable`).
struct ActionVariable: Identifiable, Hashable, Sendable {
    let id: Int
    var actionID: Int
    var variableID: Int
    var unitID: Int?
    var uncertainty: Double?
    var uncertaintyClass: UncertaintyClass
    var calculation: String?
    /// Display precision. Not in lucentBASE.
    var decimals: Int = 1
    /// Limits for the value. Not in lucentBASE. A boolean counts as 0 or 1.
    var lowerLimit: Double? = nil
    var upperLimit: Double? = nil

    func exceeds(_ reading: Reading) -> Bool {
        guard let number = reading.number else { return false }
        if let lowerLimit, number < lowerLimit { return true }
        if let upperLimit, number > upperLimit { return true }
        return false
    }

    var limitDescription: String? {
        switch (lowerLimit, upperLimit) {
        case let (low?, high?): "\(low.formatted()) – \(high.formatted())"
        case let (nil, high?): "≤ \(high.formatted())"
        case let (low?, nil): "≥ \(low.formatted())"
        case (nil, nil): nil
        }
    }
}

// MARK: - Collections and values

/// A sample or a series of samples (`collection`).
struct LabCollection: Identifiable, Hashable, Sendable {
    let id: Int
    /// The readable identifier from the numbering scheme.
    var name: String
    var matrixID: Int
    var classID: Int
    var spotID: Int?
    var siteID: Int?
    /// Not in lucentBASE.
    var sampledAt: Date
    /// Not in lucentBASE.
    var sampledByID: Int?
}

enum Reading: Hashable, Sendable {
    case decimal(Double)
    case text(String)
    case boolean(Bool)
    case datetime(Date)

    var number: Double? {
        switch self {
        case .decimal(let value): value
        case .boolean(let value): value ? 1 : 0
        case .text, .datetime: nil
        }
    }
}

/// A result (`value`). Its raw values (`raw_value`) aren't modelled yet.
struct LabValue: Identifiable, Hashable, Sendable {
    let id: Int
    var collectionID: Int
    var actionVariableID: Int
    var repetition: Int
    var reading: Reading
    var accepted: Bool
    /// When, by whom and with what it was measured, from lucentBASE's raw values.
    var measuredAt: Date?
    var personID: Int?
    var deviceID: Int?
    var etag: String? = nil
}

/// Derived from the values of a collection against what its class plans.
enum CollectionStatus: Int, CaseIterable, Comparable, Identifiable, Sendable {
    case registered, inAnalysis, inReview, approved

    var id: Int { rawValue }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

// MARK: - Management

struct LabTask: Identifiable, Hashable, Sendable {
    let id: Int
    var request: String
    var description: String
    var assignerID: Int?
    var assigneeID: Int?
    var deadline: Date
    /// Not in lucentBASE.
    var done: Bool
    var etag: String? = nil
}

struct Message: Identifiable, Hashable, Sendable {
    let id: Int
    var senderID: Int?
    var receiverID: Int?
    var subject: String
    var body: String
    var read: Bool
    /// Not in lucentBASE.
    var sentAt: Date
}

// MARK: - Everything together

struct LabData: Sendable {
    var organizations: [Organization]
    var people: [Person]
    var crs: [CRS]
    var sites: [Site]
    var spots: [Spot]
    var matrices: [Matrix]
    var collectionClasses: [CollectionClass]
    /// Which actions a collection class plans (`j_action_collection_class`).
    var classActions: [Int: [Int]]
    var dimensions: [PhysicalDimension]
    var units: [LabUnit]
    var variables: [Variable]
    var devices: [Device]
    var sops: [SOP]
    var actions: [LabAction]
    var actionVariables: [ActionVariable]
    var collections: [LabCollection]
    var values: [LabValue]
    var tasks: [LabTask]
    var messages: [Message]
}
