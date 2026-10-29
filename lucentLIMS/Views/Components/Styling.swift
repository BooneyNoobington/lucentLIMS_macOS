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
    var tint: Color {
        switch id {
        case 8: .teal
        case 9: .indigo
        case 10: .blue
        case 11: .orange
        default: .gray
        }
    }

    var systemImage: String {
        switch id {
        case 8: "wind"
        case 11: "water.waves"
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
    func format(_ reading: Reading, _ actionVariable: ActionVariable) -> String {
        switch reading {
        case .decimal(let number):
            let text = number.formatted(.number.precision(.fractionLength(actionVariable.decimals)))
            let symbol = unit(actionVariable.unitID)?.symbol ?? ""
            return symbol.isEmpty ? text : "\(text) \(symbol)"
        case .text(let text):
            return text
        case .boolean(let flag):
            return flag ? String(localized: "Yes") : String(localized: "No")
        case .datetime(let date):
            return date.formatted(date: .abbreviated, time: .shortened)
        }
    }

    /// "± 0.05" or "± 2 %".
    func uncertaintyText(_ actionVariable: ActionVariable) -> String? {
        guard let uncertainty = actionVariable.uncertainty else { return nil }
        switch actionVariable.uncertaintyClass {
        case .absolute:
            let symbol = unit(actionVariable.unitID)?.symbol ?? ""
            return "± \(uncertainty.formatted())" + (symbol.isEmpty ? "" : " \(symbol)")
        case .relative:
            return "± \(uncertainty.formatted()) %"
        }
    }

    /// "≤ 50 mg/L", or "No" for a flag that should stay unset.
    func limitText(_ actionVariable: ActionVariable) -> String? {
        guard let limits = actionVariable.limitDescription else { return nil }
        if variable(actionVariable.variableID)?.valueClass == .boolean { return String(localized: "No") }
        let symbol = unit(actionVariable.unitID)?.symbol ?? ""
        return symbol.isEmpty ? limits : "\(limits) \(symbol)"
    }

    /// "Limit ≤ 50 mg/L" or "Expected: No".
    func limitPhrase(_ actionVariable: ActionVariable) -> String? {
        guard let limit = limitText(actionVariable) else { return nil }
        return variable(actionVariable.variableID)?.valueClass == .boolean
            ? String(localized: "Expected: \(limit)") : String(localized: "Limit \(limit)")
    }
}
