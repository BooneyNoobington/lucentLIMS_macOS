import Foundation

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

/// Mock data in lucentBASE's model. The master data is lucentAPI's demo package (demo.lucent.json,
/// a copy of lucentAPI's examples/responses/package.json; the system user is Booney Noobington,
/// lucentAndShiny's demo person). Collections, measurements, tasks and messages are generated
/// relative to `now`, so the dashboard looks current.
enum MockData {
    /// People, in the package's order.
    static let system = 1, doe = 2, dorn = 3, simpson = 4, picard = 5, ripley = 6
    static let samplingTime = 1

    static let roleDescriptions: [LabRole: String] = [
        .sampler: "Registers collections.",
        .analyst: "Records raw values.",
        .reviewer: "Accepts and withdraws raw values, except their own.",
        .admin: "May do everything, including managing people, roles and devices.",
    ]

    static let collectionClasses = ["spot sample", "mixed sample", "collective sample", "time series",
                                    "free measurement"]

    static func make(now: Date = .now, calendar: Calendar = .current) -> LabData {
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int, hour: Int = 16) -> Date {
            calendar.date(byAdding: .hour, value: offset * 24 + hour, to: today)!
        }
        let master: PackageData
        do { master = try PackageData.demo() } catch { fatalError("The bundled demo package doesn't load: \(error)") }
        let (actions, effects, parameters) = (master.actions, master.effects, master.parameters)
        let spotIDs = Dictionary(uniqueKeysWithValues: master.spots.map { ($0.name, $0.id) })
        let siteIDs = Dictionary(uniqueKeysWithValues: master.sites.map { ($0.name, $0.id) })
        let matrixIDs = Dictionary(uniqueKeysWithValues: master.matrices.map { ($0.name, $0.id) })
        let actionIDs = Dictionary(actions.filter(\.active).map { ($0.name, $0.id) }, uniquingKeysWith: max)
        let dustSampler = { (number: Int) in master.devices.first { $0.name == "Feinstaubsammler LVS-3" && $0.number == number }!.id }

