#!/usr/bin/env swift
// Draws BoardBar's app icon and writes every size the .appiconset asks for.
//
// The icon is generated rather than drawn by hand so it stays reproducible: the
// PNGs in Assets.xcassets are build inputs, and this file is the source they
// came from. Run it after changing the artwork:
//
//     swift Tools/make-appicon.swift
//
// It mirrors the menu-bar glyph — three columns of cards under a header rule —
// because the two are seen minutes apart and should read as the same object.

import AppKit

// Anchored to this file rather than to the working directory, so the script
// updates the real catalog no matter where it is run from. A cwd-relative path
// would happily create a second, stray catalog and report success.
let outputDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // Tools
    .deletingLastPathComponent()  // repository root
    .appendingPathComponent("BoardBar/Assets.xcassets/AppIcon.appiconset")

/// macOS icons are not edge-to-edge: the rounded square sits inside a fixed
/// margin of the canvas, and every other proportion here is measured against
/// that square rather than the canvas, so the artwork scales as one piece.
let canvas: CGFloat = 1024
let inset: CGFloat = 100
let squircle = CGRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2)
let cornerRadius = squircle.width * 0.2237

func drawIcon(in context: CGContext) {
    context.setShouldAntialias(true)
    let plate = CGPath(
        roundedRect: squircle, cornerWidth: cornerRadius, cornerHeight: cornerRadius,
        transform: nil
    )

    context.saveGState()
    context.addPath(plate)
    context.clip()
    let space = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(
        colorsSpace: space,
        colors: [
            CGColor(colorSpace: space, components: [0.30, 0.44, 0.93, 1])!,
            CGColor(colorSpace: space, components: [0.13, 0.22, 0.62, 1])!,
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: squircle.minX, y: squircle.maxY),
        end: CGPoint(x: squircle.maxX, y: squircle.minY),
        options: []
    )
    context.restoreGState()

    // Everything inside the plate is white at varying opacity rather than a
    // second hue: at 16pt the icon is a silhouette, and a two-colour interior
    // turns to mud long before the shapes stop being legible.
    let content = squircle.insetBy(dx: squircle.width * 0.17, dy: squircle.height * 0.20)
    let columnGap = content.width * 0.09
    let columnWidth = (content.width - columnGap * 2) / 3
    let cardRadius = columnWidth * 0.16

    // The header rule stands for the board's title row. It is what keeps the
    // three columns from reading as a bar chart.
    let headerHeight = content.height * 0.10
    let header = CGRect(
        x: content.minX, y: content.maxY - headerHeight,
        width: content.width * 0.62, height: headerHeight
    )
    context.setFillColor(CGColor(gray: 1, alpha: 0.95))
    context.addPath(
        CGPath(
            roundedRect: header, cornerWidth: headerHeight / 2, cornerHeight: headerHeight / 2,
            transform: nil
        )
    )
    context.fillPath()

    // Uneven column heights: a board where every column holds the same number
    // of cards is a board nobody has ever used.
    // One array, not a count and a parallel table of opacities: the column
    // heights are the number of alphas listed, so there is no pair to keep in
    // step and no way to edit one column into an out-of-range read.
    let columns: [[CGFloat]] = [[0.95, 0.80, 0.62], [0.95, 0.72], [0.88, 0.70, 0.52]]
    let cardsTop = content.maxY - headerHeight - content.height * 0.12
    let cardHeight = content.height * 0.20
    let cardGap = content.height * 0.075

    for (columnIndex, cards) in columns.enumerated() {
        let x = content.minX + (columnWidth + columnGap) * CGFloat(columnIndex)
        for (cardIndex, alpha) in cards.enumerated() {
            let y = cardsTop - cardHeight - (cardHeight + cardGap) * CGFloat(cardIndex)
            let card = CGRect(x: x, y: y, width: columnWidth, height: cardHeight)
            context.setFillColor(CGColor(gray: 1, alpha: alpha))
            context.addPath(
                CGPath(
                    roundedRect: card, cornerWidth: cardRadius, cornerHeight: cardRadius,
                    transform: nil
                )
            )
            context.fillPath()
        }
    }
}

/// Rendered at the exact pixel size rather than downsampled from one master, so
/// the small sizes get real hinting from the rasteriser instead of the blur a
/// 1024→16 resample leaves behind.
func writePNG(pixels: Int, to url: URL) throws {
    guard
        let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else { throw CocoaError(.fileWriteUnknown) }

    let scale = CGFloat(pixels) / canvas
    context.scaleBy(x: scale, y: scale)
    drawIcon(in: context)

    guard
        let image = context.makeImage(),
        let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    else { throw CocoaError(.fileWriteUnknown) }
    try data.write(to: url)
}

let sizes = [16, 32, 64, 128, 256, 512, 1024]
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
for size in sizes {
    let url = outputDirectory.appendingPathComponent("icon_\(size).png")
    try writePNG(pixels: size, to: url)
    print("wrote \(url.lastPathComponent)")
}
