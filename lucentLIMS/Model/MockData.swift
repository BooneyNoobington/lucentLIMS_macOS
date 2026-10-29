import Foundation
import CryptoKit

/// A small deterministic random number generator (SplitMix64), so the mock data looks the
/// same on every launch.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A normally distributed number (Box–Muller).
    mutating func normal(_ mean: Double, _ sd: Double) -> Double {
        let u1 = Double.random(in: Double.ulpOfOne..<1, using: &self)
        let u2 = Double.random(in: 0..<1, using: &self)
        return mean + sd * (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }

    mutating func chance(_ probability: Double) -> Bool {
        Double.random(in: 0..<1, using: &self) < probability
    }
}

/// Mock data in the shape of lucentBASE. The people, matrices and the spots "Test 1" and
/// "Garten" come from lucentAndShiny's demo data, everything else is made up. Dates are
/// relative to `now`, so the dashboard always looks current.
enum MockData {
    // People
    static let noobington = 23, doe = 24, dorn = 26, simpson = 27, picard = 28, ripley = 29

    static func make(now: Date = .now, calendar: Calendar = .current) -> LabData {
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int, hour: Int = 16) -> Date {
            calendar.date(byAdding: .hour, value: offset * 24 + hour, to: today)!
        }

        let organizations = [
            Organization(id: 5, name: "Redhsoft Inc", shorthand: "Redhsoft"),
            Organization(id: 10, name: "Umweltlabor Lucent", shorthand: "Lucent"),
            Organization(id: 11, name: "Ionic Instruments GmbH", shorthand: "Ionic"),
            Organization(id: 12, name: "Spectra Analytik AG", shorthand: "Spectra"),
            Organization(id: 13, name: "Klarsicht Messtechnik KG", shorthand: "Klarsicht"),
            Organization(id: 14, name: "Aerosol Systems GmbH", shorthand: "Aerosol"),
        ]

        let people = [
            Person(id: noobington, givenName: "Booney", surname: "Noobington", unixAccount: "grindel", organizationID: 5, position: "Administration"),
            Person(id: doe, givenName: "John", surname: "Doe", unixAccount: "jd", organizationID: 10, position: "Analytik"),
            Person(id: dorn, givenName: "Michael", surname: "Dorn", unixAccount: "worf", organizationID: 10, position: "Probenahme"),
            Person(id: simpson, givenName: "Homer", surname: "Simpson", unixAccount: "s7e23", organizationID: 10, position: "Luftmessnetz"),
            Person(id: picard, givenName: "Jean Luc", surname: "Picard", unixAccount: "p47at", organizationID: 10, position: "Laborleitung"),
            Person(id: ripley, givenName: "Ellen", surname: "Ripley", unixAccount: "xx121", organizationID: 10, position: "Qualitätssicherung"),
        ]

        let crs = [CRS(id: 1, epsg: 4326, name: "WGS 84")]

        let sites = [
            Site(id: 1, name: "Betriebsgelände Laborstraße", description: "Labor- und Verwaltungsgebäude",
                 address: Address(street: "Laborstraße", houseNumber: "4", zip: "76131", district: "Oststadt", city: "Karlsruhe"),
                 border: [.init(latitude: 49.0103, longitude: 8.4102), .init(latitude: 49.0106, longitude: 8.4139),
                          .init(latitude: 49.0088, longitude: 8.4145), .init(latitude: 49.0084, longitude: 8.4108)],
                 crsID: 1),
            Site(id: 2, name: "Wasserwerk Ost", description: "Fassungsgelände mit den Brunnen B3 und B7",
                 address: Address(street: "Am Wasserwerk", houseNumber: "1", addition: "a", zip: "76227", district: "Durlach", city: "Karlsruhe"),
                 border: [.init(latitude: 48.9990, longitude: 8.4510), .init(latitude: 48.9995, longitude: 8.4600),
                          .init(latitude: 48.9950, longitude: 8.4612), .init(latitude: 48.9944, longitude: 8.4515)],
                 crsID: 1),
            Site(id: 3, name: "Messfeld Rheinaue", description: "Grundwassermessstellen am Altrhein",
                 address: Address(street: "Rheinauenweg", houseNumber: "12", zip: "76187", district: "Knielingen", city: "Karlsruhe"),
                 border: [.init(latitude: 49.0335, longitude: 8.3010), .init(latitude: 49.0340, longitude: 8.3095),
                          .init(latitude: 49.0290, longitude: 8.3105), .init(latitude: 49.0282, longitude: 8.3020)],
                 crsID: 1),
        ]

