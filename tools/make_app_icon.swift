// Renders the Cab Hustle app icon.
//
// Draws an original flat, top-down taxi at 1024x1024, then flattens the result
// onto an opaque bitmap with no alpha channel — Apple rejects a marketing icon
// that carries one. `tools/generate_app_icons.sh` downsamples the output into
// the full iOS icon set.
//
// Build and run:
//   swiftc -O -o /tmp/make_app_icon tools/make_app_icon.swift
//   /tmp/make_app_icon <output.png>

import AppKit
import Foundation

// AppKit drawing from a command-line tool needs the shared application.
_ = NSApplication.shared

let side = 1024

// `--mark` draws the taxi alone on a transparent background, for the launch
// screen, where the storyboard supplies the backdrop colour. Without it the
// full opaque app icon is rendered.
let args = Array(CommandLine.arguments.dropFirst())
let markOnly = args.contains("--mark")
guard let outputPath = args.first(where: { !$0.hasPrefix("--") }), args.count <= 2 else {
    FileHandle.standardError.write("usage: make_app_icon <output.png> [--mark]\n".data(using: .utf8)!)
    exit(2)
}

func rgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
    NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
}

let asphaltTop = rgb(0x36, 0x3E, 0x51)
let asphaltBottom = rgb(0x14, 0x17, 0x1F)
let taxiYellow = rgb(0xFF, 0xC6, 0x1A)
let taxiYellowDeep = rgb(0xE8, 0xA5, 0x0C)
let glass = rgb(0x1B, 0x1F, 0x29)
let checkerLight = rgb(0xF7, 0xF7, 0xF7)

func makeRep(alpha: Bool) -> NSBitmapImageRep {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: side,
        pixelsHigh: side,
        bitsPerSample: 8,
        samplesPerPixel: alpha ? 4 : 3,
        hasAlpha: alpha,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        FileHandle.standardError.write("could not allocate bitmap\n".data(using: .utf8)!)
        exit(1)
    }
    return rep
}

/// Copies the opaque RGB channels out of an RGBA bitmap into a 3-sample one.
///
/// A no-alpha `NSBitmapImageRep` cannot back an `NSGraphicsContext`, so the
/// artwork is drawn with alpha and flattened here. The drawing covers the whole
/// canvas with an opaque background, so every pixel is alpha 255 and a straight
/// channel copy is exact.
func flatten(_ source: NSBitmapImageRep) -> NSBitmapImageRep {
    let dest = makeRep(alpha: false)
    guard let src = source.bitmapData, let dst = dest.bitmapData else {
        FileHandle.standardError.write("bitmap data unavailable\n".data(using: .utf8)!)
        exit(1)
    }
    let srcSPP = source.samplesPerPixel
    let dstSPP = dest.samplesPerPixel
    for y in 0..<side {
        let srcRow = y * source.bytesPerRow
        let dstRow = y * dest.bytesPerRow
        for x in 0..<side {
            let s = srcRow + x * srcSPP
            let d = dstRow + x * dstSPP
            dst[d] = src[s]
            dst[d + 1] = src[s + 1]
            dst[d + 2] = src[s + 2]
        }
    }
    return dest
}

func draw(into rep: NSBitmapImageRep, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
        FileHandle.standardError.write("could not bind graphics context\n".data(using: .utf8)!)
        exit(1)
    }
    NSGraphicsContext.current = ctx
    body()
    ctx.flushGraphics()
}

// --- Artwork, drawn into an alpha-capable bitmap (gradients and shadows need it).
let art = makeRep(alpha: true)
let canvas = NSRect(x: 0, y: 0, width: CGFloat(side), height: CGFloat(side))

draw(into: art) {
    if !markOnly {
        // Background: vertical asphalt gradient, edge to edge.
        NSGradient(starting: asphaltTop, ending: asphaltBottom)?.draw(in: canvas, angle: -90)
    }

    let bodyRect = NSRect(x: 252, y: 132, width: 520, height: 760)
    let taxi = NSBezierPath(roundedRect: bodyRect, xRadius: 120, yRadius: 120)

    // Wheels, drawn before the body so only the outer edge shows — the nubs are
    // what make the silhouette read as a car rather than a rounded rectangle.
    let wheelDark = rgb(0x0E, 0x10, 0x16)
    wheelDark.setFill()
    for wheelY in [CGFloat(236), CGFloat(628)] {
        for wheelX in [bodyRect.minX - 46, bodyRect.maxX - 54] {
            NSBezierPath(
                roundedRect: NSRect(x: wheelX, y: wheelY, width: 100, height: 160),
                xRadius: 30, yRadius: 30
            ).fill()
        }
    }

    // Ground shadow so the body separates from the asphalt at small sizes.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
    shadow.shadowBlurRadius = 44
    shadow.shadowOffset = NSSize(width: 0, height: -18)
    shadow.set()
    taxiYellow.setFill()
    taxi.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Body gradient for a little depth.
    NSGraphicsContext.saveGraphicsState()
    taxi.addClip()
    NSGradient(starting: taxiYellow, ending: taxiYellowDeep)?.draw(in: bodyRect, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Checker band — the taxi read, and the element that stays legible at 40px.
    NSGraphicsContext.saveGraphicsState()
    taxi.addClip()
    let band = NSRect(x: bodyRect.minX, y: 430, width: bodyRect.width, height: 104)
    checkerLight.setFill()
    band.fill()
    glass.setFill()
    let square: CGFloat = 52
    var column = 0
    var x = band.minX
    while x < band.maxX {
        let y = column.isMultiple(of: 2) ? band.minY : band.minY + square
        NSRect(x: x, y: y, width: square, height: square).fill()
        x += square
        column += 1
    }
    NSGraphicsContext.restoreGraphicsState()

    // Windshield (front, toward the top) and rear window.
    glass.setFill()
    NSBezierPath(roundedRect: NSRect(x: 322, y: 646, width: 380, height: 150),
                 xRadius: 58, yRadius: 58).fill()
    NSBezierPath(roundedRect: NSRect(x: 322, y: 214, width: 380, height: 134),
                 xRadius: 52, yRadius: 52).fill()

    // Roof light bar between the windshield and the checker band.
    checkerLight.setFill()
    NSBezierPath(roundedRect: NSRect(x: 432, y: 560, width: 160, height: 52),
                 xRadius: 24, yRadius: 24).fill()

    // Body outline last, so it sits above everything it bounds.
    glass.withAlphaComponent(0.5).setStroke()
    taxi.lineWidth = 10
    taxi.stroke()
}

// The app icon is flattened to drop the alpha channel; the launch mark keeps
// its transparency so it composites over the storyboard background.
let output = markOnly ? art : flatten(art)

guard let png = output.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("could not encode png\n".data(using: .utf8)!)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: outputPath))
print("wrote \(outputPath) — \(side)x\(side), alpha: \(output.hasAlpha)")
