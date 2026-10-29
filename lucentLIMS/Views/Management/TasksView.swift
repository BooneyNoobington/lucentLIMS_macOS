import SwiftUI

struct TasksView: View {
    @Environment(LabStore.self) private var store
    @State private var onlyMine = false

    var body: some View {
        let tasks = store.tasks
            .filter { !onlyMine || $0.assigneeID == store.currentUser.id }
            .sorted { $0.deadline < $1.deadline }
        let endOfToday = store.calendar.date(byAdding: .day, value: 1, to: store.calendar.startOfDay(for: store.now))!
        let endOfWeek = store.calendar.date(byAdding: .day, value: 7, to: endOfToday)!

        List {
            group("Overdue", tasks.filter { store.isOverdue($0) })
            group("Today", tasks.filter { !$0.done && $0.deadline >= store.now && $0.deadline < endOfToday })
            group("Next 7 days", tasks.filter { !$0.done && $0.deadline >= endOfToday && $0.deadline < endOfWeek })
            group("Later", tasks.filter { !$0.done && $0.deadline >= endOfWeek })
            group("Done", tasks.filter(\.done).reversed())
        }
        .animation(.default, value: store.tasks)
        .navigationTitle("Tasks")
        .toolbar {
            ToolbarItem {
                Picker("Assigned to", selection: $onlyMine) {
                    Text("Everyone").tag(false)
                    Text("Me").tag(true)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
    }

    @ViewBuilder
    private func group(_ title: LocalizedStringKey, _ tasks: [LabTask]) -> some View {
        if !tasks.isEmpty {
            Section(title) {
                ForEach(tasks) { TaskRow(task: $0) }
            }
        }
    }
}

private struct TaskRow: View {
    @Environment(LabStore.self) private var store
    let task: LabTask

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                store.setDone(!task.done, taskID: task.id)
            } label: {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.done ? Color.accentColor : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .help(task.done ? "Mark as open" : "Mark as done")

            VStack(alignment: .leading, spacing: 4) {
                Text(task.request)
                    .font(.body.weight(.medium))
                    .strikethrough(task.done)
                    .foregroundStyle(task.done ? .secondary : .primary)
                if !task.description.isEmpty {
                    Text(task.description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Avatar(person: store.person(task.assignerID), size: 18)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Avatar(person: store.person(task.assigneeID), size: 18)
                    Text(store.person(task.assigneeID)?.fullName ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.tertiary)
                    DeadlineText(deadline: task.deadline, done: task.done, now: store.now)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
