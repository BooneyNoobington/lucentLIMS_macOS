import SwiftUI
import Charts

struct DashboardView: View {
    @Environment(LabStore.self) private var store
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                kpis
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 400), spacing: 16, alignment: .top)], spacing: 16) {
                    Card("Collections per week", systemImage: "chart.bar.xaxis") {
                        WeeklyChart(counts: store.weeklyCounts(), matrices: store.matrices)
                    }
                    Card("Status", systemImage: "chart.pie") {
                        StatusDonut(counts: statusCounts)
                    }
                    Card("Limit exceedances", systemImage: "exclamationmark.triangle") {
                        ExceedanceList(exceedances: Array(store.recentExceedances().prefix(6)))
                    }
                    Card(title: "Upcoming tasks", systemImage: "checklist") {
                        Button("All Tasks") { navigation.section = .tasks }
                            .buttonStyle(.borderless)
                    } content: {
                        UpcomingTasks(tasks: Array(store.openTasks.prefix(5)))
                    }
                    Card("Inbox", systemImage: "tray") {
                        Inbox(messages: store.inbox)
                    }
                }
            }
            .padding(24)
        }
        .background(Color.pageBackground)
        .navigationTitle("Dashboard")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Collection", systemImage: "plus") { navigation.presentNewCollection() }
                    .disabled(!store.can(.sampler))
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(greeting), \(store.currentUser.givenName)")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text(store.now, format: .dateTime.weekday(.wide).day().month(.wide).year())
                .foregroundStyle(.secondary)
        }
    }

    private var greeting: String {
        switch store.calendar.component(.hour, from: store.now) {
        case 5..<12: String(localized: "Good morning")
        case 12..<18: String(localized: "Good afternoon")
        default: String(localized: "Good evening")
        }
    }

    private var kpis: some View {
        let week = store.calendar.dateInterval(of: .weekOfYear, for: store.now)!
        let lastWeek = DateInterval(start: week.start.addingTimeInterval(-7 * 86_400), duration: 7 * 86_400)
        let inReview = store.collections.filter { store.status(of: $0) == .inReview }.count
        let overdue = store.openTasks.filter { store.isOverdue($0) }.count

        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 16) {
            Button { navigation.showCollections() } label: {
                KPITile(title: "Collections this week", value: "\(store.collections(sampledIn: week).count)",
                        detail: String(localized: "\(store.collections(sampledIn: lastWeek).count) last week"),
                        systemImage: "testtube.2", tint: .teal)
            }
            Button { navigation.showCollections(status: .inReview) } label: {
                KPITile(title: "Awaiting review", value: "\(inReview)",
                        detail: String(localized: "Four-eyes principle, SOP-009"),
                        systemImage: "eye", tint: .blue)
            }
            KPITile(title: "Limit exceedances", value: "\(store.recentExceedances().count)",
                    detail: String(localized: "In the last 30 days"),
                    systemImage: "exclamationmark.triangle.fill", tint: .red)
            Button { navigation.section = .tasks } label: {
                KPITile(title: "Open tasks", value: "\(store.openTasks.count)",
                        detail: String(localized: "\(overdue) overdue"),
                        systemImage: "checklist", tint: .purple)
            }
        }
        .buttonStyle(.plain)
    }

    private var statusCounts: [StatusCount] {
        let counts = Dictionary(grouping: store.collections, by: { store.status(of: $0) }).mapValues(\.count)
        return CollectionStatus.allCases.map { StatusCount(status: $0, count: counts[$0] ?? 0) }
    }
}

struct StatusCount: Identifiable {
    let status: CollectionStatus
    let count: Int
    var id: CollectionStatus { status }
}

private struct WeeklyChart: View {
    let counts: [WeeklyCount]
    let matrices: [Matrix]

