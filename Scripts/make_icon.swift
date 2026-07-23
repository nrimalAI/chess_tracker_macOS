#!/usr/bin/env swift
// Renders the ChessTime app icon into Resources/Assets.xcassets.
// Run from the repo root:  swift Scripts/make_icon.swift

import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let outputDirectory = URL(fileURLWithPath: "Resources/Assets.xcassets/AppIcon.appiconset")

func drawIcon(side: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: side, height: side))
    image.lockFocus()

    guard let context = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }
    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    // Rounded-square base with a vertical gradient, matching macOS icon shape.
    let inset = side * 0.06
    let rect = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let radius = rect.width * 0.2237  // Apple's squircle corner ratio
    let shape = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    context.saveGState()
    shape.addClip()
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.36, green: 0.60, blue: 0.35, alpha: 1),
        NSColor(calibratedRed: 0.16, green: 0.34, blue: 0.22, alpha: 1),
    ])
    gradient?.draw(in: rect, angle: -90)
    context.restoreGState()

    // Chess pawn, centred and optically balanced.
    let glyph = "♟"
    let fontSize = side * 0.60
    let font = NSFont.systemFont(ofSize: fontSize)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(calibratedWhite: 1.0, alpha: 0.95),
    ]
    let text = NSAttributedString(string: glyph, attributes: attributes)
    let textSize = text.size()
    let origin = NSPoint(
        x: rect.midX - textSize.width / 2,
        y: rect.midY - textSize.height / 2 + side * 0.02
    )
    text.draw(at: origin)

    image.unlockFocus()
    return image
}

try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for size in sizes {
    let image = drawIcon(side: CGFloat(size))
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:])
    else {
        print("failed to render \(size)")
        continue
    }
    // Force the pixel dimensions; lockFocus works in points on Retina displays.
    bitmap.size = NSSize(width: size, height: size)
    let url = outputDirectory.appendingPathComponent("icon_\(size).png")
    try? png.write(to: url)
    print("wrote \(url.lastPathComponent)")
}