        let spots = [
            Spot(id: 2, name: "Test 1", description: "Erster Test", x: 49.006986, y: 8.376389, crsID: 1),
            Spot(id: 3, name: "Garten", description: "Unter dem Dach der Fahrradgarage", x: 49.006097, y: 8.382112, crsID: 1),
            Spot(id: 4, name: "Zapfstelle Labor 2.14", description: "Kaltwasserhahn im Altbau, 2. OG", x: 49.0096, y: 8.4118, crsID: 1, siteID: 1),
            Spot(id: 5, name: "Zapfstelle Kantine", description: "Spülküche, Mischbatterie links", x: 49.0091, y: 8.4132, crsID: 1, siteID: 1),
            Spot(id: 6, name: "Hochbehälter Nord", description: "Probenahmehahn Kammer 1", x: 49.0352, y: 8.4212, crsID: 1),
            Spot(id: 7, name: "Wasserwerk Reinwasser", description: "Reinwasserbehälter, Ausgang ins Netz", x: 48.9962, y: 8.4566, crsID: 1, siteID: 2),
            Spot(id: 8, name: "Brunnen B3", description: "Vertikalfilterbrunnen, 28 m", x: 48.9978, y: 8.4531, crsID: 1, siteID: 2),
            Spot(id: 9, name: "Brunnen B7", description: "Vertikalfilterbrunnen, 34 m", x: 48.9958, y: 8.4592, crsID: 1, siteID: 2),
            Spot(id: 10, name: "GWM 12", description: "Grundwassermessstelle am Feldrand", x: 49.0318, y: 8.3046, crsID: 1, siteID: 3),
            Spot(id: 11, name: "Messcontainer Innenstadt", description: "Verkehrsnahe Luftmessstation", x: 49.0094, y: 8.4010, crsID: 1),
        ]

        let matrices = [
            Matrix(id: 8, name: "Luft", description: "Außen- oder Innenluft"),
            Matrix(id: 9, name: "Leitungswasser", description: "Aus der Hausinstallation"),
            Matrix(id: 10, name: "Trinkwasser", description: "Gemäß Trinkwasserverordnung"),
            Matrix(id: 11, name: "Grundwasser", description: "Aus Brunnen und Messstellen"),
        ]

        let collectionClasses = [
            CollectionClass(id: 1, name: "Routineprobe", description: "Routinemäßige Untersuchung von Wasser"),
            CollectionClass(id: 2, name: "Zeitreihe", description: "Wiederkehrende Luftmessung an einem Spot"),
            CollectionClass(id: 3, name: "Umfassende Untersuchung", description: "Routine plus Anionen und Metalle"),
            CollectionClass(id: 4, name: "Grundwassermonitoring", description: "Überwachung der Grundwasserbeschaffenheit"),
        ]
        let classActions = [1: [1, 2, 3, 4, 7], 2: [8, 9], 3: [1, 2, 3, 4, 5, 6, 7], 4: [1, 3, 4, 5]]

        let dimensions = [
            PhysicalDimension(id: 1, name: "Dimensionslos", description: "Größen ohne Einheit, z. B. der pH-Wert"),
            PhysicalDimension(id: 2, name: "Temperatur", description: "Thermodynamische Temperatur"),
            PhysicalDimension(id: 3, name: "Elektrische Leitfähigkeit", description: "Leitwert pro Länge"),
            PhysicalDimension(id: 4, name: "Massenkonzentration", description: "Masse pro Volumen"),
            PhysicalDimension(id: 5, name: "Anzahlkonzentration", description: "Anzahl pro Volumen, z. B. koloniebildende Einheiten"),
        ]

        let units = [
            LabUnit(id: 1, name: "Ohne Einheit", notations: [], dimensionID: 1),
            LabUnit(id: 2, name: "Grad Celsius", notations: ["°C"], dimensionID: 2),
            LabUnit(id: 3, name: "Mikrosiemens pro Zentimeter", notations: ["µS/cm", "µS cm⁻¹"], dimensionID: 3),
            LabUnit(id: 4, name: "Milligramm pro Liter", notations: ["mg/L", "mg l⁻¹", "ppm"], dimensionID: 4),
            LabUnit(id: 5, name: "Mikrogramm pro Liter", notations: ["µg/L", "µg l⁻¹", "ppb"], dimensionID: 4),
            LabUnit(id: 6, name: "Mikrogramm pro Kubikmeter", notations: ["µg/m³", "µg m⁻³"], dimensionID: 4),
            LabUnit(id: 7, name: "Koloniebildende Einheiten pro 100 Milliliter", notations: ["KBE/100 mL", "CFU/100 mL"], dimensionID: 5),
        ]

