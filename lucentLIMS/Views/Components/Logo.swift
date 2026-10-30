import SwiftUI

extension Color {
    /// The colours of the logo (Branding/lucentLIMS-icon.svg).
    static let markBlue = Color(red: 0x59 / 255, green: 0xB9 / 255, blue: 0xF4 / 255)
    static let markMint = Color(red: 0x7A / 255, green: 0xDF / 255, blue: 0xC8 / 255)
    static let markDeepBlue = Color(red: 0x16 / 255, green: 0x8E / 255, blue: 0xD0 / 255)
}

/// The lucentLIMS mark: two translucent cards laid over each other to form an L. Drawn from the
/// geometry of Branding/lucentLIMS-icon.svg, so it stays sharp at any size.
struct LucentMark: View {
    var monochrome = false

    var body: some View {
        Canvas { context, size in
            let unit = min(size.width, size.height) / 256
            let origin = CGPoint(x: (size.width - 256 * unit) / 2, y: (size.height - 256 * unit) / 2)
            func card(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> Path {
                RoundedRectangle(cornerRadius: 20 * unit, style: .circular).path(in: CGRect(
                    x: origin.x + x * unit, y: origin.y + y * unit, width: width * unit, height: height * unit))
            }
            let vertical = card(0, 0, 144, 256)
            let horizontal = card(0, 112, 256, 144)
            if monochrome {
                context.fill(vertical, with: .foreground)
                context.fill(horizontal, with: .foreground)
                return
            }
            context.fill(vertical, with: .color(.markBlue))
            context.fill(horizontal, with: .color(.markMint))
            context.clip(to: vertical)
            context.fill(horizontal, with: .color(.markDeepBlue))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// The mark beside the wordmark: "lucent" bold, "LIMS" light.
struct LucentLogo: View {
    var height: CGFloat = 28

    var body: some View {
        HStack(spacing: height * 0.32) {
            LucentMark()
                .frame(width: height, height: height)
            Text(wordmark)
                .foregroundStyle(Color("Wordmark"))
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("lucentLIMS")
    }

    private var wordmark: AttributedString {
        var lucent = AttributedString("lucent")
        lucent.font = .system(size: height * 0.78, weight: .bold)
        var lims = AttributedString("LIMS")
        lims.font = .system(size: height * 0.78, weight: .light)
        var result = lucent + lims
        result.kern = -height * 0.02
        return result
    }
}

#Preview {
    VStack(spacing: 24) {
        LucentLogo(height: 56)
        LucentLogo()
        HStack(spacing: 16) {
            ForEach([64, 32, 16] as [CGFloat], id: \.self) { LucentMark().frame(width: $0, height: $0) }
            LucentMark(monochrome: true).frame(width: 32, height: 32)
        }
    }
    .padding()
}
