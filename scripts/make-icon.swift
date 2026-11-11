// Renders the DChimera ("Data Chimera") app icon into DChimera/Assets.xcassets/AppIcon.appiconset.
// Contour style: a "D" drawn as one thick silver outline, a database cylinder outline inside its bowl,
// and a single curved horn growing from the top of the D — the only hint of the chimera.
// Run from the project folder:  swift scripts/make-icon.swift
import AppKit

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func strokeGradient(_ ctx: CGContext, _ path: CGPath, width: CGFloat, colors: [NSColor], from: CGPoint, to: CGPoint) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(\.cgColor) as CFArray, locations: nil)!
    ctx.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

func render(_ size: CGFloat) -> Data? {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gc
    let ctx = gc.cgContext
    let s = size / 1024
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }

    // Wet-asphalt squircle with a soft blue light and a glass rim.
    let base = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let squircle = NSBezierPath(roundedRect: base, xRadius: 185 * s, yRadius: 185 * s)
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
    shadow.shadowBlurRadius = 28 * s
    shadow.shadowOffset = NSSize(width: 0, height: -12 * s)
    shadow.set()
    NSGradient(colors: [color(0x3C434A), color(0x1C1F23)])!.draw(in: squircle, angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()
    NSGraphicsContext.current?.saveGraphicsState()
    squircle.addClip()
    NSGradient(colors: [color(0x5FA8E8, 0.16), color(0x5FA8E8, 0)])!
        .draw(fromCenter: NSPoint(x: 560 * s, y: 500 * s), radius: 0, toCenter: NSPoint(x: 560 * s, y: 500 * s), radius: 330 * s, options: [])
    NSGraphicsContext.current?.restoreGraphicsState()
    let rim = NSBezierPath(roundedRect: base.insetBy(dx: 3 * s, dy: 3 * s), xRadius: 182 * s, yRadius: 182 * s)
    rim.lineWidth = 4 * s
    color(0xFFFFFF, 0.12).setStroke()
    rim.stroke()

    let silver = [color(0xFFFFFF), color(0xCBD2DA), color(0x8F99A4)]
    let rain = [color(0x9BD0FF), color(0x5FA8E8), color(0x3F86C8)]

    // The D: stem, top bar, bowl, bottom bar — one closed contour.
    let d = CGMutablePath()
    d.move(to: pt(320, 262))
    d.addLine(to: pt(320, 742))
    d.addLine(to: pt(520, 742))
    d.addCurve(to: pt(520, 262), control1: pt(772, 742), control2: pt(772, 262))
    d.closeSubpath()
    strokeGradient(ctx, d, width: 50 * s, colors: silver, from: pt(0, 800), to: pt(0, 220))

    // The horn: grows out of the top of the stem as one tapered crescent, sweeping up and back.
    let horn = CGMutablePath()
    horn.move(to: pt(295, 742))
    horn.addCurve(to: pt(212, 874), control1: pt(292, 812), control2: pt(262, 862))
    horn.addCurve(to: pt(345, 742), control1: pt(280, 880), control2: pt(342, 828))
    horn.closeSubpath()
    ctx.saveGState()
    ctx.addPath(horn)
    ctx.clip()
    let hornGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: silver.map(\.cgColor) as CFArray, locations: nil)!
    ctx.drawLinearGradient(hornGradient, start: pt(0, 880), end: pt(0, 700), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()

    // The data: a cylinder outline inside the bowl of the D.
    let cx: CGFloat = 500, w: CGFloat = 232, eh: CGFloat = 70
    let top: CGFloat = 594, mid: CGFloat = 502, bottom: CGFloat = 410
    let cyl = CGMutablePath()
    cyl.addEllipse(in: CGRect(x: (cx - w / 2) * s, y: (top - eh / 2) * s, width: w * s, height: eh * s))
    cyl.move(to: pt(cx - w / 2, top))
    cyl.addLine(to: pt(cx - w / 2, bottom))
    cyl.move(to: pt(cx + w / 2, top))
    cyl.addLine(to: pt(cx + w / 2, bottom))
    for y in [mid, bottom] {
        let steps = 48
        for i in 0...steps {
            let t = CGFloat.pi + CGFloat(i) / CGFloat(steps) * .pi
            let p = pt(cx + cos(t) * w / 2, y + sin(t) * eh / 2)
            if i == 0 { cyl.move(to: p) } else { cyl.addLine(to: p) }
        }
    }
    strokeGradient(ctx, cyl, width: 26 * s, colors: rain, from: pt(0, 640), to: pt(0, 370))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let dir = URL(fileURLWithPath: "DChimera/Assets.xcassets/AppIcon.appiconset")
for size in [16, 32, 64, 128, 256, 512, 1024] {
    try! render(CGFloat(size))!.write(to: dir.appendingPathComponent("icon_\(size).png"))
}
print("icons written")