    var body: some View {
        Chart(counts) { item in
            BarMark(x: .value("Week", item.week, unit: .weekOfYear),
                    y: .value("Collections", item.count))
                .foregroundStyle(by: .value("Matrix", item.matrix))
                .cornerRadius(3)
        }
        .chartForegroundStyleScale(domain: matrices.map(\.name), range: matrices.map(\.tint))
        .chartLegend(position: .bottom, alignment: .leading)
        .chartXAxis {
            AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        .frame(height: 230)
    }
}

private struct StatusDonut: View {
    let counts: [StatusCount]
    @State private var selectedAngle: Int?

    private var selected: StatusCount? {
        guard let selectedAngle else { return nil }
        var total = 0
        return counts.first { item in
            total += item.count
            return selectedAngle < total
        }
    }

    var body: some View {
        Chart(counts) { item in
            SectorMark(angle: .value("Collections", item.count), innerRadius: .ratio(0.62), angularInset: 2)
                .cornerRadius(5)
                .foregroundStyle(by: .value("Status", item.status.title))
                .opacity(selected == nil || selected?.status == item.status ? 1 : 0.35)
        }
        .chartForegroundStyleScale(domain: CollectionStatus.allCases.map(\.title),
                                   range: CollectionStatus.allCases.map(\.tint))
        .chartLegend(position: .trailing, alignment: .center, spacing: 24)
        .chartAngleSelection(value: $selectedAngle)
        .chartBackground { proxy in
            GeometryReader { geometry in
                if let anchor = proxy.plotFrame {
                    let frame = geometry[anchor]
                    VStack(spacing: 0) {
                        Text("\(selected?.count ?? counts.map(\.count).reduce(0, +))")
                            .font(.system(.title, design: .rounded, weight: .bold))
                            .contentTransition(.numericText())
                        Text(selected?.status.title ?? String(localized: "collections"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .animation(.snappy, value: selected?.status)
        .frame(height: 230)
    }
}

private struct ExceedanceList: View {
    @Environment(LabStore.self) private var store
    let exceedances: [Exceedance]

    var body: some View {
        if exceedances.isEmpty {
            ContentUnavailableView("No Exceedances", systemImage: "checkmark.shield",
                                   description: Text("All raw values of the last 30 days are within their limits."))
        } else {
            VStack(spacing: 0) {
                ForEach(exceedances) { item in
                    NavigationLink(value: Route.collection(item.collection.id)) {
                        row(item)
                    }
                    .buttonStyle(.plain)
                    if item.id != exceedances.last?.id { Divider() }
                }
            }
        }
    }

    private func row(_ item: Exceedance) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.parameter(item.effect.parameterID)?.name ?? "—")
                    .font(.callout.weight(.medium))
                HStack(spacing: 4) {
                    IdentifierView(identifier: item.collection.name)
                    Text("· \(store.locationName(of: item.collection))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(store.format(item.raw))
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.red)
                if let limit = store.limitPhrase(item.effect) {
                    Text(limit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

private struct UpcomingTasks: View {
    @Environment(LabStore.self) private var store
    let tasks: [LabTask]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(tasks) { task in
                HStack(spacing: 12) {
                    Avatar(person: store.person(task.assigneeID), size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.request)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        Text(store.person(task.assigneeID)?.fullName ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    DeadlineText(deadline: task.deadline, done: task.done, now: store.now)
                }
                .padding(.vertical, 8)
                if task.id != tasks.last?.id { Divider() }
            }
        }
    }
}

private struct Inbox: View {
    @Environment(LabStore.self) private var store
    let messages: [Message]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(messages) { message in
                Button {
                    store.perform { try await store.setRead(!message.read, message: message) }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Circle()
                            .fill(message.read ? Color.clear : Color.accentColor)
                            .frame(width: 8, height: 8)
                            .padding(.top, 11)
                        Avatar(person: store.person(message.senderID), size: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(store.person(message.senderID)?.fullName ?? "")
                                    .font(.callout.weight(message.read ? .regular : .semibold))
                                Spacer()
                                Text(message.sentAt, format: .relative(presentation: .named))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(message.subject)
                                .font(.callout)
                            Text(message.body)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(message.read ? "Mark as unread" : "Mark as read")
                if message.id != messages.last?.id { Divider() }
            }
        }
    }
}