        let variables = [
            Variable(id: 1, name: "Temperatur", valueClass: .decimal, description: "Wassertemperatur bei der Probenahme", dimensionID: 2),
            Variable(id: 2, name: "pH-Wert", valueClass: .decimal, description: "Negativer dekadischer Logarithmus der Oxoniumaktivität", dimensionID: 1),
            Variable(id: 3, name: "Elektrische Leitfähigkeit", valueClass: .decimal, description: "Bezogen auf 25 °C", dimensionID: 3),
            Variable(id: 4, name: "Nitrat", valueClass: .decimal, description: "NO₃⁻", dimensionID: 4),
            Variable(id: 5, name: "Chlorid", valueClass: .decimal, description: "Cl⁻", dimensionID: 4),
            Variable(id: 6, name: "Sulfat", valueClass: .decimal, description: "SO₄²⁻", dimensionID: 4),
            Variable(id: 7, name: "Blei", valueClass: .decimal, description: "Pb, gesamt", dimensionID: 4),
            Variable(id: 8, name: "Kupfer", valueClass: .decimal, description: "Cu, gesamt", dimensionID: 4),
            Variable(id: 9, name: "Nickel", valueClass: .decimal, description: "Ni, gesamt", dimensionID: 4),
            Variable(id: 10, name: "Escherichia coli", valueClass: .decimal, description: "Fäkalindikator", dimensionID: 5),
            Variable(id: 11, name: "Coliforme Bakterien", valueClass: .decimal, description: "Hygieneindikator", dimensionID: 5),
            Variable(id: 12, name: "Feinstaub PM10", valueClass: .decimal, description: "Partikel ≤ 10 µm, Tagesmittel", dimensionID: 4),
            Variable(id: 13, name: "Feinstaub PM2,5", valueClass: .decimal, description: "Partikel ≤ 2,5 µm, Tagesmittel", dimensionID: 4),
            Variable(id: 14, name: "Stickstoffdioxid", valueClass: .decimal, description: "NO₂, Tagesmittel", dimensionID: 4),
            Variable(id: 15, name: "Färbung", valueClass: .text, description: "Visuelle Prüfung", dimensionID: nil),
            Variable(id: 16, name: "Geruch auffällig", valueClass: .boolean, description: "Olfaktorische Prüfung", dimensionID: nil),
        ]

        let devices = [
            Device(id: 1, name: "pH-Meter Lab 1", number: "PH-2207-114", manufacturerID: 11, operatorID: doe, active: true),
            Device(id: 2, name: "pH-Meter Lab 2 (Reserve)", number: "PH-1903-027", manufacturerID: 11, operatorID: doe, active: false),
            Device(id: 3, name: "Leitfähigkeitsmessgerät LF 4", number: "LF-2105-033", manufacturerID: 11, operatorID: doe, active: true),
            Device(id: 4, name: "Ionenchromatograph IC-3", number: "IC3-0098", manufacturerID: 12, operatorID: doe, active: true),
            Device(id: 5, name: "ICP-MS Q2", number: "ICPMS-Q2-4411", manufacturerID: 12, operatorID: picard, active: true),
            Device(id: 6, name: "Brutschrank 36 °C", number: "BS36-002", manufacturerID: 13, operatorID: ripley, active: true),
            Device(id: 7, name: "Feinstaubsammler LVS-3 Nr. 1", number: "LVS3-1187", manufacturerID: 14, operatorID: simpson, active: true),
            Device(id: 8, name: "Feinstaubsammler LVS-3 Nr. 2", number: "LVS3-1192", manufacturerID: 14, operatorID: simpson, active: true),
            Device(id: 9, name: "NO₂-Analysator", number: "NOX500-221", manufacturerID: 14, operatorID: simpson, active: true),
            Device(id: 10, name: "Feinwaage XS205", number: "XS205-778", manufacturerID: 13, operatorID: doe, active: true),
            Device(id: 11, name: "Einstichthermometer", number: "TH-0042", manufacturerID: 13, operatorID: dorn, active: true),
        ]

        var documentID = 0
        func document(_ name: String, path: String? = nil, url: String? = nil, accepted: Bool = true) -> SOPDocument {
            documentID += 1
            let digest = SHA256.hash(data: Data((path ?? url ?? name).utf8))
            return SOPDocument(id: documentID, name: name, url: url.flatMap(URL.init(string:)), filePath: path,
                               accepted: accepted, sha256: digest.map { String(format: "%02x", $0) }.joined())
        }
        func roles(_ pairs: (Int, String)...) -> [Assignment] { pairs.map { Assignment(personID: $0.0, role: $0.1) } }

