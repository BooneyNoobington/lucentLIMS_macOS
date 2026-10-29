import Foundation

/// Readable collection identifiers in a mixed-radix numbering scheme.
///
/// Each segment is a "digit" with its own alphabet, so the sequence number 1000 becomes
/// `0·Cyan·1·Rho`. Consecutive identifiers differ in the last segment, which makes them
/// hard to swap by accident on a label or over the phone. This is the "mixed radix"
/// scheme of lucentAndShiny's `las.yaml`.
struct NumberingScheme: Sendable {
    struct Segment: Sendable {
        let name: String
        let symbols: [String]
    }

    let segments: [Segment]
    let separator: String

    /// How many identifiers the scheme can produce.
    var capacity: Int { segments.reduce(1) { $0 * $1.symbols.count } }

    /// The identifier for a zero-based sequence number, or `nil` if the scheme is exhausted.
    func identifier(for sequence: Int) -> String? {
        guard sequence >= 0, sequence < capacity else { return nil }
        var remaining = sequence
        var parts: [String] = []
        for segment in segments.reversed() {
            let base = segment.symbols.count
            parts.append(segment.symbols[remaining % base])
            remaining /= base
        }
        return parts.reversed().joined(separator: separator)
    }

    /// The zero-based sequence number of an identifier, or `nil` if it isn't one of ours.
    func sequence(of identifier: String) -> Int? {
        let parts = identifier.components(separatedBy: separator)
        guard parts.count == segments.count else { return nil }
        var result = 0
        for (part, segment) in zip(parts, segments) {
            guard let index = segment.symbols.firstIndex(of: part) else { return nil }
            result = result * segment.symbols.count + index
        }
        return result
    }

    /// The identifier after `identifier`, or `nil` if there is none.
    func next(after identifier: String) -> String? {
        sequence(of: identifier).flatMap { self.identifier(for: $0 + 1) }
    }

    static let colours = ["Red", "Orange", "Yellow", "Green", "Cyan", "Blue", "Violet"]

    static let lucent = NumberingScheme(
        segments: [
            Segment(name: "segment 1", symbols: (0...9).map(String.init)),
            Segment(name: "segment 2", symbols: colours),
            Segment(name: "segment 3", symbols: (0...9).map(String.init)),
            Segment(name: "segment 4", symbols: [
                "Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta", "Eta", "Theta",
                "Iota", "Kappa", "Lambda", "Mu", "Nu", "Xi", "Omicron", "Pi", "Rho",
                "Sigma", "Tau", "Upsilon", "Phi", "Chi", "Psi", "Omega",
            ]),
        ],
        separator: "·"
    )
}
