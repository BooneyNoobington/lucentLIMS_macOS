import SwiftUI

struct ContentView: View {
    @Environment(LabStore.self) private var store
    @State private var navigation = AppNavigation()

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $navigation.section)
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 300)
        } detail: {
            NavigationStack(path: $navigation.path) {
                section(navigation.section ?? .dashboard)
                    .navigationDestination(for: Route.self) { route in
                        RouteView(route: route)
                            .inlineNavigationTitle()
                    }
            }
            .id(navigation.section)
        }
        .environment(navigation)
        .focusedSceneValue(\.navigation, navigation)
        .sheet(isPresented: $navigation.isPresentingNewCollection) {
            NewCollectionSheet(store: store)
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
        case .variables: CatalogView()
        case .people: PeopleView()
        case .devices: DevicesView()
        case .tasks: TasksView()
        case .sops: SOPsView()
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
        case .sop(let id):
            if let sop = store.sop(id) { SOPDetailView(sop: sop) }
        }
    }
}

private struct Sidebar: View {
    @Environment(LabStore.self) private var store
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            row(.dashboard)
            Section("Laboratory") {
                row(.collections, badge: store.collections.filter { store.status(of: $0) == .inReview }.count)
                row(.locations)
            }
            Section("Scientific") {
                row(.methods)
                row(.variables)
            }
            Section("Management") {
                row(.people)
                row(.devices)
                row(.tasks, badge: store.tasks.filter { store.isOverdue($0) }.count)
                row(.sops)
            }
        }
        .navigationTitle("lucentLIMS")
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Avatar(person: store.currentUser, size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text(store.currentUser.fullName)
                        .font(.callout.weight(.medium))
                    Text(store.currentUser.unixAccount)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private func row(_ item: SidebarItem, badge: Int = 0) -> some View {
        Label(item.title, systemImage: item.systemImage)
            .badge(badge)
            .tag(item)
    }
}
