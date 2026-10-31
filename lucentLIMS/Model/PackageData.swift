import Foundation
import LucentAPIClient

/// The master data of a lucent package in the app's types. Entries get ids in their order in the
/// package, as an import into an empty lucentBASE gives them, and references by name become ids:
/// a unit by its name or a notation, a person by linux user or full name, an action by name and
/// iteration, a device by name and number.
struct PackageData {
    var organizations: [Organization] = []
    var people: [Person] = []
    var crs: [CRS] = []
    var dimensions: [PhysicalDimension] = []
    var units: [LabUnit] = []
    var matrices: [Matrix] = []
    var parameters: [Parameter] = []
    var devices: [Device] = []
    var documents: [Document] = []
    var sites: [Site] = []
    var spots: [Spot] = []
    var actions: [LabAction] = []
    var effects: [Effect] = []
    var thresholds: [Threshold] = []
    var coefficients: [Coefficient] = []

    struct Unresolved: LocalizedError {
        var path: String
        var name: String
        var errorDescription: String? { "\(path): nothing is called “\(name)”." }
    }

    /// The bundled demo package, lucentAPI's demo master data.
    static func demo(in bundle: Bundle = .main) throws -> PackageData {
        let url = bundle.url(forResource: "demo.lucent", withExtension: "json")!
        return try PackageData(LucentAPIClient.decoder.decode(LucentAPI.Package.self, from: Data(contentsOf: url)))
    }