        let sops = [
            SOP(id: 1, name: "SOP-001 Probenahme Wasser", active: true,
                documents: [document("Probenahme Wasser, Rev. 3", path: "/srv/lucent/sop/SOP-001_r3.pdf"),
                            document("Probenahme Wasser, Rev. 2 (ersetzt)", path: "/srv/lucent/sop/SOP-001_r2.pdf", accepted: false)],
                people: roles((dorn, "Autor"), (ripley, "Prüfung"), (picard, "Freigabe"))),
            SOP(id: 2, name: "SOP-002 pH-Wert", active: true,
                documents: [document("pH-Wert, Rev. 2", path: "/srv/lucent/sop/SOP-002_r2.pdf")],
                people: roles((doe, "Autor"), (ripley, "Prüfung"), (picard, "Freigabe"))),
            SOP(id: 3, name: "SOP-003 Elektrische Leitfähigkeit", active: true,
                documents: [document("Elektrische Leitfähigkeit, Rev. 1", path: "/srv/lucent/sop/SOP-003_r1.pdf")],
                people: roles((doe, "Autor"), (ripley, "Prüfung"), (picard, "Freigabe"))),
            SOP(id: 4, name: "SOP-004 Anionen mittels IC", active: true,
                documents: [document("Anionen mittels IC, Rev. 4", path: "/srv/lucent/sop/SOP-004_r4.pdf"),
                            document("Gerätehandbuch IC-3", url: "https://docs.example.org/ic3/handbuch.pdf")],
                people: roles((doe, "Autor"), (ripley, "Prüfung"), (picard, "Freigabe"))),
            SOP(id: 5, name: "SOP-005 Metalle mittels ICP-MS", active: true,
                documents: [document("Metalle mittels ICP-MS, Rev. 2", path: "/srv/lucent/sop/SOP-005_r2.pdf"),
                            document("Entwurf Rev. 3", path: "/srv/lucent/sop/entwurf/SOP-005_r3.docx", accepted: false)],
                people: roles((picard, "Autor"), (ripley, "Prüfung"))),
            SOP(id: 6, name: "SOP-006 E. coli und coliforme Bakterien", active: true,
                documents: [document("Membranfiltration, Rev. 1", path: "/srv/lucent/sop/SOP-006_r1.pdf")],
                people: roles((ripley, "Autor"), (picard, "Freigabe"))),
            SOP(id: 7, name: "SOP-007 Feinstaub gravimetrisch", active: true,
                documents: [document("Feinstaub gravimetrisch, Rev. 2", path: "/srv/lucent/sop/SOP-007_r2.pdf")],
                people: roles((simpson, "Autor"), (doe, "Prüfung"), (picard, "Freigabe"))),
            SOP(id: 8, name: "SOP-008 Stickstoffdioxid", active: true,
                documents: [document("Stickstoffdioxid, Rev. 1", path: "/srv/lucent/sop/SOP-008_r1.pdf")],
                people: roles((simpson, "Autor"), (picard, "Freigabe"))),
            SOP(id: 9, name: "SOP-009 Datenfreigabe (Vier-Augen-Prinzip)", active: true,
                documents: [document("Datenfreigabe, Rev. 1", path: "/srv/lucent/sop/SOP-009_r1.pdf")],
                people: roles((ripley, "Autor"), (noobington, "Prüfung"), (picard, "Freigabe"))),
            SOP(id: 10, name: "SOP-010 Probenahme Luft", active: false,
                documents: [document("Entwurf", path: "/srv/lucent/sop/entwurf/SOP-010.docx", accepted: false)],
                people: roles((simpson, "Autor"))),
        ]

