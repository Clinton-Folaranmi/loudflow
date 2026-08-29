#!/usr/bin/env swift
//
// Renders the LoudFlow app icon — the sage (#7E9A82) rounded square with a white microphone —
// at every macOS icon size, straight into Resources/Assets.xcassets/AppIcon.appiconset.
//
// Run from the project root:  swift scripts/make-icon.swift
//
import AppKit

let outDir = "Resources/Assets.xcassets/AppIcon.appiconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// Brand sage — the same `#7E9A82` used for the in-app logo mark (Theme.sage).
let sage = NSColor(srgbRed: 0x7E / 255.0, green: 0x9A / 255.0, blue: 0x82 / 255.0, alpha: 1)

// The Solar microphone icon that the design uses for the logo mark + widget (solar:microphone-3-bold).
let micSVG = "Resources/Assets.xcassets/solar-microphone-3-bold.imageset/solar-microphone-3-bold.svg"

/// Rasterizes the (vector) Solar mic at `target` px and paints it white.
func whiteMic(target: CGFloat) -> NSImage? {
    guard let svg = NSImage(contentsOfFile: micSVG) else { return nil }
    let out = NSImage(size: NSSize(width: target, height: target))
    out.lockFocus()
    svg.draw(in: NSRect(x: 0, y: 0, width: target, height: target))   // renders as black (currentColor)
    NSColor.white.set()
    NSRect(x: 0, y: 0, width: target, height: target).fill(using: .sourceAtop)   // → white through the alpha
    out.unlockFocus()
    return out
}

func renderPNG(pixel: Int) -> Data? {
    let size = CGFloat(pixel)
    // Explicit 1× bitmap — NSImage.lockFocus would use the screen's 2× backing scale and
    // double the pixel dimensions, which actool rejects.
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixel, pixelsHigh: pixel,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    rep.size = NSSize(width: size, height: size)

    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx

    // Sage rounded square with a small margin (Big Sur-style squircle-ish).
    let inset = size * 0.075
    let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let radius = rect.width * 0.235
    sage.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()

    // White Solar microphone, centered.
    let target = size * 0.52
    if let mic = whiteMic(target: target) {
        mic.draw(in: NSRect(x: (size - target) / 2, y: (size - target) / 2, width: target, height: target))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

// (filename, pixel size)
let outputs: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

for (name, px) in outputs {
    guard let data = renderPNG(pixel: px) else { print("failed: \(name)"); continue }
    try? data.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
    print("wrote \(name) (\(px)px)")
}

// Asset-catalog manifest.
let contents = """
{
  "images" : [
    { "idiom" : "mac", "scale" : "1x", "size" : "16x16", "filename" : "icon_16x16.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "16x16", "filename" : "icon_16x16@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "32x32", "filename" : "icon_32x32.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "32x32", "filename" : "icon_32x32@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "128x128", "filename" : "icon_128x128.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "128x128", "filename" : "icon_128x128@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "256x256", "filename" : "icon_256x256.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "256x256", "filename" : "icon_256x256@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "512x512", "filename" : "icon_512x512.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "512x512", "filename" : "icon_512x512@2x.png" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
try? contents.write(toFile: "\(outDir)/Contents.json", atomically: true, encoding: .utf8)
print("wrote Contents.json")
