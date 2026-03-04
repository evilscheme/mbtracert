#!/usr/bin/env swift
import AppKit
import CoreGraphics

func generateIcon(pixelSize: Int) -> Data? {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let cgCtx = ctx.cgContext

    let s = CGFloat(pixelSize)
    let pad = s * 0.1

    // Background: rounded rect with gradient
    let bgRect = CGRect(x: 0, y: 0, width: s, height: s)
    let cornerRadius = s * 0.2
    let bgPath = CGPath(roundedRect: bgRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    cgCtx.addPath(bgPath)
    cgCtx.clip()

    // Gradient: dark teal to darker teal
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        CGColor(red: 0.1, green: 0.35, blue: 0.45, alpha: 1.0),
        CGColor(red: 0.05, green: 0.2, blue: 0.3, alpha: 1.0)
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
        cgCtx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])
    }

    // Draw stylized route: dots connected by lines
    let nodeRadius = s * 0.05
    let nodes: [(CGFloat, CGFloat)] = [
        (0.2, 0.8), (0.35, 0.55), (0.5, 0.7), (0.65, 0.4), (0.8, 0.25)
    ]

    // Draw connecting lines
    cgCtx.setStrokeColor(CGColor(red: 0.3, green: 0.8, blue: 0.9, alpha: 0.6))
    cgCtx.setLineWidth(s * 0.02)
    cgCtx.setLineCap(.round)
    for i in 0..<nodes.count - 1 {
        let (x1, y1) = nodes[i]
        let (x2, y2) = nodes[i + 1]
        cgCtx.move(to: CGPoint(x: pad + x1 * (s - 2 * pad), y: pad + y1 * (s - 2 * pad)))
        cgCtx.addLine(to: CGPoint(x: pad + x2 * (s - 2 * pad), y: pad + y2 * (s - 2 * pad)))
    }
    cgCtx.strokePath()

    // Draw nodes
    for (i, (x, y)) in nodes.enumerated() {
        let cx = pad + x * (s - 2 * pad)
        let cy = pad + y * (s - 2 * pad)
        let r = nodeRadius * (i == nodes.count - 1 ? 1.5 : 1.0)

        // Glow
        cgCtx.setFillColor(CGColor(red: 0.3, green: 0.8, blue: 0.9, alpha: 0.3))
        cgCtx.fillEllipse(in: CGRect(x: cx - r * 2, y: cy - r * 2, width: r * 4, height: r * 4))

        // Node
        cgCtx.setFillColor(CGColor(red: 0.4, green: 0.9, blue: 1.0, alpha: 1.0))
        cgCtx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    }

    NSGraphicsContext.current = nil
    return rep.representation(using: .png, properties: [:])
}

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

for (size, filename) in sizes {
    guard let png = generateIcon(pixelSize: size) else {
        print("Failed to generate \(filename)")
        continue
    }
    let url = URL(fileURLWithPath: outputDir).appendingPathComponent(filename)
    try! png.write(to: url)
    print("Generated \(filename) (\(size)x\(size))")
}