        let actions = [
            LabAction(id: 1, name: "Probenahme Wasser", standard: "DIN ISO 5667-5", iteration: 3, active: true,
                      description: "Entnahme der Probe und Messung der Wassertemperatur vor Ort.",
                      sopID: 1, deviceIDs: [11], people: roles((dorn, "Verantwortlich")), dependsOn: [], implies: [2]),
            LabAction(id: 2, name: "Sensorische Prüfung", standard: "DIN EN 1622", iteration: 1, active: true,
                      description: "Färbung und Geruch, direkt nach der Probenahme.",
                      sopID: 1, deviceIDs: [], people: roles((dorn, "Prüfer")), dependsOn: [1], implies: []),
            LabAction(id: 3, name: "pH-Wert", standard: "DIN EN ISO 10523", iteration: 2, active: true,
                      description: "Potentiometrische Messung mit Glaselektrode, Drei-Punkt-Kalibrierung.",
                      sopID: 2, deviceIDs: [1, 2], people: roles((doe, "Analyst"), (picard, "Verantwortlich")), dependsOn: [1], implies: []),
            LabAction(id: 4, name: "Elektrische Leitfähigkeit", standard: "DIN EN 27888", iteration: 1, active: true,
                      description: "Konduktometrische Messung mit Temperaturkompensation auf 25 °C.",
                      sopID: 3, deviceIDs: [3], people: roles((doe, "Analyst")), dependsOn: [1], implies: []),
            LabAction(id: 5, name: "Anionen (IC)", standard: "DIN EN ISO 10304-1", iteration: 4, active: true,
                      description: "Nitrat, Chlorid und Sulfat mittels Ionenchromatographie. Die Ionenbilanz wird mit der Leitfähigkeit plausibilisiert.",
                      sopID: 4, deviceIDs: [4], people: roles((doe, "Analyst"), (picard, "Verantwortlich")), dependsOn: [1], implies: [4]),
            LabAction(id: 6, name: "Metalle (ICP-MS)", standard: "DIN EN ISO 17294-2", iteration: 2, active: true,
                      description: "Stagnationsprobe S0. Eine Überschreitung wird mit einer Wiederholungsmessung bestätigt.",
                      sopID: 5, deviceIDs: [5], people: roles((picard, "Analyst"), (ripley, "Prüfer")), dependsOn: [1], implies: []),
            LabAction(id: 7, name: "E. coli und coliforme Bakterien", standard: "DIN EN ISO 9308-1", iteration: 1, active: true,
                      description: "Membranfiltration, Bebrütung 21 ± 3 h bei 36 °C.",
                      sopID: 6, deviceIDs: [6], people: roles((ripley, "Analyst")), dependsOn: [1], implies: []),
            LabAction(id: 8, name: "Feinstaub (gravimetrisch)", standard: "DIN EN 12341", iteration: 2, active: true,
                      description: "24-Stunden-Probenahme auf Filter, Wägung vor und nach der Beaufschlagung.",
                      sopID: 7, deviceIDs: [7, 8, 10], people: roles((simpson, "Probenehmer"), (doe, "Analyst")), dependsOn: [], implies: []),
            LabAction(id: 9, name: "Stickstoffdioxid", standard: "DIN EN 14211", iteration: 1, active: true,
                      description: "Chemilumineszenz, Tagesmittelwert.",
                      sopID: 8, deviceIDs: [9], people: roles((simpson, "Verantwortlich")), dependsOn: [], implies: []),
        ]

        let actionVariables = [
            ActionVariable(id: 1, actionID: 1, variableID: 1, unitID: 2, uncertainty: 0.2, uncertaintyClass: .absolute),
            ActionVariable(id: 2, actionID: 2, variableID: 15, unitID: nil, uncertainty: nil, uncertaintyClass: .absolute),
            ActionVariable(id: 3, actionID: 2, variableID: 16, unitID: nil, uncertainty: nil, uncertaintyClass: .absolute, upperLimit: 0),
            ActionVariable(id: 4, actionID: 3, variableID: 2, unitID: 1, uncertainty: 0.05, uncertaintyClass: .absolute,
                           decimals: 2, lowerLimit: 6.5, upperLimit: 9.5),
            ActionVariable(id: 5, actionID: 4, variableID: 3, unitID: 3, uncertainty: 2, uncertaintyClass: .relative,
                           calculation: "κ₂₅ = κ_T · f₂₅(T)", decimals: 0, upperLimit: 2790),
            ActionVariable(id: 6, actionID: 5, variableID: 4, unitID: 4, uncertainty: 5, uncertaintyClass: .relative, upperLimit: 50),
            ActionVariable(id: 7, actionID: 5, variableID: 5, unitID: 4, uncertainty: 5, uncertaintyClass: .relative, upperLimit: 250),
            ActionVariable(id: 8, actionID: 5, variableID: 6, unitID: 4, uncertainty: 5, uncertaintyClass: .relative, upperLimit: 250),
            ActionVariable(id: 9, actionID: 6, variableID: 7, unitID: 5, uncertainty: 10, uncertaintyClass: .relative, upperLimit: 10),
            ActionVariable(id: 10, actionID: 6, variableID: 8, unitID: 4, uncertainty: 8, uncertaintyClass: .relative, decimals: 2, upperLimit: 2),
            ActionVariable(id: 11, actionID: 6, variableID: 9, unitID: 5, uncertainty: 10, uncertaintyClass: .relative, upperLimit: 20),
            ActionVariable(id: 12, actionID: 7, variableID: 10, unitID: 7, uncertainty: nil, uncertaintyClass: .absolute, decimals: 0, upperLimit: 0),
            ActionVariable(id: 13, actionID: 7, variableID: 11, unitID: 7, uncertainty: nil, uncertaintyClass: .absolute, decimals: 0, upperLimit: 0),
            ActionVariable(id: 14, actionID: 8, variableID: 12, unitID: 6, uncertainty: 7, uncertaintyClass: .relative,
                           calculation: "c = (m₂ − m₁) / V", decimals: 0, upperLimit: 50),
            ActionVariable(id: 15, actionID: 8, variableID: 13, unitID: 6, uncertainty: 7, uncertaintyClass: .relative,
                           calculation: "c = (m₂ − m₁) / V", decimals: 0, upperLimit: 25),
            ActionVariable(id: 16, actionID: 9, variableID: 14, unitID: 6, uncertainty: 7.5, uncertaintyClass: .relative, decimals: 0, upperLimit: 40),
        ]

