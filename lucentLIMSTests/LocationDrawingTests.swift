#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import lucentLIMS

/// The Locations screen in a real window, while a site is drawn and when the drawing ends.
@MainActor
struct LocationDrawingTests {
    static let harbour = [GeoPoint(latitude: 49.016, longitude: 8.325), GeoPoint(latitude: 49.016, longitude: 8.332),
                          GeoPoint(latitude: 49.012, longitude: 8.332), GeoPoint(latitude: 49.012, longitude: 8.325)]

    func window(_ store: LabStore, _ navigation: AppNavigation) -> NSWindow {
        let view = NavigationStack { LocationsView() }.environment(store).environment(navigation)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1200, height: 800), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false  // Swift owns it; AppKit releasing it on close would be once too often
        window.contentView = NSHostingView(rootView: view)
        window.layoutIfNeeded()
        return window
    }

    func settle(_ window: NSWindow) async {
        for _ in 0..<5 {
            window.contentView?.layoutSubtreeIfNeeded()
            await Task.yield()
        }
    }

    @Test func endingADrawingClosesTheEditor() async throws {
        let store = LabStore.demo(userName: "grindel")
        let navigation = AppNavigation()
        navigation.section = .locations
        navigation.locationDraft = LocationDraft(kind: .site, name: "Rheinhafen", border: Self.harbour)
        let window = window(store, navigation)
        await settle(window)

        navigation.locationDraft = nil  // what Cancel and a successful save do
        await settle(window)
        #expect(navigation.locationDraft == nil)
        window.close()
    }

    @Test func savingADrawingSelectsTheNewSite() async throws {
        let store = LabStore.demo(userName: "grindel")
        let navigation = AppNavigation()
        let draft = LocationDraft(kind: .site, name: "Rheinhafen", border: Self.harbour)
        navigation.locationDraft = draft
        let window = window(store, navigation)
        await settle(window)

        navigation.locationSelection = try await store.create(draft)
        navigation.locationDraft = nil
        await settle(window)
        #expect(store.sites.contains { $0.name == "Rheinhafen" } && navigation.locationDraft == nil)
        window.close()
    }
}
#endif
