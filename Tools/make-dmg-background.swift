#!/usr/bin/env swift
// Draws the picture behind the DMG window: the app on the left, Applications on
// the right, and an arrow saying which way to drag.
//
// Generated for the same reason as the app icon, and committed for the same
// reason too: `Tools/dmg-background.tiff` is a build input, and this is where it
// came from. Run it after changing the artwork:
//
//     swift Tools/make-dmg-background.swift
//
// The layout constants in scripts/release.sh place the icons on this picture, so
// a change to one of them is a change to both.

import AppKit

let toolsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let output = toolsDirectory.appendingPathComponent("dmg-background.tiff")

let width: CGFloat = 640
let height: CGFloat = 400
/// Where Finder draws the icon names, measured from the top of the window. The
/// icons are centred 180pt down and are 128pt tall.
let labelY: CGFloat = 262

// The app icon's blue, which is also the only blue that works here. Finder draws
// icon names over this picture itself, black in light mode and white in dark, and
// offers no way to choose. A pale background loses the white and a deep one loses
// the black; both stay readable only around this luminance, so the gradient is
// kept narrow rather than running the icon's full range.
let top = (r: 0.35, g: 0.49, b: 0.96)
let bottom = (r: 0.27, g: 0.41, b: 0.88)

func mix(_ t: CGFloat) -> (r: Double, g: Double, b: Double) {
    let t = Double(t)
    return (top.r + (bottom.r - top.r) * t, top.g + (bottom.g - top.g) * t, top.b + (bottom.b - top.b) * t)
}

func luminance(_ c: (r: Double, g: Double, b: Double)) -> Double {
    func linear(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
}

// Checked rather than trusted: a nudge to the colours above can quietly make the
// names unreadable in whichever appearance the person editing them is not using.
let behindLabel = luminance(mix(labelY / height))
let onBlack = (behindLabel + 0.05) / 0.05
let onWhite = 1.05 / (behindLabel + 0.05)
print(String(format: "label contrast: black %.2f:1, white %.2f:1", onBlack, onWhite))
guard onBlack >= 4, onWhite >= 4 else {
    fatalError("Finder's icon names would be hard to read on this background.")
}

func draw(in context: CGContext) {
    let space = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(
        colorsSpace: space,
        colors: [
            CGColor(colorSpace: space, components: [top.r, top.g, top.b, 1])!,
            CGColor(colorSpace: space, components: [bottom.r, bottom.g, bottom.b, 1])!,
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient, start: CGPoint(x: 0, y: height), end: .zero, options: []
    )

    // Level with the icons' centres, in the gap between them.
    let arrowY = height - 180
    let start: CGFloat = 265
    let end: CGFloat = 375
    let head: CGFloat = 26
    context.setStrokeColor(CGColor(gray: 1, alpha: 0.95))
    context.setLineWidth(10)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.move(to: CGPoint(x: start, y: arrowY))
    context.addLine(to: CGPoint(x: end, y: arrowY))
    context.move(to: CGPoint(x: end - head, y: arrowY + head))
    context.addLine(to: CGPoint(x: end, y: arrowY))
    context.addLine(to: CGPoint(x: end - head, y: arrowY - head))
    context.strokePath()

    let previous = NSGraphicsContext.current
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    let title = NSAttributedString(
        string: "Drag BoardBar to Applications",
        attributes: [
            .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
    )
    let size = title.size()
    title.draw(at: CGPoint(x: (width - size.width) / 2, y: height - 70))
    NSGraphicsContext.current = previous
}

func writePNG(scale: CGFloat, to url: URL) throws {
    guard
        let context = CGContext(
            data: nil, width: Int(width * scale), height: Int(height * scale),
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else { throw CocoaError(.fileWriteUnknown) }
    context.scaleBy(x: scale, y: scale)
    draw(in: context)
    guard
        let image = context.makeImage(),
        let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    else { throw CocoaError(.fileWriteUnknown) }
    try data.write(to: url)
}

// Both scales in one file, which is the only form Finder will pick the sharp one
// from. A lone 2x PNG shows at twice the size and is cropped by the window.
let temporary = FileManager.default.temporaryDirectory
    .appendingPathComponent("boardbar-dmg-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporary) }
let standard = temporary.appendingPathComponent("background.png")
let retina = temporary.appendingPathComponent("background@2x.png")
try writePNG(scale: 1, to: standard)
try writePNG(scale: 2, to: retina)

let tiffutil = Process()
tiffutil.executableURL = URL(fileURLWithPath: "/usr/bin/tiffutil")
tiffutil.arguments = ["-cathidpicheck", standard.path, retina.path, "-out", output.path]
try tiffutil.run()
tiffutil.waitUntilExit()
guard tiffutil.terminationStatus == 0 else { fatalError("tiffutil failed") }
print("wrote \(output.lastPathComponent)")