        // Collections: who samples what where, how often (days) and with which offset (days ago).
        struct Schedule {
            var spotID: Int? = nil
            var siteID: Int? = nil
            var matrixID: Int, classID: Int, every: Int, offset: Int, samplerID: Int
        }
        let schedules = [
            Schedule(spotID: 3, matrixID: 8, classID: 2, every: 7, offset: 1, samplerID: simpson),
            Schedule(spotID: 11, matrixID: 8, classID: 2, every: 7, offset: 2, samplerID: simpson),
            Schedule(spotID: 2, matrixID: 8, classID: 2, every: 14, offset: 5, samplerID: simpson),
            Schedule(spotID: 4, matrixID: 9, classID: 3, every: 14, offset: 3, samplerID: dorn),
            Schedule(spotID: 5, matrixID: 9, classID: 1, every: 14, offset: 10, samplerID: dorn),
            Schedule(spotID: 6, matrixID: 10, classID: 1, every: 7, offset: 0, samplerID: dorn),
            Schedule(spotID: 7, matrixID: 10, classID: 1, every: 7, offset: 4, samplerID: dorn),
            Schedule(spotID: 7, matrixID: 10, classID: 3, every: 28, offset: 6, samplerID: dorn),
            Schedule(spotID: 6, matrixID: 10, classID: 3, every: 28, offset: 20, samplerID: dorn),
            Schedule(spotID: 8, matrixID: 11, classID: 4, every: 14, offset: 2, samplerID: dorn),
            Schedule(spotID: 9, matrixID: 11, classID: 4, every: 14, offset: 9, samplerID: dorn),
            Schedule(spotID: 10, matrixID: 11, classID: 4, every: 7, offset: 3, samplerID: ripley),
            Schedule(siteID: 3, matrixID: 11, classID: 4, every: 28, offset: 12, samplerID: ripley),
        ]
        let horizon = 84

        var rng = SeededGenerator(seed: 0x1BC3_17E5)
        var drafts: [(schedule: Schedule, sampledAt: Date)] = []
        for schedule in schedules {
            for daysAgo in stride(from: schedule.offset, through: horizon, by: schedule.every) {
                let minutes = Int.random(in: 7 * 60...11 * 60, using: &rng)
                let sampledAt = calendar.date(byAdding: .minute, value: minutes - daysAgo * 24 * 60, to: today)!
                if sampledAt <= now { drafts.append((schedule, sampledAt)) }
            }
        }
        drafts.sort { $0.sampledAt < $1.sampledAt }

        let numbering = NumberingScheme.lucent
        let firstSequence = 3000
        var collections: [LabCollection] = []
        for (index, draft) in drafts.enumerated() {
            collections.append(LabCollection(
                id: index + 1, name: numbering.identifier(for: firstSequence + index)!,
                matrixID: draft.schedule.matrixID, classID: draft.schedule.classID,
                spotID: draft.schedule.spotID, siteID: draft.schedule.siteID,
                sampledAt: draft.sampledAt, sampledByID: draft.schedule.samplerID))
        }

