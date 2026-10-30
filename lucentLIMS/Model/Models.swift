import Foundation
import CoreLocation

// The types follow lucentBASE (github.com/BooneyNoobington/lucentBase). Where a name would
// clash with Foundation or SwiftUI (Collection, Unit, Dimension, Link, …) it gets a prefix.

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
    var linuxUser: String
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

/// Something an action yields: a measured quantity, but also e.g. "was the sample filtered?".
struct Parameter: Identifiable, Hashable, Sendable {
    let id: Int
    var name: String
    var description: String
    var unitID: Int?
    var valueClass: ValueClass
}

// MARK: - Actions, devices, documents

struct Device: Identifiable, Hashable, Sendable {
    let id: Int
    var name: String
    var number: Int
    /// An organization.
    var manufacturerID: Int?
    /// An organization, as in lucentBASE.
    var operatorID: Int?
    var active: Bool
    /// lucentAPI's version tag, sent back when changing the device.
    var etag: String? = nil
}

/// A link: an SOP, a standard, a regulation, any file or web page.
struct Document: Identifiable, Hashable, Sendable {
    let id: Int
    var name: String
    var url: URL?
    var filePath: String?
    var accepted: Bool
    var sha256: String
}

/// A person's part in an action (`j_action_person`): auditor, manager or worker.
struct Assignment: Hashable, Sendable {
    var personID: Int
    var role: String
}

/// The action depends on another one (`j_action_action`).
struct Dependency: Hashable, Sendable {
    enum Kind: String, Hashable, Sendable { case strict, possibility }
    var actionID: Int
    var kind: Kind
    var description: String
}

/// Something done to a collection: sampling, a measurement, a check (`action`).
struct LabAction: Identifiable, Hashable, Sendable {
    let id: Int
    var name: String
    /// The version of the action, as a point in time.
    var iteration: Date
    var active: Bool
    var description: String
    var documentIDs: [Int]
    var deviceIDs: [Int]
    var people: [Assignment]
    var dependencies: [Dependency]
}

enum UncertaintyClass: String, Hashable, Sendable {
    case absolute, relative
}

/// What an action yields: one parameter, with method-specific uncertainty (`effect`).
struct Effect: Identifiable, Hashable, Sendable {
    let id: Int
    var actionID: Int
    var parameterID: Int
    var uncertainty: Double?
    var uncertaintyClass: UncertaintyClass
    var calculation: String?
    /// The unit of an absolute uncertainty, if not the parameter's.
    var uncertaintyUnitID: Int? = nil
}

/// Limits of a parameter in the context of a document, in the parameter's unit (`threshold`).
struct Threshold: Identifiable, Hashable, Sendable {
    let id: Int
    var parameterID: Int
    var documentID: Int
    var lowerLimit: Double?
    var upperLimit: Double?
    var description: String

    func excludes(_ number: Double) -> Bool {
        (lowerLimit.map { number < $0 } ?? false) || (upperLimit.map { number > $0 } ?? false)
    }

    var rangeDescription: String {
        switch (lowerLimit, upperLimit) {
        case let (low?, high?): "\(low.formatted()) – \(high.formatted())"
        case let (nil, high?): "≤ \(high.formatted())"
        case let (low?, nil): "≥ \(low.formatted())"
        case (nil, nil): ""
        }
    }
}

/// Two effects that belong together (`coefficient`).
struct Coefficient: Identifiable, Hashable, Sendable {
    let id: Int
    var effectIDs: [Int]
    var description: String
}

// MARK: - Collections, values, raw values

/// A sample or a series of samples (`collection`).
struct LabCollection: Identifiable, Hashable, Sendable {
    let id: Int
    /// The readable identifier from the numbering scheme.
    var name: String
    var matrixID: Int
    /// One of lucentBASE's collection classes, e.g. "spot sample".
    var collectionClass: String
    var spotID: Int?
    var siteID: Int?
    /// The sampling-time raw value, else when it was registered.
    var sampledAt: Date
    var sampledByID: Int?
}

/// What a raw value holds.
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

/// A collection's slot for one effect (`value`). Its readings are raw values.
struct LabValue: Identifiable, Hashable, Sendable {
    let id: Int
    var collectionID: Int
    var effectID: Int
}

/// A reading of a value (`raw_value`). Further readings of the same value are repetitions.
struct RawValue: Identifiable, Hashable, Sendable {
    let id: Int
    var valueID: Int
    var t: Date?
    var personID: Int?
    var deviceID: Int?
    var unitID: Int?
    var reading: Reading?
    var accepted: Bool
    var etag: String? = nil
}

/// Derived from a collection's values and raw values.
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
    /// From lucentBASE's log.
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
    var collectionClasses: [String]
    var dimensions: [PhysicalDimension]
    var units: [LabUnit]
    var parameters: [Parameter]
    var devices: [Device]
    var documents: [Document]
    var actions: [LabAction]
    var effects: [Effect]
    var thresholds: [Threshold]
    var coefficients: [Coefficient]
    var collections: [LabCollection]
    var values: [LabValue]
    var rawValues: [RawValue]
    var tasks: [LabTask]
    var messages: [Message]
    /// The parameter whose datetime raw value is a collection's sampling time.
    var samplingTimeParameterID: Int?
}
