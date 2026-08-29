#!/usr/bin/env swift
//
// Renders the DMG installer background: desk-colored backdrop, a sage arrow pointing from the
// app to the Applications folder, and a short instruction. The bitmap is 1200×800px backing a
// 600×400pt image, so it stays crisp on Retina. Drawing is done in 600×400 point coordinates.
//
import AppKit

let W: CGFloat = 600, H: CGFloat = 400

let desk  = NSColor(srgbRed: 0xDC/255.0, green: 0xE5/255.0, blue: 0xDA/255.0, alpha: 1)
let sage  = NSColor(srgbRed: 0x7E/255.0, green: 0x9A/255.0, blue: 0x82/255.0, alpha: 1)
let deep  = NSColor(srgbRed: 0x3F/255.0, green: 0x59/255.0, blue: 0x43/255.0, alpha: 1)
let muted = NSColor(srgbRed: 0x8A/255.0, green: 0x91/255.0, blue: 0x88/255.0, alpha: 1)

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W*2), pixelsHigh: Int(H*2),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
rep.size = NSSize(width: W, height: H)          // 600×400pt over 1200×800px → @2x
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx

// Backdrop
desk.setFill()
NSRect(x: 0, y: 0, width: W, height: H).fill()

// Arrow, centered between the two icon slots (icons at window x=150 and x=450, y=200 top-down;
// this context is bottom-left, so vertical center = H/2).
let midY = H / 2
sage.setFill()
let ax0: CGFloat = 250, ax1: CGFloat = 348, shaftH: CGFloat = 9
NSBezierPath(roundedRect: NSRect(x: ax0, y: midY - shaftH/2, width: ax1 - ax0, height: shaftH),
             xRadius: shaftH/2, yRadius: shaftH/2).fill()
let head = NSBezierPath()
let hh: CGFloat = 22
head.move(to: NSPoint(x: ax1, y: midY - hh))
head.line(to: NSPoint(x: ax1 + hh, y: midY))
head.line(to: NSPoint(x: ax1, y: midY + hh))
head.close()
head.fill()

// Text
func draw(_ text: String, font: NSFont, color: NSColor, topOffset: CGFloat) {
    let p = NSMutableParagraphStyle(); p.alignment = .center
    let str = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: p])
    let size = str.size()
    // topOffset = points down from the top edge; convert to bottom-left y.
    let y = H - topOffset - size.height
    str.draw(in: NSRect(x: 0, y: y, width: W, height: size.height))
}
draw("Drag LoudFlow onto Applications", font: .systemFont(ofSize: 21, weight: .bold), color: deep, topOffset: 40)
draw("Then open it from Applications and grant Microphone + Accessibility.",
     font: .systemFont(ofSize: 12, weight: .medium), color: muted, topOffset: 72)

NSGraphicsContext.restoreGraphicsState()
if let data = rep.representation(using: .png, properties: [:]) {
    try? data.write(to: URL(fileURLWithPath: "scripts/dmg-bg.png"))
    print("wrote scripts/dmg-bg.png")
}