        // Values: older collections are complete and accepted, recent ones still in progress.
        let actionsByID = Dictionary(uniqueKeysWithValues: actions.map { ($0.id, $0) })
        var values: [LabValue] = []
        for collection in collections {
            let age = now.timeIntervalSince(collection.sampledAt) / 86_400
            let progress = 1 - age / Double(horizon)  // 0 = oldest, 1 = now
            let planned = classActions[collection.classID] ?? []

            let actionsDone: Int
            var acceptedActions: Int
            switch age {
            case 10...:
                actionsDone = planned.count; acceptedActions = planned.count
            case 4..<10:
                actionsDone = planned.count
                acceptedActions = rng.chance(0.5) ? planned.count : planned.count / 2
            case 1.5..<4:
                actionsDone = rng.chance(0.4) ? planned.count : Int.random(in: 1...max(1, planned.count - 1), using: &rng)
                acceptedActions = 0
            default:
                actionsDone = rng.chance(0.5) ? 0 : 1
                acceptedActions = 0
            }

            for (actionIndex, actionID) in planned.prefix(actionsDone).enumerated() {
                let action = actionsByID[actionID]!
                let measuredAt = min(now, collection.sampledAt.addingTimeInterval(
                    Double(actionIndex) * 5 * 3600 + Double.random(in: 0...3600, using: &rng)))
                var deviceID = action.deviceIDs.first
                if actionID == 8 { deviceID = collection.spotID == 11 ? 8 : 7 }
                let personID = action.people.first { $0.role == "Analyst" }?.personID
                    ?? action.people.first?.personID ?? collection.sampledByID

                for av in actionVariables where av.actionID == actionID {
                    let reading = mockReading(av, collection: collection, progress: progress, rng: &rng)
                    let accepted = actionIndex < acceptedActions
                    values.append(LabValue(id: values.count + 1, collectionID: collection.id, actionVariableID: av.id,
                                           repetition: 1, reading: reading, accepted: accepted,
                                           measuredAt: measuredAt, personID: personID, deviceID: deviceID))
                    // A lead value above the limit is confirmed by a repetition.
                    if av.id == 9, case .decimal(let lead) = reading, lead > 10 {
                        let repeated = (lead * rng.normal(1, 0.04) * 10).rounded() / 10
                        values.append(LabValue(id: values.count + 1, collectionID: collection.id, actionVariableID: av.id,
                                               repetition: 2, reading: .decimal(repeated), accepted: accepted,
                                               measuredAt: measuredAt.addingTimeInterval(3 * 3600),
                                               personID: personID, deviceID: deviceID))
                    }
                }
            }
        }

        let tasks = [
            LabTask(id: 1, request: "pH-Meter Lab 1 kalibrieren", description: "Drei-Punkt-Kalibrierung mit Puffer 4, 7 und 10, Steilheit dokumentieren.",
                    assignerID: picard, assigneeID: doe, deadline: day(-1), done: false),
            LabTask(id: 2, request: "Blei an Zapfstelle 2.14 nachprüfen", description: "Stagnationsproben S0 und S1 nehmen, Hausinstallation im Altbau prüfen.",
                    assignerID: ripley, assigneeID: dorn, deadline: day(2), done: false),
            LabTask(id: 3, request: "Offene Kollektionen freigeben", description: "Vier-Augen-Prinzip nach SOP-009.",
                    assignerID: picard, assigneeID: ripley, deadline: day(1, hour: 12), done: false),
            LabTask(id: 4, request: "SOP-005 überarbeiten", description: "Entwurf Rev. 3 mit den neuen Kalibrierstandards abschließen.",
                    assignerID: ripley, assigneeID: picard, deadline: day(9), done: false),
            LabTask(id: 5, request: "Feinstaubfilter im Messcontainer wechseln", description: "Filterkassetten für 14 Tage einlegen, Blindfilter wiegen.",
                    assignerID: doe, assigneeID: simpson, deadline: day(0, hour: 18), done: false),
            LabTask(id: 6, request: "Nitrat-Trend an GWM 12 melden", description: "Seit Wochen über 50 mg/L. Bericht an die Wasserbehörde.",
                    assignerID: picard, assigneeID: picard, deadline: day(5), done: false),
            LabTask(id: 7, request: "Ringversuch Anionen anmelden", description: "Anmeldeschluss beachten.",
                    assignerID: picard, assigneeID: doe, deadline: day(21), done: false),
            LabTask(id: 8, request: "lucentLIMS an lucentBASE anbinden", description: "Die Mock-Daten durch die echte Datenbank ersetzen.",
                    assignerID: noobington, assigneeID: noobington, deadline: day(30), done: false),
            LabTask(id: 9, request: "Temperaturlogger Brutschrank auslesen", description: "",
                    assignerID: ripley, assigneeID: ripley, deadline: day(-4), done: true),
            LabTask(id: 10, request: "Probenflaschen nachbestellen", description: "500 mL PE und 250 mL Glas, steril.",
                    assignerID: dorn, assigneeID: noobington, deadline: day(-6), done: true),
        ]

