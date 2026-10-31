import Foundation
import LucentAPIClient
import Testing
@testable import lucentLIMS

/// The bundled demo package, lucentAPI's demo master data, in the app's types.
struct PackageDataTests {
    @Test func entriesGetTheIDsOfAnImportIntoAnEmptyLucentBase() throws {
        let demo = try PackageData.demo()
        #expect(demo.people.map(\.linuxUser) == ["grindel", "jd", "worf", "s7e23", "p47at", "xx121"])
        #expect(demo.people[MockData.ripley - 1].surname == "Ripley")
        #expect(demo.parameters[MockData.samplingTime - 1].name == "Probenahmezeitpunkt")
        let gwm = try #require(demo.spots.first { $0.name == "GWM 12" })
        #expect(gwm.id == 9 && demo.sites.first { $0.id == gwm.siteID }?.name == "Messfeld Rheinaue")
        // Effects are numbered across the actions, in their order.
        #expect(demo.effects.map(\.id) == Array(1...demo.effects.count))
        #expect(demo.effects.map(\.actionID) == demo.effects.map(\.actionID).sorted())
    }

    @Test func referencesByNameBecomeIDs() throws {
        let demo = try PackageData.demo()
        let ph = try #require(demo.actions.first { $0.name == "pH-Wert" && $0.active })
        #expect(ph.deviceIDs.compactMap { id in demo.devices.first { $0.id == id }?.number } == [2207114, 1903027])
        #expect(ph.people.map(\.personID) == [MockData.doe, MockData.picard, MockData.ripley])
        #expect(ph.dependencies.map(\.actionID) == [1])
        let lead = try #require(demo.parameters.first { $0.name == "Blei" })
        #expect(demo.units.first { $0.id == lead.unitID }?.symbol == "µg/L")
        // Conductivity is referred to the sampling temperature.
        let coefficient = try #require(demo.coefficients.first)
        #expect(coefficient.effectIDs.compactMap { id in demo.effects.first { $0.id == id }?.parameterID } == [6, 2])
    }

    @Test func anUnknownNameIsAnError() throws {
        let url = try #require(Bundle.main.url(forResource: "demo.lucent", withExtension: "json"))
        var package = try LucentAPIClient.decoder.decode(LucentAPI.Package.self, from: Data(contentsOf: url))
        package.parameters[1].unit = "Kelvin"
        #expect {
            try PackageData(package)
        } throws: { error in
            (error as? PackageData.Unresolved)?.path == "parameters[1].unit"
        }
    }
}
