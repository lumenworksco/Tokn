#!/usr/bin/swift
// Generates Tokn app icon PNGs at all required sizes.
// Run: swift scripts/generate_icons.swift

import CoreGraphics
import CoreText
import Foundation
import ImageIO

let outputDir = "Tokn/Assets.xcassets/AppIcon.appiconset"
let sizes = [16, 32, 64, 128, 256, 512, 1024]

for size in sizes {
    guard let image = renderIcon(size: size) else {
        print("Failed at \(size)")
        continue
    }
    let path = "\(outputDir)/icon_\(size)x\(size).png"
    let url = URL(fileURLWithPath: path)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        print("Can't create destination for \(path)")
        continue
    }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    print("✓ \(size)x\(size)")
}

func renderIcon(size: Int) -> CGImage? {
    let s = CGFloat(size)
    guard let ctx = CGContext(
        data: nil,
        width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: size * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    // ── Background: macOS rounded rect with purple gradient ──────────────────
    let radius = s * 0.2247
    let bg = CGMutablePath()
    bg.addRoundedRect(in: CGRect(x: 0, y: 0, width: s, height: s),
                      cornerWidth: radius, cornerHeight: radius)

    ctx.saveGState()
    ctx.addPath(bg)
    ctx.clip()

    // Gradient: violet-500 top → violet-900 bottom
    let gradColors = [
        CGColor(red: 0.549, green: 0.357, blue: 0.965, alpha: 1), // #8C5BF6
        CGColor(red: 0.227, green: 0.090, blue: 0.549, alpha: 1)  // #3A178C
    ] as CFArray
    if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: gradColors, locations: [0, 1]) {
        ctx.drawLinearGradient(grad,
                               start: CGPoint(x: s * 0.5, y: s),
                               end:   CGPoint(x: s * 0.5, y: 0),
                               options: [])
    }
    ctx.restoreGState()

    // ── Usage arc ─────────────────────────────────────────────────────────────
    // Arc sweeps 240°, starts at lower-left, fills 68% (nice demo value)
    let cx = s * 0.500
    let cy = s * 0.500
    let arcR  = s * 0.300
    let thick = s * 0.090

    // Convert from "clock" angles to CoreGraphics (CG y-axis is up)
    // We want the arc opening to face downward, centred at the bottom.
    // Start = 210° (lower-left), End = 330° (lower-right), sweeping counter-clockwise.
    // In CG radians (counter-clockwise from positive-x):
    let startDeg: CGFloat = 210 // lower-left
    let endDeg:   CGFloat = 330 // lower-right
    let startRad = startDeg * .pi / 180
    let endRad   = endDeg   * .pi / 180
    let fill: CGFloat = 0.68   // 68% filled

    // Track (faint white)
    ctx.saveGState()
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.18))
    ctx.setLineWidth(thick)
    ctx.setLineCap(.round)
    ctx.addArc(center: CGPoint(x: cx, y: cy), radius: arcR,
               startAngle: startRad, endAngle: endRad, clockwise: false)
    ctx.strokePath()
    ctx.restoreGState()

    // Progress (white)
    let totalSweep = (360 - (endDeg - startDeg)) * .pi / 180  // 240° in radians
    let progressEnd = startRad - totalSweep * fill             // counter-clockwise = subtract
    ctx.saveGState()
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    ctx.setLineWidth(thick)
    ctx.setLineCap(.round)
    ctx.addArc(center: CGPoint(x: cx, y: cy), radius: arcR,
               startAngle: startRad, endAngle: progressEnd, clockwise: true)
    ctx.strokePath()
    ctx.restoreGState()

    // ── Central "T" lettermark ────────────────────────────────────────────────
    let fontSize = s * 0.360
    let fontRef  = CTFontCreateWithName("Helvetica Neue Bold" as CFString, fontSize, nil)
    let white    = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    let attrs: [CFString: Any] = [
        kCTFontAttributeName:            fontRef,
        kCTForegroundColorAttributeName: white
    ]
    let attrStr  = CFAttributedStringCreate(nil, "T" as CFString, attrs as CFDictionary)!
    let line     = CTLineCreateWithAttributedString(attrStr)
    let bounds   = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])

    let textX = cx - bounds.width / 2 - bounds.origin.x
    let textY = cy - bounds.height / 2 - bounds.origin.y + s * 0.010
    ctx.textPosition = CGPoint(x: textX, y: textY)
    CTLineDraw(line, ctx)

    return ctx.makeImage()
}