        let messages = [
            Message(id: 1, senderID: picard, receiverID: noobington, subject: "Freigaberechte für Ellen",
                    body: "Kannst du Ellen die Rechte für die Freigabe von Kollektionen geben? Sie übernimmt ab Montag die QS.",
                    read: false, sentAt: now.addingTimeInterval(-2 * 3600)),
            Message(id: 2, senderID: ripley, receiverID: noobington, subject: "Nitrat an GWM 12",
                    body: "Der Nitratwert an GWM 12 liegt über 50 mg/L. Kannst du mir die Zeitreihe exportieren?",
                    read: false, sentAt: now.addingTimeInterval(-5 * 3600)),
            Message(id: 3, senderID: simpson, receiverID: noobington, subject: "Messcontainer",
                    body: "Filterwechsel ist erledigt. Die Donuts im Pausenraum leider auch.",
                    read: true, sentAt: now.addingTimeInterval(-26 * 3600)),
            Message(id: 4, senderID: doe, receiverID: noobington, subject: "IC-3 wieder online",
                    body: "Die Trennsäule ist getauscht, die Anionen laufen wieder.",
                    read: true, sentAt: now.addingTimeInterval(-3 * 86_400)),
        ]

        return LabData(
            organizations: organizations, people: people, crs: crs, sites: sites, spots: spots,
            matrices: matrices, collectionClasses: collectionClasses, classActions: classActions,
            dimensions: dimensions, units: units, variables: variables, devices: devices, sops: sops,
            actions: actions, actionVariables: actionVariables, collections: collections, values: values,
            tasks: tasks, messages: messages)
    }

    /// A plausible reading for a variable at a spot. `progress` runs from 0 (oldest) to 1 (now).
    private static func mockReading(_ av: ActionVariable, collection: LabCollection, progress: Double,
                                    rng: inout SeededGenerator) -> Reading {
        let spot = collection.spotID
        let matrix = collection.matrixID
        let value: Double
        switch av.id {
        case 1: value = matrix == 11 ? rng.normal(11.5, 0.5) : matrix == 9 ? rng.normal(17, 2) : rng.normal(12, 1.2)
        case 2: return .text(rng.chance(0.93) ? "farblos" : "schwach gelblich")
        case 3: return .boolean(rng.chance(0.04))
        case 4: value = matrix == 11 ? rng.normal(7.15, 0.1) : rng.normal(7.6, 0.08)
        case 5: value = spot == 10 ? rng.normal(900, 50) : matrix == 11 ? rng.normal(820, 40) : rng.normal(640, 15)
        case 6:
            switch spot {
            case 10: value = 38 + 18 * progress + rng.normal(0, 2)
            case 8: value = rng.normal(21, 1.5)
            case 9: value = rng.normal(17, 1.5)
            case nil: value = rng.normal(30, 3)
            default: value = rng.normal(15, 1.2)
            }
        case 7: value = spot == 10 ? rng.normal(70, 6) : rng.normal(45, 4)
        case 8: value = rng.normal(62, 5)
        case 9: value = spot == 4 ? (progress > 0.8 ? rng.normal(12.5, 1) : rng.normal(7.5, 2.8)) : rng.normal(0.8, 0.3)
        case 10: value = spot == 4 ? rng.normal(0.45, 0.12) : rng.normal(0.05, 0.02)
        case 11: value = rng.normal(2.5, 0.8)
        case 12: value = rng.chance(0.03) ? Double(Int.random(in: 1...3, using: &rng)) : 0
        case 13: value = rng.chance(0.06) ? Double(Int.random(in: 1...6, using: &rng)) : 0
        case 14: value = spot == 11 ? rng.normal(31, 11) : spot == 3 ? rng.normal(19, 6) : rng.normal(21, 7)
        case 15: value = spot == 11 ? rng.normal(19, 6) : rng.normal(12, 4)
        case 16: value = spot == 11 ? rng.normal(36, 7) : spot == 3 ? rng.normal(18, 5) : rng.normal(21, 5)
        default: value = 0
        }
        let scale = pow(10, Double(av.decimals))
        return .decimal((max(value, av.decimals == 0 ? 0 : 0.1) * scale).rounded() / scale)
    }
}
