import SwiftUI

struct ContentView: View {
    @Environment(Connection.self) private var connection
    @State private var navigation = AppNavigation()
    @State private var showsSettings = false

    private var store: LabStore { connection.store }

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $navigation.section, showsSettings: $showsSettings)
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 300)
        } detail: {
            switch connection.state {
            case .ready:
                NavigationStack(path: $navigation.path) {
                    section(navigation.section ?? .dashboard)
                        .navigationDestination(for: Route.self) { route in
                            RouteView(route: route)
                                .inlineNavigationTitle()
                        }
                }
                .id(navigation.section)
            case .loading:
                VStack(spacing: 20) {
                    LucentMark()
                        .frame(width: 64, height: 64)
                    ProgressView("Loading from \(connection.summary)…")
                }
            case .needsSignIn:
                SignInView()
            case .failed(let message):
                ContentUnavailableView {
                    Label("Can't Load from \(connection.summary)", systemImage: "exclamationmark.icloud")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await connection.connect() } }
                        .buttonStyle(.borderedProminent)
                    Button("Use Demo Data") { connection.useDemoData() }
                }
            }
        }
        .environment(store)
        .environment(navigation)
        .alert("The change wasn't saved", isPresented: Binding(
            get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })
        ) {
            Button("OK") {}
        } message: {
            Text(store.errorMessage ?? "")
        }
        #if os(iOS)
        .sheet(isPresented: $showsSettings) {
            NavigationStack {
                ConnectionSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { showsSettings = false } }
                    }
            }
            .environment(connection)
        }
        #endif
        .focusedSceneValue(\.navigation, navigation)
        .sheet(isPresented: $navigation.isPresentingNewCollection) {
            NewCollectionSheet(store: store)
                .environment(store)
                .environment(navigation)
        }
        .sheet(item: $navigation.personEditor) { target in
            PersonEditor(target: target, store: store)
                .environment(store)
                .environment(navigation)
        }
    }

    @ViewBuilder
    private func section(_ item: SidebarItem) -> some View {
        switch item {
        case .dashboard: DashboardView()
        case .collections: CollectionsView()
        case .locations: LocationsView()
        case .methods: MethodsView()
        case .parameters: CatalogView()
        case .people: PeopleView()
        case .devices: DevicesView()
        case .tasks: TasksView()
        case .documents: DocumentsView()
        }
    }
}

struct RouteView: View {
    @Environment(LabStore.self) private var store
    let route: Route

    var body: some View {
        switch route {
        case .collection(let id):
            if let collection = store.collection(id) {
                CollectionDetailView(collection: collection)
                    .navigationTitle(collection.name)
            }
        case .method(let id):
            if let action = store.action(id) { MethodDetailView(action: action) }
        case .person(let id):
            if let person = store.person(id) { PersonDetailView(person: person) }
        case .document(let id):
            if let document = store.document(id) { DocumentDetailView(document: document) }
        }
    }
}

private struct Sidebar: View {
    @Environment(LabStore.self) private var store
    @Environment(Connection.self) private var connection
    @Binding var selection: SidebarItem?
    @Binding var showsSettings: Bool

    var body: some View {
        List(selection: $selection) {
            Section {
                row(.dashboard)
            } header: {
                LucentLogo(height: 26)
                    .padding(.top, 4)
                    .padding(.bottom, 10)
                    .textCase(nil)
            }
            Section("Laboratory") {
                row(.collections, badge: store.collections.filter { store.status(of: $0) == .inReview }.count)
                row(.locations)
            }
            Section("Scientific") {
                row(.methods)
                row(.parameters)
            }
            Section("Management") {
                row(.people)
                row(.devices)
                row(.tasks, badge: store.tasks.filter { store.isOverdue($0) }.count)
                row(.documents)
            }
        }
        #if os(macOS)
        .navigationTitle("lucentLIMS")
        #endif
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Avatar(person: store.currentUser, size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text(store.currentUser.fullName)
                        .font(.callout.weight(.medium))
                    Label(connection.summary, systemImage: connection.isDemo ? "shippingbox" : "server.rack")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                #if os(macOS)
                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Connection settings")
                #else
                Button("Connection Settings", systemImage: "gearshape") { showsSettings = true }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                #endif
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    private func row(_ item: SidebarItem, badge: Int = 0) -> some View {
        Label(item.title, systemImage: item.systemImage)
            .badge(badge)
            .tag(item)
    }
}
