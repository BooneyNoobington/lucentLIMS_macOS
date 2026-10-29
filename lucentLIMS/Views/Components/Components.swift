import SwiftUI

/// A collection identifier such as `0·Cyan·1·Rho`, with the colour segment shown as a dot.
struct IdentifierView: View {
    let identifier: String
    var separator = NumberingScheme.lucent.separator

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(identifier.components(separatedBy: separator).enumerated()), id: \.offset) { index, part in
                if index > 0 {
                    Text(separator).foregroundStyle(.tertiary)
                }
                if let colour = Color(numberingColour: part) {
                    HStack(spacing: 2) {
                        Image(systemName: "circle.fill")
                            .imageScale(.small)
                            .foregroundStyle(colour.gradient)
                        Text(part)
                    }
                } else {
                    Text(part)
                }
            }
        }
        .fontWeight(.medium)
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(identifier.replacingOccurrences(of: separator, with: " "))
    }
}

struct StatusBadge: View {
    let status: CollectionStatus

    var body: some View {
        Label(status.title, systemImage: status.systemImage)
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(status.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(status.tint.opacity(0.14), in: Capsule())
            .fixedSize()
    }
}

struct Avatar: View {
    let person: Person?
    var size: CGFloat = 28

    var body: some View {
        Text(person?.initials ?? "?")
            .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill((person?.tint ?? .gray).gradient))
            .accessibilityLabel(person?.fullName ?? "")
    }
}

struct MatrixLabel: View {
    let matrix: Matrix?

    var body: some View {
        Label {
            Text(matrix?.name ?? "—")
        } icon: {
            Image(systemName: matrix?.systemImage ?? "questionmark")
                .foregroundStyle(matrix?.tint ?? .gray)
        }
    }
}

/// A rounded panel for the dashboard.
struct Card<Content: View, Accessory: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                Spacer()
                accessory
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.separator.opacity(0.6), lineWidth: 0.5)
        }
    }
}

extension Card where Accessory == EmptyView {
    init(_ title: LocalizedStringKey, systemImage: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, systemImage: systemImage, accessory: { EmptyView() }, content: content)
    }
}

/// A big number with a caption, for the top of the dashboard.
struct KPITile: View {
    let title: LocalizedStringKey
    let value: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(value)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .contentTransition(.numericText())
                Spacer(minLength: 0)
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 8 }
            }
            Text(title)
                .font(.subheadline.weight(.medium))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.separator.opacity(0.6), lineWidth: 0.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

extension View {
    /// Detail pages show their name in a header, so on iOS the title stays small.
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

/// A deadline relative to now, red when it has passed.
struct DeadlineText: View {
    let deadline: Date
    let done: Bool
    let now: Date

    var body: some View {
        Label {
            Text(deadline, format: .relative(presentation: .named))
        } icon: {
            Image(systemName: overdue ? "exclamationmark.circle.fill" : "calendar")
        }
        .font(.caption)
        .foregroundStyle(overdue ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
    }

    private var overdue: Bool { !done && deadline < now }
}
