import SwiftUI

struct PeopleView: View {
    @Environment(LabStore.self) private var store

    var body: some View {
        List {
            ForEach(store.organizations) { organization in
                let members = store.members(of: organization)
                if !members.isEmpty {
                    Section(organization.name) {
                        ForEach(members) { person in
                            NavigationLink(value: Route.person(person.id)) {
                                PersonRow(person: person, isCurrentUser: person.id == store.currentUser.id)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("People")
    }
}

private struct PersonRow: View {
    let person: Person
    let isCurrentUser: Bool

    var body: some View {
        HStack(spacing: 12) {
            Avatar(person: person, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(person.fullName)
                        .font(.body.weight(.medium))
                    if isCurrentUser {
                        Text("You")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.accentColor, in: Capsule())
                    }
                }
                Text(person.position ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(person.linuxUser)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct PersonDetailView: View {
    @Environment(LabStore.self) private var store
    let person: Person

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
                LabeledContent("Linux user") {
                    Text(person.linuxUser).monospaced()
                }
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
        }
        .formStyle(.grouped)
        .navigationTitle(person.fullName)
    }
}