    init(_ package: LucentAPI.Package) throws {
        func index(_ keys: [[String]]) -> [String: Int] {
            var ids: [String: Int] = [:]
            for (offset, names) in keys.enumerated() {
                for name in names where ids[name] == nil { ids[name] = offset + 1 }
            }
            return ids
        }
        func id(_ name: String?, in ids: [String: Int], at path: String) throws -> Int? {
            guard let name else { return nil }
            guard let id = ids[name] else { throw Unresolved(path: path, name: name) }
            return id
        }
        func iteration(_ text: String) -> Date {
            (try? Date(text, strategy: .iso8601.year().month().day())) ?? (try? Date(text, strategy: .iso8601)) ?? .distantPast
        }

        let organizationIDs = index(package.organizations.map { [$0.name] })
        organizations = package.organizations.enumerated().map { offset, o in
            Organization(id: offset + 1, name: o.name, shorthand: o.shorthand ?? "")
        }

        let personIDs = index(package.people.map { [$0.linuxUser, "\($0.givenName) \($0.surname)"].compactMap { $0 } })
        people = try package.people.enumerated().map { offset, p in
            Person(id: offset + 1, givenName: p.givenName, surname: p.surname, linuxUser: p.linuxUser ?? "",
                   organizationID: try id(p.organization, in: organizationIDs, at: "people[\(offset)].organization"),
                   position: p.position, active: p.active,
                   roles: Set(p.roles.compactMap { LabRole(rawValue: $0.rawValue) }))
        }

        let crsIDs = index(package.referenceSystems.map { [$0.name] })
        crs = package.referenceSystems.enumerated().map { offset, c in CRS(id: offset + 1, epsg: c.epsg, name: c.name) }

        let dimensionIDs = index(package.dimensions.map { [$0.name] })
        dimensions = package.dimensions.enumerated().map { offset, d in
            PhysicalDimension(id: offset + 1, name: d.name, description: d.description ?? "")
        }

        let unitIDs = index(package.units.map { [$0.name] + $0.notations })
        units = try package.units.enumerated().map { offset, u in
            LabUnit(id: offset + 1, name: u.name, notations: u.notations,
                    dimensionID: try id(u.dimension, in: dimensionIDs, at: "units[\(offset)].dimension"))
        }

        let matrixIDs = index(package.matrices.map { [$0.name] })
        matrices = package.matrices.enumerated().map { offset, m in
            Matrix(id: offset + 1, name: m.name, description: m.description ?? "")
        }

        let parameterIDs = index(package.parameters.map { [$0.name] })
        parameters = try package.parameters.enumerated().map { offset, p in
            Parameter(id: offset + 1, name: p.name, description: p.description ?? "",
                      unitID: try id(p.unit, in: unitIDs, at: "parameters[\(offset)].unit"),
                      valueClass: ValueClass(rawValue: p.valueClass.rawValue) ?? .text)
        }

        let deviceIDs = index(package.devices.map { ["\($0.name) \($0.number)"] })
        devices = try package.devices.enumerated().map { offset, d in
            Device(id: offset + 1, name: d.name, number: d.number,
                   manufacturerID: try id(d.manufacturer, in: organizationIDs, at: "devices[\(offset)].manufacturer"),
                   operatorID: try id(d.operator_, in: organizationIDs, at: "devices[\(offset)].operator"),
                   active: d.active)
        }

        let documentIDs = index(package.documents.map { [$0.name] })
        documents = package.documents.enumerated().map { offset, d in
            Document(id: offset + 1, name: d.name, url: d.uri.flatMap(URL.init(string:)), filePath: d.filePath,
                     accepted: d.accepted, sha256: d.sha256 ?? "")
        }

        let siteIDs = index(package.sites.map { [$0.name] })
        sites = try package.sites.enumerated().map { offset, s in
            Site(id: offset + 1, name: s.name, description: s.description ?? "",
                 address: s.address.map {
                     Address(street: $0.street, houseNumber: String($0.houseNumber), addition: $0.addition,
                             zip: $0.zip, district: $0.district, city: $0.city)
                 },
                 border: s.border.map { GeoPoint(latitude: $0.latitude, longitude: $0.longitude) },
                 crsID: try id(s.referenceSystem, in: crsIDs, at: "sites[\(offset)].reference_system"))
        }

        spots = try package.spots.enumerated().map { offset, s in
            Spot(id: offset + 1, name: s.name, description: s.description ?? "", x: s.latitude, y: s.longitude,
                 crsID: try id(s.referenceSystem, in: crsIDs, at: "spots[\(offset)].reference_system"),
                 siteID: try id(s.site, in: siteIDs, at: "spots[\(offset)].site"))
        }

        // Actions may depend on ones further down, so they are all known before the dependencies.
        let actionIDs = index(package.actions.map { ["\($0.name) \($0.iteration)"] })
        var effectIDs: [String: Int] = [:]
        for (offset, a) in package.actions.enumerated() {
            let path = "actions[\(offset)]"
            actions.append(LabAction(
                id: offset + 1, name: a.name, iteration: iteration(a.iteration), active: a.active,
                description: a.description ?? "",
                documentIDs: try a.documents.enumerated().compactMap { i, name in
                    try id(name, in: documentIDs, at: "\(path).documents[\(i)]")
                },
                deviceIDs: try a.devices.enumerated().compactMap { i, d in
                    try id("\(d.name) \(d.number)", in: deviceIDs, at: "\(path).devices[\(i)]")
                },
                people: try a.people.enumerated().map { i, assignment in
                    Assignment(personID: try id(assignment.person, in: personIDs, at: "\(path).people[\(i)].person")!,
                               role: assignment.role)
                },
                dependencies: try a.dependsOn.enumerated().map { i, d in
                    Dependency(actionID: try id("\(d.action) \(d.iteration)", in: actionIDs,
                                                at: "\(path).depends_on[\(i)]")!,
                               kind: Dependency.Kind(rawValue: d.dependencyClass) ?? .strict,
                               description: d.description ?? "")
                }))
            for (i, e) in a.effects.enumerated() {
                let effect = Effect(
                    id: effects.count + 1, actionID: offset + 1,
                    parameterID: try id(e.parameter, in: parameterIDs, at: "\(path).effects[\(i)].parameter")!,
                    uncertainty: e.uncertainty, uncertaintyClass: e.uncertaintyClass == "relative" ? .relative : .absolute,
                    calculation: e.calculation,
                    uncertaintyUnitID: try id(e.uncertaintyUnit, in: unitIDs, at: "\(path).effects[\(i)].uncertainty_unit"))
                effects.append(effect)
                effectIDs["\(a.name) \(a.iteration) \(e.parameter)"] = effect.id
            }
        }

        thresholds = try package.thresholds.enumerated().map { offset, t in
            Threshold(id: offset + 1,
                      parameterID: try id(t.parameter, in: parameterIDs, at: "thresholds[\(offset)].parameter")!,
                      documentID: try id(t.document, in: documentIDs, at: "thresholds[\(offset)].document")!,
                      lowerLimit: t.lower, upperLimit: t.upper, description: t.description ?? "")
        }

        coefficients = try package.coefficients.enumerated().map { offset, c in
            Coefficient(id: offset + 1, effectIDs: try c.effects.enumerated().compactMap { i, e in
                try id("\(e.action) \(e.iteration) \(e.parameter)", in: effectIDs, at: "coefficients[\(offset)].effects[\(i)]")
            }, description: c.description ?? "")
        }
    }
}
