import SwiftUI

/// Everyone in lucentBASE, by organization, and who may do what. Admins add and change people.
struct PeopleView: View {
    @Environment(LabStore.self) private var store
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        let active = store.people.filter(\.active)
        let inactive = store.people.filter { !$0.active }
        let unaffiliated = active.filter { store.organization($0.organizationID) == nil }

        List {
            ForEach(store.organizations) { organization in
                let members = active.filter { $0.organizationID == organization.id }
                if !members.isEmpty {
                    Section(organization.name) { rows(members) }
                }
            }
            if !unaffiliated.isEmpty {
                Section("Without organization") { rows(unaffiliated) }
            }
            if !inactive.isEmpty {
                Section("No longer active") { rows(inactive) }
            }
        }
        .navigationTitle("People")
        .toolbar {
            ToolbarItem {
                Button("New Person", systemImage: "person.badge.plus") { navigation.personEditor = .new }
                    .disabled(!store.can(.admin))
                    .help(store.can(.admin) ? "Add a person" : "Needs the admin role")
            }
        }
    }

    private func rows(_ people: [Person]) -> some View {
        ForEach(people) { person in
            NavigationLink(value: Route.person(person.id)) {
                PersonRow(person: person, isCurrentUser: person.id == store.currentUser.id)
            }
        }
    }
}

private struct PersonRow: View {
    let person: Person
    let isCurrentUser: Bool
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var isCompact: Bool { horizontalSizeClass == .compact }
    #else
    private let isCompact = false
    #endif

    var body: some View {
        HStack(spacing: 12) {
            Avatar(person: person, size: 36)
                .opacity(person.active ? 1 : 0.45)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(person.fullName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(person.active ? .primary : .secondary)
                    if isCurrentUser {
                        Text("You")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.accentColor, in: Capsule())
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !isCompact {  // the subtitle names the roles too
                HStack(spacing: 4) {
                    ForEach(person.roles.sorted(), id: \.self) { role in
                        Image(systemName: role.systemImage)
                            .help(role.title)
                    }
                }
                .font(.caption)
                .foregroundStyle(Color.accentColor)
            }
            Text(person.linuxUser)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        let roles = person.roles.sorted().map(\.title).formatted(.list(type: .and))
        return [person.position ?? "", roles].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct PersonDetailView: View {
    @Environment(LabStore.self) private var store
    @Environment(AppNavigation.self) private var navigation
    let person: Person
    @State private var history: [HistoryEntry]?

    var body: some View {
        let tasks = store.tasks.filter { $0.assigneeID == person.id && !$0.done }.sorted { $0.deadline < $1.deadline }
        let sampled = store.collections.filter { $0.sampledByID == person.id }.sorted { $0.sampledAt > $1.sampledAt }

        Form {
            Section {
                HStack(spacing: 16) {
                    Avatar(person: person, size: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(person.fullName)
                            .font(.title2.weight(.semibold))
                        Text(person.position ?? "")
                            .foregroundStyle(.secondary)
                        Text(store.organization(person.organizationID)?.name ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }

            Section("Sign-in") {
                LabeledContent("Linux user") {
                    Text(person.linuxUser.isEmpty ? "—" : person.linuxUser).monospaced()
                }
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Image(systemName: person.active ? "checkmark.circle.fill" : "pause.circle")
                        Text(person.active ? "Active" : "Inactive")
                    }
                    .foregroundStyle(person.active ? Color.green : Color.orange)
                }
            }

            Section {
                ForEach(LabRole.allCases, id: \.self) { role in
                    let has = person.roles.contains(role)
                    Label {
                        Text(role.title)
                        if let description = store.roleDescriptions[role] { Text(description) }
                    } icon: {
                        Image(systemName: has ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(has ? Color.accentColor : Color.secondary)
                    }
                    .foregroundStyle(has ? .primary : .secondary)
                }
            } header: {
                Text("Roles")
            } footer: {
                Text("What lucentBASE lets \(person.givenName) do. Admins change it.")
            }

            let actions = store.actions(involving: person)
            if !actions.isEmpty {
                Section("Methods") {
                    ForEach(actions, id: \.action.id) { item in
                        NavigationLink(value: Route.method(item.action.id)) {
                            LabeledContent(item.action.name, value: item.role.capitalized)
                        }
                    }
                }
            }

            if !tasks.isEmpty {
                Section("Open tasks") {
                    ForEach(tasks) { task in
                        LabeledContent(task.request) {
                            DeadlineText(deadline: task.deadline, done: task.done, now: store.now)
                        }
                    }
                }
            }

            if !sampled.isEmpty {
                Section("Recently sampled") {
                    ForEach(sampled.prefix(5)) { collection in
                        NavigationLink(value: Route.collection(collection.id)) {
                            LabeledContent {
                                Text(collection.sampledAt, format: .relative(presentation: .named))
                            } label: {
                                IdentifierView(identifier: collection.name)
                                Text(store.locationName(of: collection))
                            }
                        }
                    }
                }
            }

            Section("History") {
                if let history {
                    if history.isEmpty {
                        Text("No changes logged.").foregroundStyle(.secondary)
                    }
                    ForEach(history) { entry in
                        HistoryRow(entry: entry)
                    }
                } else {
                    ProgressView()
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(person.fullName)
        .toolbar {
            ToolbarItem {
                Button("Edit", systemImage: "pencil") { navigation.personEditor = .edit(person.id) }
                    .disabled(!store.can(.admin))
                    .help(store.can(.admin) ? "Change names, sign-in, organization and roles" : "Needs the admin role")
            }
        }
        // Reloads after every change to the person.
        .task(id: person) {
            history = try? await store.history(of: person)
        }
    }
}

private struct HistoryRow: View {
    @Environment(LabStore.self) private var store
    let entry: HistoryEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.note)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var icon: String {
        switch entry.subject {
        case .person: entry.created ? "person.badge.plus" : "person"
        case .role(let role): role?.systemImage ?? "key"
        case .organization: "building.2"
        }
    }

    private var detail: String {
        let when = entry.t?.formatted(date: .abbreviated, time: .shortened) ?? ""
        guard let editor = store.person(entry.editorID) else { return when }
        return "\(when) · \(editor.fullName)"
    }
}
