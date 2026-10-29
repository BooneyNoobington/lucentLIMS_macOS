import SwiftUI

@main
struct LucentLIMSApp: App {
    @State private var connection = Connection()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(connection)
        }
        #if os(macOS)
        .defaultSize(width: 1400, height: 880)
        #endif
        .commands {
            SidebarCommands()
            InspectorCommands()
            LabCommands()
        }
        #if os(macOS)
        Settings {
            ConnectionSettingsView()
                .environment(connection)
                .frame(width: 520)
        }
        #endif
    }
}

struct LabCommands: Commands {
    @FocusedValue(\.navigation) private var navigation

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Collection…") { navigation?.presentNewCollection() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(navigation == nil)
        }
        CommandMenu("Go") {
            ForEach(Array(SidebarItem.allCases.enumerated()), id: \.element) { index, item in
                Button(item.title) { navigation?.section = item }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                    .disabled(navigation == nil)
            }
        }
    }
}
