// Removes the alpha channel from a PNG.
//
// Simulator screenshots carry an alpha channel, and App Store Connect rejects
// screenshots that have one. `sips` cannot drop it, so this reads the image and
// rewrites it as opaque RGB.
//
// Build and run:
//   swiftc -O -o /tmp/strip_alpha tools/strip_alpha.swift
//   /tmp/strip_alpha <input.png> <output.png>

import AppKit
import Foundation

_ = NSApplication.shared

let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 2 else {
    FileHandle.standardError.write("usage: strip_alpha <input.png> <output.png>\n".data(using: .utf8)!)
    exit(2)
}

guard let source = NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: args[0]))) else {
    FileHandle.standardError.write("could not read \(args[0])\n".data(using: .utf8)!)
    exit(1)
}

let width = source.pixelsWide
let height = source.pixelsHigh

// A no-alpha rep cannot back an NSGraphicsContext, so the channels are copied
// directly rather than redrawn. Screenshots are fully opaque, so a straight
// copy is exact — no compositing against a background is needed.
guard let dest = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: width,
    pixelsHigh: height,
    bitsPerSample: 8,
    samplesPerPixel: 3,
    hasAlpha: false,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let src = source.bitmapData, let dst = dest.bitmapData else {
    FileHandle.standardError.write("could not allocate output bitmap\n".data(using: .utf8)!)
    exit(1)
}

let srcSPP = source.samplesPerPixel
let dstSPP = dest.samplesPerPixel

for y in 0..<height {
    let srcRow = y * source.bytesPerRow
    let dstRow = y * dest.bytesPerRow
    for x in 0..<width {
        let s = srcRow + x * srcSPP
        let d = dstRow + x * dstSPP
        dst[d] = src[s]
        dst[d + 1] = src[s + 1]
        dst[d + 2] = src[s + 2]
    }
}

guard let png = dest.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("could not encode png\n".data(using: .utf8)!)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: args[1]))
print("\(args[1]) — \(width)x\(height), alpha: \(dest.hasAlpha)")
