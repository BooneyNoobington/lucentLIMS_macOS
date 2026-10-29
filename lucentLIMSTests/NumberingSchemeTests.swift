import Testing
@testable import lucentLIMS

struct NumberingSchemeTests {
    let scheme = NumberingScheme.lucent

    @Test func capacityIsTheProductOfTheSegments() {
        #expect(scheme.capacity == 10 * 7 * 10 * 24)
    }

    @Test func firstIdentifierUsesTheFirstSymbols() {
        #expect(scheme.identifier(for: 0) == "0·Red·0·Alpha")
    }

    @Test func documentedExample() {
        #expect(scheme.identifier(for: 1000) == "0·Cyan·1·Rho")
    }

    @Test func everyIdentifierRoundTrips() {
        for sequence in 0..<scheme.capacity {
            let identifier = try! #require(scheme.identifier(for: sequence))
            #expect(scheme.sequence(of: identifier) == sequence)
        }
    }

    @Test func nextCarriesIntoTheNextSegment() {
        #expect(scheme.next(after: "0·Red·0·Alpha") == "0·Red·0·Beta")
        #expect(scheme.next(after: "0·Red·0·Omega") == "0·Red·1·Alpha")
        #expect(scheme.next(after: "0·Red·9·Omega") == "0·Orange·0·Alpha")
        #expect(scheme.next(after: "0·Violet·9·Omega") == "1·Red·0·Alpha")
    }

    @Test func exhaustedSchemeHasNoNextIdentifier() {
        #expect(scheme.next(after: "9·Violet·9·Omega") == nil)
        #expect(scheme.identifier(for: scheme.capacity) == nil)
        #expect(scheme.identifier(for: -1) == nil)
    }

    @Test(arguments: ["", "0·Red·0", "0·Red·0·Alpha·1", "0·Magenta·0·Alpha", "0-Red-0-Alpha"])
    func foreignIdentifiersAreRejected(_ identifier: String) {
        #expect(scheme.sequence(of: identifier) == nil)
    }
}
