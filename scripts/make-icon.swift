// Draws the lucentLIMS app icon: a glowing test tube on a teal plate.
// Usage: swift scripts/make-icon.swift <output directory>
// Writes icon-ios.png (full bleed) and icon-mac.png (plate with margin and shadow).
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [
        CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, alpha,
    ])!
}

func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
}

/// The artwork in a 1024 × 1024 box, y pointing down.
func drawArtwork(_ ctx: CGContext, plate: CGPath) {
    // Plate
    ctx.saveGState()
    ctx.addPath(plate)
    ctx.clip()
    ctx.drawLinearGradient(gradient([color(0x12907A), color(0x0B4F5E), color(0x082F45)]),
                           start: CGPoint(x: 120, y: 0), end: CGPoint(x: 900, y: 1024), options: [])
    // Soft light behind the tube
    ctx.drawRadialGradient(gradient([color(0x6FF2CF, 0.45), color(0x6FF2CF, 0)]),
                           startCenter: CGPoint(x: 512, y: 600), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 600), endRadius: 430, options: [])
    ctx.restoreGState()

    // Tube, tilted a little
    ctx.saveGState()
    ctx.translateBy(x: 512, y: 530)
    ctx.rotate(by: 14 * .pi / 180)
    ctx.translateBy(x: -512, y: -530)

    let width: CGFloat = 250, top: CGFloat = 200, bottom: CGFloat = 860
    let left = 512 - width / 2
    let tube = CGMutablePath()
    tube.move(to: CGPoint(x: left, y: top))
    tube.addLine(to: CGPoint(x: left, y: bottom - width / 2))
    tube.addArc(center: CGPoint(x: 512, y: bottom - width / 2), radius: width / 2,
                startAngle: .pi, endAngle: 0, clockwise: true)
    tube.addLine(to: CGPoint(x: left + width, y: top))

    // Liquid with glow
    let liquidTop: CGFloat = 470
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 90, color: color(0x7DFFD8, 0.9))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.addPath(tube)
    ctx.clip()
    ctx.clip(to: CGRect(x: 0, y: liquidTop, width: 1024, height: 1024))
    ctx.drawLinearGradient(gradient([color(0xB8FFE9), color(0x3FE0B2), color(0x16B38D)]),
                           start: CGPoint(x: 512, y: liquidTop), end: CGPoint(x: 512, y: bottom), options: [])
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    // Meniscus
    ctx.setFillColor(color(0xE6FFF7, 0.9))
    ctx.fillEllipse(in: CGRect(x: left + 14, y: liquidTop - 14, width: width - 28, height: 28))

    // Bubbles
    ctx.setFillColor(color(0xFFFFFF, 0.6))
    for (x, y, r) in [(470.0, 700.0, 26.0), (560, 610, 17), (505, 560, 11), (545, 780, 13)] {
        ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }

    // Glass
    ctx.addPath(tube)
    ctx.setStrokeColor(color(0xFFFFFF, 0.92))
    ctx.setLineWidth(24)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()

    // Rim
    let rim = CGPath(roundedRect: CGRect(x: left - 34, y: top - 30, width: width + 68, height: 52),
                     cornerWidth: 26, cornerHeight: 26, transform: nil)
    ctx.addPath(rim)
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillPath()

    // Highlight on the glass
    ctx.setStrokeColor(color(0xFFFFFF, 0.45))
    ctx.setLineWidth(16)
    ctx.move(to: CGPoint(x: left + 46, y: top + 70))
    ctx.addLine(to: CGPoint(x: left + 46, y: 420))
    ctx.strokePath()
    ctx.restoreGState()

    // Sparkle
    func sparkle(at center: CGPoint, size: CGFloat) {
        let path = CGMutablePath()
        let waist = size * 0.18
        path.move(to: CGPoint(x: center.x, y: center.y - size))
        path.addQuadCurve(to: CGPoint(x: center.x + size, y: center.y), control: CGPoint(x: center.x + waist, y: center.y - waist))
        path.addQuadCurve(to: CGPoint(x: center.x, y: center.y + size), control: CGPoint(x: center.x + waist, y: center.y + waist))
        path.addQuadCurve(to: CGPoint(x: center.x - size, y: center.y), control: CGPoint(x: center.x - waist, y: center.y + waist))
        path.addQuadCurve(to: CGPoint(x: center.x, y: center.y - size), control: CGPoint(x: center.x - waist, y: center.y - waist))
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 40, color: color(0xFFFFFF, 0.9))
        ctx.addPath(path)
        ctx.setFillColor(color(0xFFFFFF))
        ctx.fillPath()
        ctx.restoreGState()
    }
    sparkle(at: CGPoint(x: 805, y: 205), size: 70)
    sparkle(at: CGPoint(x: 862, y: 335), size: 30)
}

func render(_ name: String, plate: (CGFloat) -> CGPath?, inset: CGFloat) {
    let size = 1024
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(size))
    ctx.scaleBy(x: 1, y: -1)

    let scale = (1024 - 2 * inset) / 1024
    if let shape = plate(scale) {
        // macOS: a plate with a shadow and a transparent margin
        ctx.saveGState()
        ctx.translateBy(x: inset, y: inset)
        ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 28, color: color(0x000000, 0.35))
        ctx.addPath(shape)
        ctx.setFillColor(color(0x0B4F5E))
        ctx.fillPath()
        ctx.restoreGState()
    }
    ctx.translateBy(x: inset, y: inset)
    ctx.scaleBy(x: scale, y: scale)
    drawArtwork(ctx, plate: plate(1).map { _ in
        CGPath(roundedRect: CGRect(x: 0, y: 0, width: 1024, height: 1024), cornerWidth: 230, cornerHeight: 230, transform: nil)
    } ?? CGPath(rect: CGRect(x: 0, y: 0, width: 1024, height: 1024), transform: nil))

    let image = ctx.makeImage()!
    let url = out.appendingPathComponent(name)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    print(url.path)
}

// iOS: full bleed, the system rounds the corners.
render("icon-ios.png", plate: { _ in nil }, inset: 0)
// macOS: 824 × 824 plate in a 1024 canvas.
render("icon-mac.png", plate: { scale in
    CGPath(roundedRect: CGRect(x: 0, y: 0, width: 1024 * scale, height: 1024 * scale),
           cornerWidth: 230 * scale, cornerHeight: 230 * scale, transform: nil)
}, inset: 100)
