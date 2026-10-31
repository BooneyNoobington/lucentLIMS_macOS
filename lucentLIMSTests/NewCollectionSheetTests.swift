#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import lucentLIMS

@MainActor
struct NewCollectionSheetTests {
    @Test func theSheetRenders() async {
        let store = LabStore.demo(userName: "grindel")
        let navigation = AppNavigation()
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 520, height: 720), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: NewCollectionSheet(store: store)
            .environment(store).environment(navigation))
        for _ in 0..<5 {
            window.contentView?.layoutSubtreeIfNeeded()
            await Task.yield()
        }
        #expect(window.contentView?.fittingSize.height ?? 0 > 0)
        window.close()
    }
}
#endif
