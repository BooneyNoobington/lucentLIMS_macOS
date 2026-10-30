import SwiftUI

extension CollectionStatus {
    var title: String {
        switch self {
        case .registered: String(localized: "Registered")
        case .inAnalysis: String(localized: "In analysis")
        case .inReview: String(localized: "In review")
        case .approved: String(localized: "Approved")
        }
    }

    var systemImage: String {
        switch self {
        case .registered: "tray"
        case .inAnalysis: "flask"
        case .inReview: "eye"
        case .approved: "checkmark.seal.fill"
        }
    }

    var tint: Color {
        switch self {
        case .registered: .gray
        case .inAnalysis: .orange
        case .inReview: .blue
        case .approved: .green
        }
    }
}

extension ValueClass {
    var title: String {
        switch self {
        case .decimal: String(localized: "Decimal")
        case .text: String(localized: "Text")
        case .boolean: String(localized: "Boolean")
        case .datetime: String(localized: "Date and time")
        }
    }

    var systemImage: String {
        switch self {
        case .decimal: "number"
        case .text: "textformat"
        case .boolean: "switch.2"
        case .datetime: "calendar.badge.clock"
        }
    }
}

extension Matrix {
    /// By name, since the ids differ from one lucentBASE to the next.
    var tint: Color {
        switch name {
        case "Luft": .teal
        case "Leitungswasser": .indigo
        case "Trinkwasser": .blue
        case "Grundwasser": .orange
        default: .gray
        }
    }

    var systemImage: String {
        switch name {
        case "Luft": "wind"
        case "Grundwasser": "water.waves"
        default: "drop.fill"
        }
    }
}

extension Person {
    var tint: Color { Color(hue: Double((id * 47) % 360) / 360, saturation: 0.5, brightness: 0.78) }
}

extension Color {
    /// The colour of a segment of a collection identifier, if it names one.
    init?(numberingColour name: String) {
        switch name {
        case "Red": self = .red
        case "Orange": self = .orange
        case "Yellow": self = .yellow
        case "Green": self = .green
        case "Cyan": self = .cyan
        case "Blue": self = .blue
        case "Violet": self = .purple
        default: return nil
        }
    }

    static var pageBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }

    static var cardBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
}

extension LabStore {
    /// A reading with its unit, e.g. "12.5 µg/L".
    func format(_ reading: Reading, unitID: Int?) -> String {
        switch reading {
        case .decimal(let number):
            let text = number.formatted(.number.grouping(.never).precision(.fractionLength(0...3)))
            let symbol = unit(unitID)?.symbol ?? ""
            return symbol.isEmpty ? text : "\(text) \(symbol)"
        case .text(let text):
            return text
        case .boolean(let flag):
            return flag ? String(localized: "Yes") : String(localized: "No")
        case .datetime(let date):
            return date.formatted(date: .abbreviated, time: .shortened)
        }
    }

    /// A raw value's reading in its unit, or "—" if it holds nothing.
    func format(_ raw: RawValue) -> String {
        raw.reading.map { format($0, unitID: raw.unitID) } ?? "—"
    }

    /// "± 0.05 °C" or "± 2 %".
    func uncertaintyText(_ effect: Effect) -> String? {
        guard let uncertainty = effect.uncertainty else { return nil }
        switch effect.uncertaintyClass {
        case .absolute:
            let symbol = unit(effect.uncertaintyUnitID ?? parameter(effect.parameterID)?.unitID)?.symbol ?? ""
            return "± \(uncertainty.formatted())" + (symbol.isEmpty ? "" : " \(symbol)")
        case .relative:
            return "± \(uncertainty.formatted()) %"
        }
    }

    /// "≤ 50 mg/L", or "No" for a flag that should stay unset.
    func limitText(_ threshold: Threshold) -> String {
        let parameter = parameter(threshold.parameterID)
        if parameter?.valueClass == .boolean { return String(localized: "No") }
        let symbol = unit(parameter?.unitID)?.symbol ?? ""
        return symbol.isEmpty ? threshold.rangeDescription : "\(threshold.rangeDescription) \(symbol)"
    }

    /// The limits of an effect, e.g. "≤ 50 mg/L (TrinkwV, GrwV)", or nil if none apply.
    func limitText(_ effect: Effect) -> String? {
        let limits = limits(of: effect)
        guard !limits.isEmpty else { return nil }
        var ranges: [String] = [], documents: [String: [String]] = [:]
        for limit in limits {
            let range = limitText(limit)
            if documents[range] == nil { ranges.append(range) }
            documents[range, default: []].append(document(limit.documentID)?.shortName ?? "")
        }
        if ranges.count == 1 && limits.count == 1 { return ranges[0] }
        return ranges.map { "\($0) (\(documents[$0]!.joined(separator: ", ")))" }.joined(separator: ", ")
    }

    /// "Limit ≤ 50 mg/L" or "Expected: No".
    func limitPhrase(_ effect: Effect) -> String? {
        guard let limit = limitText(effect) else { return nil }
        return parameter(effect.parameterID)?.valueClass == .boolean
            ? String(localized: "Expected: \(limit)") : String(localized: "Limit \(limit)")
    }
}

extension Document {
    /// The abbreviation in parentheses, e.g. "TrinkwV", else the name.
    var shortName: String {
        if let open = name.lastIndex(of: "("), let close = name.lastIndex(of: ")"), open < close {
            return String(name[name.index(after: open)..<close])
        }
        return name
    }

    var systemImage: String { url != nil ? "globe" : "doc.richtext" }
}
