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

/// Mock data in lucentBASE's model, with the same people, places, actions, parameters,
/// documents and thresholds as lucentAPI's demo data (the system user is Booney Noobington,
/// lucentAndShiny's demo person). Dates are relative to `now`, so the dashboard looks current.
enum MockData {
    static let system = 1, doe = 2, dorn = 3, simpson = 4, picard = 5, ripley = 6
    static let samplingTime = 1

    static let collectionClasses = ["spot sample", "mixed sample", "collective sample", "time series",
                                    "free measurement"]

    static func make(now: Date = .now, calendar: Calendar = .current) -> LabData {
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int, hour: Int = 16) -> Date {
            calendar.date(byAdding: .hour, value: offset * 24 + hour, to: today)!
        }
        func date(_ text: String) -> Date { try! Date(text, strategy: .iso8601.year().month().day()) }
        func sha256(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
        func roles(_ pairs: (Int, String)...) -> [Assignment] { pairs.map { Assignment(personID: $0.0, role: $0.1) } }

        let organizations = [
            Organization(id: 1, name: "Redhsoft.org", shorthand: "redhsoft"),
            Organization(id: 2, name: "Umweltlabor Lucent", shorthand: "Lucent"),
            Organization(id: 3, name: "Ionic Instruments GmbH", shorthand: "Ionic"),
            Organization(id: 4, name: "Spectra Analytik AG", shorthand: "Spectra"),
            Organization(id: 5, name: "Klarsicht Messtechnik KG", shorthand: "Klarsicht"),
            Organization(id: 6, name: "Aerosol Systems GmbH", shorthand: "Aerosol"),
        ]

        let people = [
            Person(id: system, givenName: "Booney", surname: "Noobington", linuxUser: "grindel", organizationID: 1, position: "Administration"),
            Person(id: doe, givenName: "John", surname: "Doe", linuxUser: "jd", organizationID: 2, position: "Analytik"),
            Person(id: dorn, givenName: "Michael", surname: "Dorn", linuxUser: "worf", organizationID: 2, position: "Probenahme"),
            Person(id: simpson, givenName: "Homer", surname: "Simpson", linuxUser: "s7e23", organizationID: 2, position: "Luftmessnetz"),
            Person(id: picard, givenName: "Jean Luc", surname: "Picard", linuxUser: "p47at", organizationID: 2, position: "Laborleitung"),
            Person(id: ripley, givenName: "Ellen", surname: "Ripley", linuxUser: "xx121", organizationID: 2, position: "Qualitätssicherung"),
        ]

        let crs = [CRS(id: 1, epsg: 4326, name: "WGS 84")]

        let sites = [
            Site(id: 1, name: "Laborstraße", description: "Labor- und Verwaltungsgebäude",
                 address: Address(street: "Laborstraße", houseNumber: "4", zip: "76131", district: "Oststadt", city: "Karlsruhe"),
                 border: [.init(latitude: 49.0103, longitude: 8.4102), .init(latitude: 49.0106, longitude: 8.4139),
                          .init(latitude: 49.0088, longitude: 8.4145), .init(latitude: 49.0084, longitude: 8.4108)],
                 crsID: 1),
            Site(id: 2, name: "Wasserwerk Ost", description: "Fassungsgelände, Brunnen B3 und B7",
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
            Matrix(id: 1, name: "Luft", description: "Außen- oder Innenluft"),
            Matrix(id: 2, name: "Leitungswasser", description: "Aus der Hausinstallation"),
            Matrix(id: 3, name: "Trinkwasser", description: "Gemäß Trinkwasserverordnung"),
            Matrix(id: 4, name: "Grundwasser", description: "Aus Brunnen und Messstellen"),
        ]

        let dimensions = [
            PhysicalDimension(id: 1, name: "Temperatur", description: "Thermodynamische Temperatur"),
            PhysicalDimension(id: 2, name: "Elektrische Leitfähigkeit", description: "Leitwert pro Länge"),
            PhysicalDimension(id: 3, name: "Massenkonzentration", description: "Masse pro Volumen"),
            PhysicalDimension(id: 4, name: "Anzahlkonzentration", description: "Anzahl pro Volumen, z. B. KBE"),
        ]

        let units = [
            LabUnit(id: 1, name: "Grad Celsius", notations: ["°C"], dimensionID: 1),
            LabUnit(id: 2, name: "Mikrosiemens pro Zentimeter", notations: ["µS/cm", "µS cm⁻¹"], dimensionID: 2),
            LabUnit(id: 3, name: "Milligramm pro Liter", notations: ["mg/L", "mg l⁻¹", "ppm"], dimensionID: 3),
            LabUnit(id: 4, name: "Mikrogramm pro Liter", notations: ["µg/L", "µg l⁻¹", "ppb"], dimensionID: 3),
            LabUnit(id: 5, name: "Mikrogramm pro Kubikmeter", notations: ["µg/m³", "µg m⁻³"], dimensionID: 3),
            LabUnit(id: 6, name: "KBE pro 100 Milliliter", notations: ["KBE/100 mL", "CFU/100 mL"], dimensionID: 4),
        ]

        let parameters = [
            Parameter(id: samplingTime, name: "Probenahmezeitpunkt", description: "Wann die Probe genommen wurde", valueClass: .datetime),
            Parameter(id: 2, name: "Temperatur", description: "Wassertemperatur bei der Probenahme", unitID: 1, valueClass: .decimal),
            Parameter(id: 3, name: "Färbung", description: "Visuelle Prüfung", valueClass: .text),
            Parameter(id: 4, name: "Geruch auffällig", description: "Olfaktorische Prüfung", valueClass: .boolean),
            Parameter(id: 5, name: "pH-Wert", description: "Negativer dekadischer Logarithmus der Oxoniumaktivität", valueClass: .decimal),
            Parameter(id: 6, name: "Elektrische Leitfähigkeit", description: "Bezogen auf 25 °C", unitID: 2, valueClass: .decimal),
            Parameter(id: 7, name: "Nitrat", description: "NO₃⁻", unitID: 3, valueClass: .decimal),
            Parameter(id: 8, name: "Chlorid", description: "Cl⁻", unitID: 3, valueClass: .decimal),
            Parameter(id: 9, name: "Sulfat", description: "SO₄²⁻", unitID: 3, valueClass: .decimal),
            Parameter(id: 10, name: "Blei", description: "Pb, gesamt", unitID: 4, valueClass: .decimal),
            Parameter(id: 11, name: "Kupfer", description: "Cu, gesamt", unitID: 3, valueClass: .decimal),
            Parameter(id: 12, name: "Nickel", description: "Ni, gesamt", unitID: 4, valueClass: .decimal),
            Parameter(id: 13, name: "Escherichia coli", description: "Fäkalindikator", unitID: 6, valueClass: .decimal),
            Parameter(id: 14, name: "Coliforme Bakterien", description: "Hygieneindikator", unitID: 6, valueClass: .decimal),
            Parameter(id: 15, name: "Feinstaub PM10", description: "Partikel ≤ 10 µm, Tagesmittel", unitID: 5, valueClass: .decimal),
            Parameter(id: 16, name: "Feinstaub PM2,5", description: "Partikel ≤ 2,5 µm, Tagesmittel", unitID: 5, valueClass: .decimal),
            Parameter(id: 17, name: "Stickstoffdioxid", description: "NO₂, Tagesmittel", unitID: 5, valueClass: .decimal),
        ]

        let sop = "/srv/lucent/sop/", law = "https://www.gesetze-im-internet.de/"
        let documents: [Document] = [
            (1, "SOP-001 Probenahme Wasser", sop + "SOP-001_r3.pdf", nil, true),
            (2, "SOP-002 pH-Wert", sop + "SOP-002_r2.pdf", nil, true),
            (3, "SOP-003 Leitfähigkeit", sop + "SOP-003_r1.pdf", nil, true),
            (4, "SOP-004 Anionen (IC)", sop + "SOP-004_r4.pdf", nil, true),
            (5, "SOP-005 Metalle (ICP-MS)", sop + "SOP-005_r2.pdf", nil, true),
            (6, "SOP-005 Entwurf Rev. 3", sop + "entwurf/SOP-005_r3.docx", nil, false),
            (7, "SOP-006 Mikrobiologie", sop + "SOP-006_r1.pdf", nil, true),
            (8, "SOP-007 Feinstaub", sop + "SOP-007_r2.pdf", nil, true),
            (9, "SOP-008 Stickstoffdioxid", sop + "SOP-008_r1.pdf", nil, true),
            (10, "SOP-009 Datenfreigabe", sop + "SOP-009_r1.pdf", nil, true),
            (11, "Gerätehandbuch IC-3", nil, "https://docs.example.org/ic3/handbuch.pdf", true),
            (12, "Trinkwasserverordnung (TrinkwV)", nil, law + "trinkwv_2023/", true),
            (13, "Grundwasserverordnung (GrwV)", nil, law + "grwv_2010/", true),
            (14, "39. BImSchV (Luftqualität)", nil, law + "bimschv_39/", true),
        ].map { (id: Int, name: String, path: String?, url: String?, accepted: Bool) in
            Document(id: id, name: name, url: url.flatMap(URL.init(string:)), filePath: path, accepted: accepted,
                     sha256: sha256(path ?? url ?? name))
        }

        let thresholds: [Threshold] = [
            (4, 12, nil, 0, "Ohne anormale Veränderung"), (5, 12, 6.5, 9.5, "Anlage 3"), (6, 12, nil, 2790, "Anlage 3"),
            (7, 12, nil, 50, "Anlage 2 Teil I"), (8, 12, nil, 250, "Anlage 3"), (9, 12, nil, 250, "Anlage 3"),
            (10, 12, nil, 10, "Anlage 2 Teil II"), (11, 12, nil, 2, "Anlage 2 Teil II"), (12, 12, nil, 20, "Anlage 2 Teil II"),
            (13, 12, nil, 0, "Anlage 1"), (14, 12, nil, 0, "Anlage 3"),
            (7, 13, nil, 50, "Schwellenwert Anlage 2"), (8, 13, nil, 250, "Schwellenwert Anlage 2"),
            (9, 13, nil, 250, "Schwellenwert Anlage 2"), (10, 13, nil, 10, "Schwellenwert Anlage 2"),
            (15, 14, nil, 50, "Tagesgrenzwert"), (16, 14, nil, 25, "Jahresgrenzwert"), (17, 14, nil, 40, "Jahresgrenzwert"),
        ].enumerated().map { index, row in
            let (parameterID, documentID, lower, upper, description): (Int, Int, Double?, Double?, String) = row
            return Threshold(id: index + 1, parameterID: parameterID, documentID: documentID, lowerLimit: lower,
                             upperLimit: upper, description: description)
        }

        let strict = { (id: Int) in Dependency(actionID: id, kind: .strict, description: "Erst nach der Probenahme") }
        let actions = [
            LabAction(id: 1, name: "Probenahme Wasser", iteration: date("2024-03-01"), active: true,
                      description: "Entnahme nach DIN ISO 5667-5, Temperatur vor Ort.", documentIDs: [1, 12],
                      deviceIDs: [11], people: roles((dorn, "worker"), (picard, "manager")), dependencies: []),
            LabAction(id: 2, name: "Sensorische Prüfung", iteration: date("2023-06-01"), active: true,
                      description: "Färbung und Geruch nach DIN EN 1622.", documentIDs: [1, 12], deviceIDs: [],
                      people: roles((dorn, "worker")), dependencies: [strict(1)]),
            LabAction(id: 3, name: "pH-Wert", iteration: date("2024-09-15"), active: true,
                      description: "DIN EN ISO 10523, Glaselektrode, Drei-Punkt-Kalibrierung.", documentIDs: [2, 12],
                      deviceIDs: [1, 2], people: roles((doe, "worker"), (picard, "manager"), (ripley, "auditor")),
                      dependencies: [strict(1)]),
            LabAction(id: 4, name: "Elektrische Leitfähigkeit", iteration: date("2023-01-10"), active: true,
                      description: "DIN EN 27888, kompensiert auf 25 °C.", documentIDs: [3, 12], deviceIDs: [3],
                      people: roles((doe, "worker")), dependencies: [strict(1)]),
            LabAction(id: 5, name: "Anionen (IC)", iteration: date("2025-02-01"), active: true,
                      description: "Nitrat, Chlorid und Sulfat nach DIN EN ISO 10304-1.", documentIDs: [4, 11, 12, 13],
                      deviceIDs: [4], people: roles((doe, "worker"), (picard, "manager")),
                      dependencies: [strict(1), Dependency(actionID: 4, kind: .possibility,
                                                           description: "Ionenbilanz mit der Leitfähigkeit plausibilisieren")]),
            LabAction(id: 6, name: "Metalle (ICP-MS)", iteration: date("2024-11-20"), active: true,
                      description: "DIN EN ISO 17294-2, Stagnationsprobe S0. Überschreitungen werden wiederholt.",
                      documentIDs: [5, 6, 12, 13], deviceIDs: [5], people: roles((picard, "worker"), (ripley, "auditor")),
                      dependencies: [strict(1)]),
            LabAction(id: 7, name: "E. coli und coliforme Bakterien", iteration: date("2023-05-05"), active: true,
                      description: "Membranfiltration nach DIN EN ISO 9308-1, 21 h bei 36 °C.", documentIDs: [7, 12],
                      deviceIDs: [6], people: roles((ripley, "worker")), dependencies: [strict(1)]),
            LabAction(id: 8, name: "Feinstaub (gravimetrisch)", iteration: date("2024-04-01"), active: true,
                      description: "DIN EN 12341, 24-Stunden-Probenahme auf Filter.", documentIDs: [8, 14],
                      deviceIDs: [7, 8, 10], people: roles((simpson, "worker"), (doe, "worker")), dependencies: []),
            LabAction(id: 9, name: "Stickstoffdioxid", iteration: date("2023-09-01"), active: true,
                      description: "Chemilumineszenz nach DIN EN 14211, Tagesmittel.", documentIDs: [9, 14], deviceIDs: [9],
                      people: roles((simpson, "worker")), dependencies: []),
            LabAction(id: 10, name: "pH-Wert", iteration: date("2021-02-01"), active: false,
                      description: "Vorgängerversion mit Zwei-Punkt-Kalibrierung.", documentIDs: [2], deviceIDs: [2],
                      people: roles((doe, "worker")), dependencies: []),
        ]

        let devices = [
            Device(id: 1, name: "pH-Meter Lab 1", number: 2207114, manufacturerID: 3, operatorID: 2, active: true),
            Device(id: 2, name: "pH-Meter Lab 2", number: 1903027, manufacturerID: 3, operatorID: 2, active: false),
            Device(id: 3, name: "Leitfähigkeitsmessgerät LF 4", number: 2105033, manufacturerID: 3, operatorID: 2, active: true),
            Device(id: 4, name: "Ionenchromatograph IC-3", number: 98, manufacturerID: 4, operatorID: 2, active: true),
            Device(id: 5, name: "ICP-MS Q2", number: 4411, manufacturerID: 4, operatorID: 2, active: true),
            Device(id: 6, name: "Brutschrank 36 °C", number: 2, manufacturerID: 5, operatorID: 2, active: true),
            Device(id: 7, name: "Feinstaubsammler LVS-3", number: 1187, manufacturerID: 6, operatorID: 2, active: true),
            Device(id: 8, name: "Feinstaubsammler LVS-3", number: 1192, manufacturerID: 6, operatorID: 2, active: true),
            Device(id: 9, name: "NO₂-Analysator", number: 500221, manufacturerID: 6, operatorID: 2, active: true),
            Device(id: 10, name: "Feinwaage XS205", number: 205778, manufacturerID: 5, operatorID: 2, active: true),
            Device(id: 11, name: "Einstichthermometer", number: 42, manufacturerID: 5, operatorID: 2, active: true),
        ]

        let effects: [Effect] = [
            (1, 1, 1, nil, .absolute, nil), (2, 1, 2, 0.2, .absolute, nil), (3, 2, 3, nil, .absolute, nil),
            (4, 2, 4, nil, .absolute, nil), (5, 3, 5, 0.05, .absolute, nil), (6, 4, 6, 2, .relative, "κ25 = κT · f25(T)"),
            (7, 5, 7, 5, .relative, nil), (8, 5, 8, 5, .relative, nil), (9, 5, 9, 5, .relative, nil),
            (10, 6, 10, 10, .relative, nil), (11, 6, 11, 8, .relative, nil), (12, 6, 12, 10, .relative, nil),
            (13, 7, 13, nil, .absolute, nil), (14, 7, 14, nil, .absolute, nil), (15, 8, 1, nil, .absolute, nil),
            (16, 8, 15, 7, .relative, "c = (m2 − m1) / V"), (17, 8, 16, 7, .relative, "c = (m2 − m1) / V"),
            (18, 9, 17, 7.5, .relative, nil), (19, 10, 5, 0.1, .absolute, nil),
        ].map { (id: Int, action: Int, parameter: Int, uncertainty: Double?, kind: UncertaintyClass, calculation: String?) in
            Effect(id: id, actionID: action, parameterID: parameter, uncertainty: uncertainty, uncertaintyClass: kind,
                   calculation: calculation)
        }

        let coefficients = [Coefficient(id: 1, effectIDs: [6, 2], description: "Die Leitfähigkeit wird auf die Probentemperatur bezogen")]

        // Collections: who samples what where, with which actions, how often (days), first offset (days ago).
        struct Schedule {
            var spotID: Int? = nil
            var siteID: Int? = nil
            var matrixID: Int, collectionClass: String, actions: [Int], every: Int, offset: Int, samplerID: Int
        }
        let waterRoutine = [1, 2, 3, 4, 7], waterFull = [1, 2, 3, 4, 5, 6, 7], groundWater = [1, 3, 4, 5], air = [8, 9]
        let schedules = [
            Schedule(spotID: 3, matrixID: 1, collectionClass: "time series", actions: air, every: 7, offset: 1, samplerID: simpson),
            Schedule(spotID: 11, matrixID: 1, collectionClass: "time series", actions: air, every: 7, offset: 2, samplerID: simpson),
            Schedule(spotID: 2, matrixID: 1, collectionClass: "time series", actions: air, every: 14, offset: 5, samplerID: simpson),
            Schedule(spotID: 4, matrixID: 2, collectionClass: "spot sample", actions: waterFull, every: 14, offset: 3, samplerID: dorn),
            Schedule(spotID: 5, matrixID: 2, collectionClass: "spot sample", actions: waterRoutine, every: 14, offset: 10, samplerID: dorn),
            Schedule(spotID: 6, matrixID: 3, collectionClass: "spot sample", actions: waterRoutine, every: 7, offset: 0, samplerID: dorn),
            Schedule(spotID: 7, matrixID: 3, collectionClass: "spot sample", actions: waterRoutine, every: 7, offset: 4, samplerID: dorn),
            Schedule(spotID: 7, matrixID: 3, collectionClass: "spot sample", actions: waterFull, every: 28, offset: 6, samplerID: dorn),
            Schedule(spotID: 8, matrixID: 4, collectionClass: "spot sample", actions: groundWater, every: 14, offset: 2, samplerID: dorn),
            Schedule(spotID: 9, matrixID: 4, collectionClass: "spot sample", actions: groundWater, every: 14, offset: 9, samplerID: dorn),
            Schedule(spotID: 10, matrixID: 4, collectionClass: "spot sample", actions: groundWater, every: 7, offset: 3, samplerID: ripley),
            Schedule(siteID: 3, matrixID: 4, collectionClass: "mixed sample", actions: groundWater, every: 28, offset: 12, samplerID: ripley),
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

        let workers = [1: dorn, 2: dorn, 3: doe, 4: doe, 5: doe, 6: picard, 7: ripley, 8: doe, 9: simpson]
        let numbering = NumberingScheme.lucent
        var collections: [LabCollection] = []
        var values: [LabValue] = []
        var rawValues: [RawValue] = []
        for (index, draft) in drafts.enumerated() {
            let schedule = draft.schedule
            let collection = LabCollection(
                id: index + 1, name: numbering.identifier(for: 3000 + index + 1)!, matrixID: schedule.matrixID,
                collectionClass: schedule.collectionClass, spotID: schedule.spotID, siteID: schedule.siteID,
                sampledAt: draft.sampledAt, sampledByID: schedule.samplerID)
            collections.append(collection)
            var slots: [Int: Int] = [:]
            for effect in effects where schedule.actions.contains(effect.actionID) {
                values.append(LabValue(id: values.count + 1, collectionID: collection.id, effectID: effect.id))
                slots[effect.id] = values.count
            }

            let age = now.timeIntervalSince(draft.sampledAt) / 86_400
            let progress = 1 - age / Double(horizon)
            let planned = schedule.actions
            let actionsDone: Int, acceptedActions: Int
            switch age {
            case 10...: (actionsDone, acceptedActions) = (planned.count, planned.count)
            case 4..<10: (actionsDone, acceptedActions) = (planned.count, rng.chance(0.5) ? planned.count : planned.count / 2)
            case 1.5..<4: (actionsDone, acceptedActions) = (rng.chance(0.4) ? planned.count : Int.random(in: 1...max(1, planned.count - 1), using: &rng), 0)
            default: (actionsDone, acceptedActions) = (rng.chance(0.5) ? 0 : 1, 0)
            }

            for (actionIndex, actionID) in planned.prefix(actionsDone).enumerated() {
                let measuredAt = min(now, draft.sampledAt.addingTimeInterval(
                    Double(actionIndex) * 5 * 3600 + Double.random(in: 0...3600, using: &rng)))
                let action = actions.first { $0.id == actionID }!
                var deviceID = action.deviceIDs.first
                if actionID == 8 { deviceID = schedule.spotID == 11 ? 8 : 7 }
                for effect in effects where effect.actionID == actionID {
                    let parameter = parameters.first { $0.id == effect.parameterID }!
                    var readings: [Reading]
                    var t = measuredAt, person = workers[actionID]!
                    if parameter.id == samplingTime {
                        readings = [.datetime(draft.sampledAt)]
                        t = draft.sampledAt
                        person = schedule.samplerID
                    } else {
                        readings = [mockReading(parameter.id, spotID: schedule.spotID, progress: progress, rng: &rng)]
                        // A lead value above the limit is measured again.
                        if parameter.id == 10, case .decimal(let lead) = readings[0], lead > 10 {
                            readings.append(.decimal((lead * rng.normal(1, 0.04) * 10).rounded() / 10))
                        }
                    }
                    for (repetition, reading) in readings.enumerated() {
                        rawValues.append(RawValue(
                            id: rawValues.count + 1, valueID: slots[effect.id]!, t: t.addingTimeInterval(Double(repetition) * 3 * 3600),
                            personID: person, deviceID: deviceID, unitID: parameter.unitID, reading: reading,
                            accepted: actionIndex < acceptedActions))
                    }
                }
            }
        }

        let tasks = [
            LabTask(id: 1, request: "pH-Meter Lab 1 kalibrieren", description: "Drei-Punkt-Kalibrierung mit Puffer 4, 7 und 10.",
                    assignerID: picard, assigneeID: doe, deadline: day(-1), done: false),
            LabTask(id: 2, request: "Blei an Zapfstelle 2.14 nachprüfen", description: "Stagnationsproben S0 und S1 nehmen.",
                    assignerID: ripley, assigneeID: dorn, deadline: day(2), done: false),
            LabTask(id: 3, request: "Offene Kollektionen freigeben", description: "Vier-Augen-Prinzip nach SOP-009.",
                    assignerID: picard, assigneeID: ripley, deadline: day(1, hour: 12), done: false),
            LabTask(id: 4, request: "Nitrat-Trend an GWM 12 melden", description: "Bericht an die Wasserbehörde.",
                    assignerID: picard, assigneeID: picard, deadline: day(5), done: false),
            LabTask(id: 5, request: "Feinstaubfilter wechseln", description: "Filterkassetten für 14 Tage einlegen.",
                    assignerID: doe, assigneeID: simpson, deadline: day(0, hour: 18), done: false),
            LabTask(id: 6, request: "lucentLIMS an lucentAPI anbinden", description: "Die Mock-Daten durch die API ersetzen.",
                    assignerID: system, assigneeID: system, deadline: day(30), done: false),
            LabTask(id: 7, request: "Probenflaschen nachbestellen", description: "500 mL PE und 250 mL Glas, steril.",
                    assignerID: dorn, assigneeID: system, deadline: day(-6), done: true),
        ]

        let messages = [
            Message(id: 1, senderID: picard, receiverID: system, subject: "Freigaberechte für Ellen",
                    body: "Kannst du Ellen die Rechte für die Freigabe von Kollektionen geben? Sie übernimmt ab Montag die QS.",
                    read: false, sentAt: now.addingTimeInterval(-2 * 3600)),
            Message(id: 2, senderID: ripley, receiverID: system, subject: "Nitrat an GWM 12",
                    body: "Der Nitratwert an GWM 12 liegt über 50 mg/L. Kannst du mir die Zeitreihe exportieren?",
                    read: false, sentAt: now.addingTimeInterval(-5 * 3600)),
            Message(id: 3, senderID: simpson, receiverID: system, subject: "Messcontainer",
                    body: "Filterwechsel ist erledigt. Die Donuts im Pausenraum leider auch.",
                    read: true, sentAt: now.addingTimeInterval(-26 * 3600)),
        ]

        return LabData(
            organizations: organizations, people: people, crs: crs, sites: sites, spots: spots, matrices: matrices,
            collectionClasses: collectionClasses, dimensions: dimensions, units: units, parameters: parameters,
            devices: devices, documents: documents, actions: actions, effects: effects, thresholds: thresholds,
            coefficients: coefficients, collections: collections, values: values, rawValues: rawValues, tasks: tasks,
            messages: messages, samplingTimeParameterID: samplingTime)
    }

    /// A plausible reading of a parameter at a spot. `progress` runs from 0 (oldest) to 1 (now).
    private static func mockReading(_ parameterID: Int, spotID spot: Int?, progress: Double,
                                    rng: inout SeededGenerator) -> Reading {
        let ground = spot == 8 || spot == 9 || spot == 10 || spot == nil
        let value: Double, decimals: Double
        switch parameterID {
        case 2: (value, decimals) = (rng.normal(ground ? 11.5 : 14, 1), 1)
        case 3: return .text(rng.chance(0.93) ? "farblos" : "schwach gelblich")
        case 4: return .boolean(rng.chance(0.04))
        case 5: (value, decimals) = (rng.normal(ground ? 7.15 : 7.6, 0.08), 2)
        case 6: (value, decimals) = (rng.normal(spot == 10 ? 880 : 650, 30), 0)
        case 7: (value, decimals) = (spot == 10 ? 38 + 18 * progress + rng.normal(0, 2) : rng.normal(ground ? 20 : 15, 1.5), 1)
        case 8: (value, decimals) = (rng.normal(45, 4), 1)
        case 9: (value, decimals) = (rng.normal(62, 5), 1)
        case 10: (value, decimals) = (spot == 4 ? (progress > 0.8 ? rng.normal(12.5, 1) : rng.normal(7.5, 2.8)) : rng.normal(0.8, 0.3), 1)
        case 11: (value, decimals) = (spot == 4 ? rng.normal(0.45, 0.12) : rng.normal(0.05, 0.02), 2)
        case 12: (value, decimals) = (rng.normal(2.5, 0.8), 1)
        case 13: (value, decimals) = (rng.chance(0.03) ? Double(Int.random(in: 1...3, using: &rng)) : 0, 0)
        case 14: (value, decimals) = (rng.chance(0.06) ? Double(Int.random(in: 1...6, using: &rng)) : 0, 0)
        case 15: (value, decimals) = (spot == 11 ? rng.normal(31, 11) : spot == 3 ? rng.normal(19, 6) : rng.normal(21, 7), 0)
        case 16: (value, decimals) = (spot == 11 ? rng.normal(19, 6) : rng.normal(12, 4), 0)
        default: (value, decimals) = (spot == 11 ? rng.normal(36, 7) : spot == 3 ? rng.normal(18, 5) : rng.normal(21, 5), 0)
        }
        let scale = pow(10, decimals)
        return .decimal((max(value, decimals == 0 ? 0 : 0.1) * scale).rounded() / scale)
    }
}
