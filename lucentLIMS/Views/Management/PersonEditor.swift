import SwiftUI

/// Adds a person or changes one: names, sign-in, organization and roles. Admins only. The
/// reason goes into lucentBASE's log with every change it causes.
struct PersonEditor: View {
    enum Target: Hashable, Identifiable {
        case new
        case edit(Int)

        var id: Self { self }
    }

    @Environment(LabStore.self) private var store
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.dismiss) private var dismiss

    let target: Target
    @State private var draft: PersonDraft
    @State private var roles: Set<LabRole>
    @State private var reason = ""
    @State private var saving = false
    @State private var error: String?

    init(target: Target, store: LabStore) {
        self.target = target
        if case .edit(let id) = target, let person = store.person(id) {
            _draft = State(initialValue: PersonDraft(person))
            _roles = State(initialValue: person.roles)
        } else {
            var draft = PersonDraft()
            draft.organizationID = store.currentUser.organizationID
            _draft = State(initialValue: draft)
            _roles = State(initialValue: [])
        }
    }

    private var person: Person? {
        if case .edit(let id) = target { return store.person(id) }
        return nil
    }

    private var isYou: Bool { person?.id == store.currentUser.id }

    /// The only active admin keeps the admin role and stays active.
    private var isLastAdmin: Bool {
        guard let person else { return false }
        return store.people.filter { $0.active && $0.roles.contains(.admin) }.map(\.id) == [person.id]
    }

    private var hasChanges: Bool {
        guard let person else { return true }
        return draft != PersonDraft(person) || roles != person.roles
    }

    private var isComplete: Bool {
        !draft.givenName.trimmingCharacters(in: .whitespaces).isEmpty
            && !draft.surname.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Section("Name") {
                    field("Given name", text: $draft.givenName)
                    field("Surname", text: $draft.surname)
                }

                Section {
                    field("Linux user", text: $draft.linuxUser, prompt: "e.g. xx121", isAccount: true)
                    if person != nil {
                        Toggle("Active", isOn: $draft.active)
                            .disabled(isYou || (isLastAdmin && draft.active))
                    }
                } header: {
                    Text("Sign-in")
                } footer: {
                    if isYou {
                        Text("Nobody can deactivate themselves.")
                    } else if isLastAdmin {
                        Text("The last active admin stays active.")
                    } else {
                        Text("The username at the identity provider. People who have left are set inactive: they can't sign in, but stay in the history.")
                    }
                }

                Section("Organization") {
                    Picker("Organization", selection: $draft.organizationID) {
                        Text("None").tag(Int?.none)
                        ForEach(store.organizations) { Text($0.name).tag(Optional($0.id)) }
                    }
                    field("Position", text: $draft.position, prompt: "e.g. Qualitätssicherung")
                        .disabled(draft.organizationID == nil)
                }

                Section {
                    ForEach(LabRole.allCases, id: \.self) { role in
                        Toggle(isOn: Binding(
                            get: { roles.contains(role) },
                            set: { if $0 { roles.insert(role) } else { roles.remove(role) } })
                        ) {
                            Label {
                                Text(role.title)
                                if let description = store.roleDescriptions[role] { Text(description) }
                            } icon: {
                                Image(systemName: role.systemImage)
                            }
                        }
                        .disabled(role == .admin && isLastAdmin && roles.contains(.admin))
                    }
                } header: {
                    Text("Roles")
                } footer: {
                    Text(isLastAdmin ? "The last active admin keeps the admin role." : "Without roles a person can read everything but change nothing.")
                }

                Section {
                    TextField("Reason", text: $reason, prompt: Text("e.g. Takes over quality assurance"), axis: .vertical)
                } footer: {
                    Text("Goes into lucentBASE's log with the change.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle(person.map { String(localized: "Edit \($0.fullName)") } ?? String(localized: "New Person"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(person == nil ? "Add" : "Save") { save() }
                        .disabled(saving || !isComplete || !hasChanges || !store.can(.admin))
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 640)
        #endif
    }

    /// A text field with its name beside it, also on iOS, where a filled field shows no label.
    private func field(_ title: LocalizedStringKey, text: Binding<String>, prompt: LocalizedStringKey? = nil,
                       isAccount: Bool = false) -> some View {
        LabeledContent(title) {
            TextField(title, text: text, prompt: prompt.map { Text($0) })
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .monospaced(isAccount)
                .autocorrectionDisabled(isAccount)
                #if os(iOS)
                .textInputAutocapitalization(isAccount ? .never : .words)
                #endif
        }
    }

    private func save() {
        saving = true
        var draft = draft
        draft.givenName = draft.givenName.trimmingCharacters(in: .whitespaces)
        draft.surname = draft.surname.trimmingCharacters(in: .whitespaces)
        draft.linuxUser = draft.linuxUser.trimmingCharacters(in: .whitespaces)
        draft.position = draft.organizationID == nil ? "" : draft.position.trimmingCharacters(in: .whitespaces)
        let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                if let person {
                    try await store.save(person, as: draft, roles: roles, reason: reason.isEmpty ? nil : reason)
                } else {
                    let created = try await store.createPerson(draft, roles: roles, reason: reason.isEmpty ? nil : reason)
                    navigation.path.append(.person(created.id))
                }
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            saving = false
        }
    }
}
