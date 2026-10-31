import SwiftUI

/// The sections of the sidebar, grouped as in lucentAndShiny.
enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case dashboard, collections, locations, methods, parameters, people, devices, tasks, documents

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: String(localized: "Dashboard")
        case .collections: String(localized: "Collections")
        case .locations: String(localized: "Locations")
        case .methods: String(localized: "Methods")
        case .parameters: String(localized: "Parameters & Units")
        case .people: String(localized: "People")
        case .devices: String(localized: "Devices")
        case .tasks: String(localized: "Tasks")
        case .documents: String(localized: "Documents")
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "gauge.with.dots.needle.67percent"
        case .collections: "testtube.2"
        case .locations: "map"
        case .methods: "flask"
        case .parameters: "atom"
        case .people: "person.2"
        case .devices: "gauge.with.needle"
        case .tasks: "checklist"
        case .documents: "doc.text"
        }
    }
}

/// Pages that can be pushed onto any section's navigation stack.
enum Route: Hashable {
    case collection(Int)
    case method(Int)
    case person(Int)
    case document(Int)
}

/// Navigation state of one window.
@MainActor
@Observable
final class AppNavigation {
    var section: SidebarItem? = .dashboard {
        didSet { if section != oldValue { path = [] } }
    }
    var path: [Route] = []

    var collectionSelection: Set<Int> = []
    var collectionSearch = ""
    var collectionStatusFilter: CollectionStatus?
    var showsCollectionInspector = !Platform.isPhone
    var locationSelection: LocationRef?
    var isPresentingNewCollection = false
    var personEditor: PersonEditor.Target?

    init() {
        #if DEBUG
        applyLaunchArguments(UserDefaults.standard)
        #endif
    }

    func open(collection id: Int) {
        section = .collections
        collectionSearch = ""
        collectionStatusFilter = nil
        collectionSelection = [id]
        showsCollectionInspector = true
    }

    func open(location: LocationRef) {
        section = .locations
        locationSelection = location
    }

    func showCollections(matching search: String = "", status: CollectionStatus? = nil) {
        section = .collections
        collectionSearch = search
        collectionStatusFilter = status
        collectionSelection = []
    }

    func presentNewCollection() {
        isPresentingNewCollection = true
    }
}

#if DEBUG
extension AppNavigation {
    /// Opens a screen from launch arguments, for screenshots without clicking through, e.g.
    /// `-section locations -location spot:10`, `-section methods -route method:5` or
    /// `-section people -route person:6 -editPerson 6`.
    private func applyLaunchArguments(_ defaults: UserDefaults) {
        func reference(_ key: String) -> (kind: Substring, id: Int)? {
            guard let parts = defaults.string(forKey: key)?.split(separator: ":"), parts.count == 2,
                  let id = Int(parts[1]) else { return nil }
            return (parts[0], id)
        }
        if let raw = defaults.string(forKey: "section") {
            section = SidebarItem(rawValue: raw)  // "none" shows the sidebar on an iPhone
        }
        if defaults.integer(forKey: "collection") > 0 {
            collectionSelection = [defaults.integer(forKey: "collection")]
        }
        if let (kind, id) = reference("location") {
            locationSelection = kind == "site" ? .site(id) : .spot(id)
        }
        if let (kind, id) = reference("route") {
            switch kind {
            case "collection": path = [.collection(id)]
            case "method": path = [.method(id)]
            case "person": path = [.person(id)]
            case "document": path = [.document(id)]
            default: break
            }
        }
        isPresentingNewCollection = defaults.bool(forKey: "newCollection")
        if defaults.bool(forKey: "newPerson") {
            personEditor = .new
        } else if defaults.integer(forKey: "editPerson") > 0 {
            personEditor = .edit(defaults.integer(forKey: "editPerson"))
        }
    }
}
#endif

enum Platform {
    /// On an iPhone an inspector is a sheet, so it starts closed there.
    @MainActor static var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }
}

extension FocusedValues {
    @Entry var navigation: AppNavigation?
}
