// Renders Resources/AppIcon.icns. Run via: swift Scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(pixels)

    // Rounded-square tile, inset like standard macOS icons.
    let tile = NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    let path = NSBezierPath(roundedRect: tile, xRadius: s * 0.18, yRadius: s * 0.18)
    NSGradient(colors: [NSColor(red: 0.16, green: 0.20, blue: 0.30, alpha: 1),
                        NSColor(red: 0.05, green: 0.06, blue: 0.10, alpha: 1)])!
        .draw(in: path, angle: -90)

    // Lens: outer ring, glass, highlight.
    let center = NSPoint(x: s * 0.5, y: s * 0.53)
    func circle(_ r: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
    }
    NSColor(white: 0.85, alpha: 1).setFill()
    circle(s * 0.22).fill()
    NSGradient(colors: [NSColor(red: 0.20, green: 0.45, blue: 0.95, alpha: 1),
                        NSColor(red: 0.04, green: 0.08, blue: 0.25, alpha: 1)])!
        .draw(in: circle(s * 0.17), relativeCenterPosition: NSPoint(x: -0.3, y: 0.3))
    NSColor(white: 1, alpha: 0.75).setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - s * 0.08, y: center.y + s * 0.03,
                                width: s * 0.06, height: s * 0.06)).fill()

    // Slider track along the bottom, hinting at adjustments.
    let trackY = s * 0.2
    NSColor(white: 1, alpha: 0.25).setFill()
    NSBezierPath(roundedRect: NSRect(x: s * 0.25, y: trackY, width: s * 0.5, height: s * 0.025),
                 xRadius: s * 0.0125, yRadius: s * 0.0125).fill()
    NSColor(red: 0.35, green: 0.65, blue: 1, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: s * 0.52, y: trackY - s * 0.025, width: s * 0.075, height: s * 0.075)).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}

let output = root.appendingPathComponent("Resources/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
print("Wrote \(output.path)")
