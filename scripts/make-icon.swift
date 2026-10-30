// Draws the lucentLIMS app icons from the logo: two translucent cards forming an L.
// The geometry and colours are those of Branding/lucentLIMS-icon.svg.
//
// Usage: swift scripts/make-icon.swift <output directory>
// Writes icon-ios.png (light, full bleed), icon-ios-dark.png and icon-ios-tinted.png (the mark
// on transparency, for iOS's dark and tinted icons) and icon-mac.png (a plate with margin and
// shadow).
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

struct MarkColors {
    var vertical: CGColor
    var horizontal: CGColor
    var overlap: CGColor
}

let brand = MarkColors(vertical: color(0x59B9F4), horizontal: color(0x7ADFC8), overlap: color(0x168ED0))
// Tinted icons are grey; iOS colours them. The overlap stays the darkest part.
let grey = MarkColors(vertical: color(0xC8C8C8), horizontal: color(0xF0F0F0), overlap: color(0x9A9A9A))

/// The mark in a square of `size` at `origin` (y pointing down). In the SVG the mark spans
/// 256 units: a 144 × 256 card, a 256 × 144 card, corner radius 20.
func drawMark(_ ctx: CGContext, origin: CGPoint, size: CGFloat, colors: MarkColors) {
    let unit = size / 256
    func card(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGPath {
        CGPath(roundedRect: CGRect(x: origin.x + x * unit, y: origin.y + y * unit, width: width * unit,
                                   height: height * unit),
               cornerWidth: 20 * unit, cornerHeight: 20 * unit, transform: nil)
    }
    let vertical = card(0, 0, 144, 256)
    let horizontal = card(0, 112, 256, 144)
    for (path, fill) in [(vertical, colors.vertical), (horizontal, colors.horizontal)] {
        ctx.addPath(path)
        ctx.setFillColor(fill)
        ctx.fillPath()
    }
    ctx.saveGState()
    ctx.addPath(vertical)
    ctx.clip()
    ctx.addPath(horizontal)
    ctx.setFillColor(colors.overlap)
    ctx.fillPath()
    ctx.restoreGState()
}

func render(_ name: String, draw: (CGContext) -> Void) {
    let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: 1024)
    ctx.scaleBy(x: 1, y: -1)
    draw(ctx)
    let url = out.appendingPathComponent(name)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    print(url.path)
}

/// A barely-there light background: white at the top, a cool grey-blue at the bottom.
func paper(_ ctx: CGContext, in rect: CGRect) {
    let gradient = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF), color(0xEDF3F8)] as CFArray,
                              locations: nil)!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: rect.minY),
                           end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
}

// iOS: full bleed, the system rounds the corners. The mark takes 56 % of the width.
let markSize: CGFloat = 576
let markOrigin = CGPoint(x: (1024 - markSize) / 2, y: (1024 - markSize) / 2)

render("icon-ios.png") { ctx in
    paper(ctx, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
    drawMark(ctx, origin: markOrigin, size: markSize, colors: brand)
}
render("icon-ios-dark.png") { ctx in
    drawMark(ctx, origin: markOrigin, size: markSize, colors: brand)
}
render("icon-ios-tinted.png") { ctx in
    drawMark(ctx, origin: markOrigin, size: markSize, colors: grey)
}

// macOS: an 824 × 824 plate in the 1024 canvas, with a soft shadow.
render("icon-mac.png") { ctx in
    let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: plate, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 24, color: color(0x000000, 0.28))
    ctx.addPath(shape)
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    paper(ctx, in: plate)
    ctx.restoreGState()
    let size = plate.width * 0.56
    drawMark(ctx, origin: CGPoint(x: plate.midX - size / 2, y: plate.midY - size / 2), size: size, colors: brand)
}
