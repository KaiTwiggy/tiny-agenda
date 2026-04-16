#!/usr/bin/env swift
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "master1024.png"
let w = 1024
let h = 1024

guard
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: w,
        pixelsHigh: h,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 32
    )
else {
    fputs("error: could not create bitmap\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.isFlipped = true
guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }

let rect = CGRect(x: 0, y: 0, width: w, height: h)

// Squircle clip
let bgPath = NSBezierPath(roundedRect: rect.insetBy(dx: 32, dy: 32), xRadius: 230, yRadius: 230)
bgPath.addClip()

let colors = [
    NSColor(red: 0.19, green: 0.18, blue: 0.53, alpha: 1).cgColor,
    NSColor(red: 0.49, green: 0.23, blue: 0.93, alpha: 1).cgColor,
    NSColor(red: 0.03, green: 0.57, blue: 0.70, alpha: 1).cgColor,
]
let loc: [CGFloat] = [0, 0.48, 1]
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: loc)!
ctx.drawLinearGradient(grad, start: .zero, end: CGPoint(x: w, y: h), options: [])

ctx.resetClip()
bgPath.addClip()
let glow = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        NSColor(red: 0.96, green: 0.45, blue: 0.71, alpha: 0.45).cgColor,
        NSColor(red: 0.65, green: 0.55, blue: 0.98, alpha: 0.12).cgColor,
        NSColor(red: 0.19, green: 0.18, blue: 0.53, alpha: 0).cgColor,
    ] as CFArray,
    locations: [0, 0.45, 1]
)!
ctx.drawRadialGradient(
    glow,
    startCenter: CGPoint(x: w * 0.28, y: h * 0.22),
    startRadius: 0,
    endCenter: CGPoint(x: w * 0.28, y: h * 0.22),
    endRadius: h * 0.75,
    options: []
)

ctx.resetClip()
bgPath.addClip()
let sea = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        NSColor(red: 0.13, green: 0.83, blue: 0.93, alpha: 0.35).cgColor,
        NSColor(red: 0.03, green: 0.57, blue: 0.70, alpha: 0).cgColor,
    ] as CFArray,
    locations: [0, 1]
)!
ctx.drawRadialGradient(
    sea,
    startCenter: CGPoint(x: w * 0.82, y: h * 0.92),
    startRadius: 0,
    endCenter: CGPoint(x: w * 0.82, y: h * 0.92),
    endRadius: h * 0.55,
    options: []
)

NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.isFlipped = true
guard let ctx2 = NSGraphicsContext.current?.cgContext else { exit(1) }

let sheet = CGRect(x: 152, y: 208, width: 720, height: 640)
ctx2.setFillColor(NSColor(red: 0.98, green: 0.96, blue: 1.0, alpha: 0.96).cgColor)
ctx2.addPath(NSBezierPath(roundedRect: sheet, xRadius: 56, yRadius: 56).cgPath)
ctx2.fillPath()

let headerRect = CGRect(x: 152, y: 208, width: 720, height: 132)
ctx2.setFillColor(NSColor(red: 0.30, green: 0.11, blue: 0.58, alpha: 0.92).cgColor)
ctx2.addPath(NSBezierPath(roundedRect: headerRect, xRadius: 56, yRadius: 56).cgPath)
ctx2.fillPath()
ctx2.setFillColor(NSColor(red: 0.30, green: 0.11, blue: 0.58, alpha: 0.92).cgColor)
ctx2.fill(CGRect(x: 152, y: 208 + 56, width: 720, height: 76))

ctx2.setFillColor(NSColor(red: 0.77, green: 0.71, blue: 0.98, alpha: 0.9).cgColor)
for cx in [280, 512, 744] {
    ctx2.fillEllipse(in: CGRect(x: CGFloat(cx) - 28, y: 246, width: 56, height: 56))
}

let cell: CGFloat = 88
let gap: CGFloat = 28
let startX: CGFloat = 232
let startY: CGFloat = 420

for row in 0 ..< 3 {
    for col in 0 ..< 5 {
        let x = startX + CGFloat(col) * (cell + gap)
        let y = startY + CGFloat(row) * (cell + gap)
		let c = CGRect(x: x, y: y, width: cell, height: cell)
		let r = NSBezierPath(roundedRect: c, xRadius: 20, yRadius: 20)
		if row == 1 && col == 1 {
			ctx2.setFillColor(NSColor(red: 0.96, green: 0.45, blue: 0.71, alpha: 1).cgColor)
		} else {
			ctx2.setFillColor(NSColor(red: 0.78, green: 0.82, blue: 0.99, alpha: 0.88).cgColor)
		}
        ctx2.addPath(r.cgPath)
        ctx2.fillPath()
    }
}

let star = NSBezierPath()
let sx: CGFloat = 780
let sy: CGFloat = 180
let pts: [CGPoint] = [
    CGPoint(x: sx, y: sy + 14),
    CGPoint(x: sx + 10, y: sy + 38),
    CGPoint(x: sx + 36, y: sy + 38),
    CGPoint(x: sx + 16, y: sy + 54),
    CGPoint(x: sx + 24, y: sy + 80),
    CGPoint(x: sx, y: sy + 64),
    CGPoint(x: sx - 24, y: sy + 80),
    CGPoint(x: sx - 16, y: sy + 54),
    CGPoint(x: sx - 36, y: sy + 38),
    CGPoint(x: sx - 10, y: sy + 38),
]
star.move(to: pts[0])
for p in pts.dropFirst() {
    star.line(to: p)
}
star.close()
ctx2.setFillColor(NSColor(red: 0.99, green: 0.90, blue: 0.60, alpha: 0.95).cgColor)
ctx2.addPath(star.cgPath)
ctx2.fillPath()

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else {
    fputs("error: png encode\n", stderr)
    exit(1)
}
do {
    try data.write(to: URL(fileURLWithPath: out))
} catch {
    fputs("error: write \(error)\n", stderr)
    exit(1)
}
