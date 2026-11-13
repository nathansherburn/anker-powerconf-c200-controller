// Renders Resources/AppIcon.icns. Run via: swift Scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func gray(_ white: CGFloat, _ alpha: CGFloat = 1) -> NSColor { NSColor(white: white, alpha: alpha) }

/// The front of the C200: a charcoal body, a glossy black panel, and a textured
/// shutter window holding the lens, which sits above the middle of the body.
func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(pixels)
    func rect(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> NSRect {
        NSRect(x: s * x0, y: s * y0, width: s * (x1 - x0), height: s * (y1 - y0))
    }
    func rounded(_ r: NSRect, _ radius: CGFloat) -> NSBezierPath {
        NSBezierPath(roundedRect: r, xRadius: s * radius, yRadius: s * radius)
    }

    // Body: matte charcoal rounded square, inset like standard macOS icons, with a soft shadow.
    let body = rounded(rect(0.1, 0.1, 0.9, 0.9), 0.18)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = gray(0, 0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
    shadow.shadowBlurRadius = s * 0.02
    shadow.set()
    gray(0.22).setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [gray(0.32), gray(0.17)])!.draw(in: body, angle: -90)
    gray(1, 0.12).setStroke()
    let rim = rounded(rect(0.1, 0.1, 0.9, 0.9).insetBy(dx: s * 0.004, dy: s * 0.004), 0.176)
    rim.lineWidth = s * 0.006
    rim.stroke()

    // Glossy black front panel, with a faint diagonal reflection.
    let panelRect = rect(0.13, 0.23, 0.87, 0.87)
    let panel = rounded(panelRect, 0.15)
    NSGradient(colors: [gray(0.09), gray(0.03)])!.draw(in: panel, angle: -90)
    NSGraphicsContext.saveGraphicsState()
    panel.addClip()
    let gloss = NSBezierPath()
    gloss.move(to: NSPoint(x: s * 0.13, y: s * 0.87))
    gloss.line(to: NSPoint(x: s * 0.62, y: s * 0.87))
    gloss.line(to: NSPoint(x: s * 0.13, y: s * 0.40))
    gloss.close()
    gray(1, 0.05).setFill()
    gloss.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Shutter window: matte grey around the lens.
    let center = NSPoint(x: s * 0.5, y: s * 0.555)
    let windowRect = rect(0.22, 0.29, 0.78, 0.82)
    let window = rounded(windowRect, 0.095)
    NSGradient(colors: [gray(0.34), gray(0.16)])!
        .draw(in: window, relativeCenterPosition: NSPoint(x: -0.2, y: 0.3))
    gray(0, 0.5).setStroke()
    window.lineWidth = s * 0.004
    window.stroke()

    // Lens: ribbed bezel, black barrel, dark glass with a blue glint.
    func circle(_ r: CGFloat) -> NSBezierPath {
        let r = r * 1.12
        return NSBezierPath(ovalIn: NSRect(x: center.x - s * r, y: center.y - s * r, width: s * r * 2, height: s * r * 2))
    }
    NSGraphicsContext.saveGraphicsState()
    let lensShadow = NSShadow()
    lensShadow.shadowColor = gray(0, 0.5)
    lensShadow.shadowOffset = NSSize(width: 0, height: -s * 0.006)
    lensShadow.shadowBlurRadius = s * 0.015
    lensShadow.set()
    gray(0.1).setFill()
    circle(0.128).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [gray(0.42), gray(0.12)])!.draw(in: circle(0.128), angle: -60)
    for r in stride(from: CGFloat(0.12), through: 0.094, by: -0.0065) {
        let ring = circle(r)
        ring.lineWidth = s * 0.0025
        gray(0, 0.45).setStroke()
        ring.stroke()
    }
    gray(0.03).setFill()
    circle(0.088).fill()
    NSGradient(colors: [NSColor(red: 0.10, green: 0.16, blue: 0.30, alpha: 1),
                        NSColor(red: 0.01, green: 0.02, blue: 0.05, alpha: 1)])!
        .draw(in: circle(0.066), relativeCenterPosition: NSPoint(x: 0.25, y: -0.25))
    gray(0, 0.6).setStroke()
    let glassEdge = circle(0.066)
    glassEdge.lineWidth = s * 0.004
    glassEdge.stroke()
    NSColor(red: 0.45, green: 0.75, blue: 1, alpha: 0.95).setFill()
    circle(0.011).fill()
    gray(1, 0.18).setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - s * 0.056, y: center.y + s * 0.013,
                                width: s * 0.05, height: s * 0.034)).fill()

    // Glassy sheen across the window: a diagonal sweep from the top-left corner whose
    // crisp edge cuts straight across the lens.
    NSGraphicsContext.saveGraphicsState()
    window.addClip()
    let sheen = NSBezierPath()
    sheen.move(to: NSPoint(x: s * 0.22, y: s * 0.82))
    sheen.line(to: NSPoint(x: s * 0.80, y: s * 0.82))
    sheen.line(to: NSPoint(x: s * 0.22, y: s * 0.27))
    sheen.close()
    NSGradient(colors: [gray(1, 0.22), gray(1, 0.07)])!.draw(in: sheen, angle: -45)
    NSGraphicsContext.restoreGraphicsState()

    // Microphone grilles either side and the white status light in the middle.
    for x in [CGFloat(0.235), 0.765] {
        let grille = NSBezierPath(ovalIn: NSRect(x: s * (x - 0.032), y: s * 0.147, width: s * 0.064, height: s * 0.036))
        gray(0.1).setFill()
        grille.fill()
        gray(1, 0.08).setStroke()
        grille.lineWidth = s * 0.003
        grille.stroke()
    }
    NSGradient(colors: [gray(1, 0.35), gray(1, 0)])!
        .draw(in: NSBezierPath(ovalIn: rect(0.47, 0.135, 0.53, 0.195)), relativeCenterPosition: .zero)
    gray(0.98).setFill()
    NSBezierPath(ovalIn: rect(0.486, 0.151, 0.514, 0.179)).fill()

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