        // Collections: who samples what where, with which actions, how often (days), first offset (days ago).
        struct Schedule {
            var spot: String? = nil
            var site: String? = nil
            var matrix: String, collectionClass: String, actions: [String], every: Int, offset: Int, samplerID: Int
        }
        let sampling = "Probenahme Wasser", sensory = "Sensorische Prüfung", pH = "pH-Wert", conductivity = "Elektrische Leitfähigkeit"
        let anions = "Anionen (IC)", metals = "Metalle (ICP-MS)", bacteria = "E. coli und coliforme Bakterien"
        let dust = "Feinstaub (gravimetrisch)", no2 = "Stickstoffdioxid"
        let waterRoutine = [sampling, sensory, pH, conductivity, bacteria]
        let waterFull = [sampling, sensory, pH, conductivity, anions, metals, bacteria]
        let groundWater = [sampling, pH, conductivity, anions], air = [dust, no2]
        let schedules = [
            Schedule(spot: "Garten", matrix: "Luft", collectionClass: "time series", actions: air, every: 7, offset: 1, samplerID: simpson),
            Schedule(spot: "Messcontainer Innenstadt", matrix: "Luft", collectionClass: "time series", actions: air, every: 7, offset: 2, samplerID: simpson),
            Schedule(spot: "Test 1", matrix: "Luft", collectionClass: "time series", actions: air, every: 14, offset: 5, samplerID: simpson),
            Schedule(spot: "Zapfstelle Labor 2.14", matrix: "Leitungswasser", collectionClass: "spot sample", actions: waterFull, every: 14, offset: 3, samplerID: dorn),
            Schedule(spot: "Zapfstelle Kantine", matrix: "Leitungswasser", collectionClass: "spot sample", actions: waterRoutine, every: 14, offset: 10, samplerID: dorn),
            Schedule(spot: "Hochbehälter Nord", matrix: "Trinkwasser", collectionClass: "spot sample", actions: waterRoutine, every: 7, offset: 0, samplerID: dorn),
            Schedule(spot: "Wasserwerk Reinwasser", matrix: "Trinkwasser", collectionClass: "spot sample", actions: waterRoutine, every: 7, offset: 4, samplerID: dorn),
            Schedule(spot: "Wasserwerk Reinwasser", matrix: "Trinkwasser", collectionClass: "spot sample", actions: waterFull, every: 28, offset: 6, samplerID: dorn),
            Schedule(spot: "Brunnen B3", matrix: "Grundwasser", collectionClass: "spot sample", actions: groundWater, every: 14, offset: 2, samplerID: dorn),
            Schedule(spot: "Brunnen B7", matrix: "Grundwasser", collectionClass: "spot sample", actions: groundWater, every: 14, offset: 9, samplerID: dorn),
            Schedule(spot: "GWM 12", matrix: "Grundwasser", collectionClass: "spot sample", actions: groundWater, every: 7, offset: 3, samplerID: ripley),
            Schedule(site: "Messfeld Rheinaue", matrix: "Grundwasser", collectionClass: "mixed sample", actions: groundWater, every: 28, offset: 12, samplerID: ripley),
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

        let workers = [sampling: dorn, sensory: dorn, pH: doe, conductivity: doe, anions: doe, metals: picard,
                       bacteria: ripley, dust: doe, no2: simpson]
        let numbering = NumberingScheme.lucent
        var collections: [LabCollection] = []
        var values: [LabValue] = []
        var rawValues: [RawValue] = []
        for (index, draft) in drafts.enumerated() {
            let schedule = draft.schedule
            let planned = schedule.actions.map { actionIDs[$0]! }
            let collection = LabCollection(
                id: index + 1, name: numbering.identifier(for: 3000 + index + 1)!, matrixID: matrixIDs[schedule.matrix]!,
                collectionClass: schedule.collectionClass, spotID: schedule.spot.map { spotIDs[$0]! },
                siteID: schedule.site.map { siteIDs[$0]! }, sampledAt: draft.sampledAt, sampledByID: schedule.samplerID)
            collections.append(collection)
            var slots: [Int: Int] = [:]
            for effect in effects where planned.contains(effect.actionID) {
                values.append(LabValue(id: values.count + 1, collectionID: collection.id, effectID: effect.id))
                slots[effect.id] = values.count
            }

            let age = now.timeIntervalSince(draft.sampledAt) / 86_400
            let progress = 1 - age / Double(horizon)
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
                if action.name == dust { deviceID = dustSampler(schedule.spot == "Messcontainer Innenstadt" ? 1192 : 1187) }
                for effect in effects where effect.actionID == actionID {
                    let parameter = parameters.first { $0.id == effect.parameterID }!
                    var readings: [Reading]
                    var t = measuredAt, person = workers[action.name]!
                    if parameter.id == samplingTime {
                        readings = [.datetime(draft.sampledAt)]
                        t = draft.sampledAt
                        person = schedule.samplerID
                    } else {
                        readings = [mockReading(parameter.name, at: schedule.spot, progress: progress, rng: &rng)]
                        // A lead value above the limit is measured again.
                        if parameter.name == "Blei", case .decimal(let lead) = readings[0], lead > 10 {
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
            organizations: master.organizations, people: master.people, crs: master.crs, sites: master.sites,
            spots: master.spots, matrices: master.matrices, collectionClasses: collectionClasses,
            dimensions: master.dimensions, units: master.units, parameters: parameters, devices: master.devices,
            documents: master.documents, actions: actions, effects: effects, thresholds: master.thresholds,
            coefficients: master.coefficients, collections: collections, values: values, rawValues: rawValues, tasks: tasks,
            messages: messages, samplingTimeParameterID: samplingTime, roleDescriptions: roleDescriptions)
    }

    /// A plausible reading of a parameter at a spot (nil: a site's mixed sample). `progress` runs
    /// from 0 (oldest) to 1 (now).
    private static func mockReading(_ parameter: String, at spot: String?, progress: Double,
                                    rng: inout SeededGenerator) -> Reading {
        let ground = spot == nil || ["Brunnen B3", "Brunnen B7", "GWM 12"].contains(spot)
        let traffic = spot == "Messcontainer Innenstadt", garden = spot == "Garten"
        let lead = spot == "Zapfstelle Labor 2.14", rising = spot == "GWM 12"  // lead pipes; nitrate rising above the limit
        let value: Double, decimals: Double
        switch parameter {
        case "Temperatur": (value, decimals) = (rng.normal(ground ? 11.5 : 14, 1), 1)
        case "Färbung": return .text(rng.chance(0.93) ? "farblos" : "schwach gelblich")
        case "Geruch auffällig": return .boolean(rng.chance(0.04))
        case "pH-Wert": (value, decimals) = (rng.normal(ground ? 7.15 : 7.6, 0.08), 2)
        case "Elektrische Leitfähigkeit": (value, decimals) = (rng.normal(rising ? 880 : 650, 30), 0)
        case "Nitrat": (value, decimals) = (rising ? 38 + 18 * progress + rng.normal(0, 2) : rng.normal(ground ? 20 : 15, 1.5), 1)
        case "Chlorid": (value, decimals) = (rng.normal(45, 4), 1)
        case "Sulfat": (value, decimals) = (rng.normal(62, 5), 1)
        case "Blei": (value, decimals) = (lead ? (progress > 0.8 ? rng.normal(12.5, 1) : rng.normal(7.5, 2.8)) : rng.normal(0.8, 0.3), 1)
        case "Kupfer": (value, decimals) = (lead ? rng.normal(0.45, 0.12) : rng.normal(0.05, 0.02), 2)
        case "Nickel": (value, decimals) = (rng.normal(2.5, 0.8), 1)
        case "Escherichia coli": (value, decimals) = (rng.chance(0.03) ? Double(Int.random(in: 1...3, using: &rng)) : 0, 0)
        case "Coliforme Bakterien": (value, decimals) = (rng.chance(0.06) ? Double(Int.random(in: 1...6, using: &rng)) : 0, 0)
        case "Feinstaub PM10": (value, decimals) = (traffic ? rng.normal(31, 11) : garden ? rng.normal(19, 6) : rng.normal(21, 7), 0)
        case "Feinstaub PM2,5": (value, decimals) = (traffic ? rng.normal(19, 6) : rng.normal(12, 4), 0)
        default: (value, decimals) = (traffic ? rng.normal(36, 7) : garden ? rng.normal(18, 5) : rng.normal(21, 5), 0)
        }
        let scale = pow(10, decimals)
        return .decimal((max(value, decimals == 0 ? 0 : 0.1) * scale).rounded() / scale)
    }
}
