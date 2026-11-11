import SwiftUI

// The Stalker theme ("the Zone"): soot and rust under a burnt dusk sky, bone-colored text,
// radiation-yellow accents, cut-corner military panels and hazard tape.

enum Zone {
    static let soot = Color(hex: 0x14120D)
    static let panel = Color(hex: 0x1C1A13)
    static let panelSolid = Color(hex: 0x211E16)
    static let edge = Color(hex: 0x5C4B2E)
    static let rust = Color(hex: 0xA4522A)
    static let yellow = Color(hex: 0xF2C230)
    static let amber = Color(hex: 0xE8A417)
    static let blood = Color(hex: 0xD8402E)
    static let bone = Color(hex: 0xE6DCC0)
    static let ink = Color(hex: 0x16130C)
}

// MARK: - Shapes

/// Rectangle with the four corners cut off at 45°.
struct Chamfer: Shape {
    var cut: CGFloat

    func path(in r: CGRect) -> Path {
        let c = min(cut, r.width / 2, r.height / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX + c, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + c))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
        p.addLine(to: CGPoint(x: r.maxX - c, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + c, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - c))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
        p.closeSubpath()
        return p
    }
}

/// The theme's outline for panels, buttons and chips. Rounded rectangle (capsule when `radius` is nil)
/// in most themes, cut corners in Stalker and Doom, small lab-tile corners in Breaking Bad.
/// `corners` keeps only Stalker's bright corner marks.
struct SkinShape: Shape {
    var radius: CGFloat?
    var corners = false

    static let capsule = SkinShape(radius: nil)

    func path(in rect: CGRect) -> Path {
        switch Skin.current.kind {
        case .stalker:
            let cut = Self.cut(radius: radius, rect: rect)
            return corners ? Self.cornerMarks(rect, cut: cut) : Chamfer(cut: cut).path(in: rect)
        case .doom:
            return corners ? Path() : Chamfer(cut: Self.cut(radius: radius, rect: rect)).path(in: rect)
        case .breakingBad:
            return corners ? Path() : RoundedRectangle(cornerRadius: min(radius ?? rect.height / 2, 7), style: .continuous).path(in: rect)
        default:
            if corners { return Path() }
            if let radius { return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect) }
            return Capsule().path(in: rect)
        }
    }

    /// Size of the cut corners in Stalker and Doom.
    static func cut(radius: CGFloat?, rect: CGRect) -> CGFloat {
        if Skin.current.kind == .doom {
            return radius.map { min($0 * 0.4, 8) } ?? min(rect.height * 0.22, 6)
        }
        return radius.map { min($0 * 0.55, 12) } ?? min(rect.height * 0.28, 8)
    }

    /// Short bracket along each cut corner; only panels big enough get them.
    private static func cornerMarks(_ r: CGRect, cut: CGFloat) -> Path {
        var p = Path()
        guard r.width > 120, r.height > 70 else { return p }
        let c = min(cut, r.width / 2, r.height / 2), a: CGFloat = 18
        func mark(_ points: [CGPoint]) {
            p.move(to: points[0])
            for point in points.dropFirst() { p.addLine(to: point) }
        }
        mark([CGPoint(x: r.minX, y: r.minY + c + a), CGPoint(x: r.minX, y: r.minY + c), CGPoint(x: r.minX + c, y: r.minY), CGPoint(x: r.minX + c + a, y: r.minY)])
        mark([CGPoint(x: r.maxX - c - a, y: r.minY), CGPoint(x: r.maxX - c, y: r.minY), CGPoint(x: r.maxX, y: r.minY + c), CGPoint(x: r.maxX, y: r.minY + c + a)])
        mark([CGPoint(x: r.maxX, y: r.maxY - c - a), CGPoint(x: r.maxX, y: r.maxY - c), CGPoint(x: r.maxX - c, y: r.maxY), CGPoint(x: r.maxX - c - a, y: r.maxY)])
        mark([CGPoint(x: r.minX + c + a, y: r.maxY), CGPoint(x: r.minX + c, y: r.maxY), CGPoint(x: r.minX, y: r.maxY - c), CGPoint(x: r.minX, y: r.maxY - c - a)])
        return p
    }
}

/// The radiation trefoil: three 60° blades around a dot.
struct RadiationSign: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.3
        var p = Path()
        for blade in 0..<3 {
            let mid = 90.0 + Double(blade) * 120
            p.move(to: CGPoint(x: center.x + inner * cos((mid - 30) * .pi / 180), y: center.y + inner * sin((mid - 30) * .pi / 180)))
            p.addArc(center: center, radius: outer, startAngle: .degrees(mid - 30), endAngle: .degrees(mid + 30), clockwise: false)
            p.addArc(center: center, radius: inner, startAngle: .degrees(mid + 30), endAngle: .degrees(mid - 30), clockwise: true)
            p.closeSubpath()
        }
        p.addEllipse(in: CGRect(x: center.x - outer * 0.19, y: center.y - outer * 0.19, width: outer * 0.38, height: outer * 0.38))
        return p
    }
}

/// Yellow-and-black hazard tape. With `base: false` only the dark stripes are drawn (a texture for yellow fills).
struct HazardStripes: View {
    var stripe: CGFloat = 7
    var base = true

    var body: some View {
        Canvas { ctx, size in
            if base { ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Zone.yellow)) }
            var x = -size.height
            while x < size.width + size.height {
                var p = Path()
                p.move(to: CGPoint(x: x, y: size.height))
                p.addLine(to: CGPoint(x: x + size.height, y: 0))
                p.addLine(to: CGPoint(x: x + size.height + stripe, y: 0))
                p.addLine(to: CGPoint(x: x + stripe, y: size.height))
                p.closeSubpath()
                ctx.fill(p, with: .color(Zone.ink))
                x += stripe * 2
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Toolbar dosimeter

/// Radiation meter in the toolbar: a calm background reading, a red spike while a query runs.
struct Dosimeter: View {
    let active: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: active ? 0.09 : 0.7)) { timeline in
            let level = Self.level(timeline.date.timeIntervalSinceReferenceDate, active: active)
            HStack(spacing: 7) {
                RadiationSign()
                    .fill(active ? Zone.blood : Zone.yellow)
                    .frame(width: 13, height: 13)
                    .shadow(color: (active ? Zone.blood : Zone.yellow).opacity(0.7), radius: active ? 5 : 2)
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(0..<8, id: \.self) { i in
                        Rectangle()
                            .fill(Double(i) / 8 < level ? Self.barColor(i) : Color.white.opacity(0.09))
                            .frame(width: 3, height: 5 + CGFloat(i) * 1.3)
                    }
                }
                Text(String(format: "%.2f μSv/h", 0.11 + level * (active ? 9 : 0.5)))
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit().width(.condensed))
                    .foregroundStyle(active ? Zone.blood : Theme.secondaryText)
                    .frame(width: 62, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .liquidGlass(SkinShape.capsule, clear: true, rim: active ? 0.5 : 0.2)
        }
        .help(active ? "Query running" : "Background radiation: calm")
    }

    private static func barColor(_ i: Int) -> Color {
        i < 4 ? Color(hex: 0x9FE870) : (i < 6 ? Zone.yellow : Zone.blood)
    }

    private static func level(_ t: TimeInterval, active: Bool) -> Double {
        let noise = GaugeNoise.value(t, step: active ? 0.09 : 0.7)
        return active ? 0.45 + 0.55 * noise : 0.1 + 0.18 * noise
    }
}

/// Jumpy pseudo-random value in 0...1 for toolbar gauges: the same for the same time step.
enum GaugeNoise {
    static func value(_ t: TimeInterval, step: Double, salt: UInt64 = 0) -> Double {
        var x = (UInt64(max(0, t / step)) &+ salt &* 0x632BE59BD9B4E019) &* 0x9E3779B97F4A7C15
        x ^= x >> 29
        x = x &* 0xBF58476D1CE4E5B9
        x ^= x >> 32
        return Double(x % 1000) / 1000
    }
}

/// The theme's toolbar gauge: Stalker dosimeter, Doom rage meter, Breaking Bad purity meter; a spinner elsewhere.
struct ThemeGauge: View {
    let active: Bool

    var body: some View {
        switch Skin.current.kind {
        case .stalker: Dosimeter(active: active)
        case .doom: RageMeter(active: active)
        case .breakingBad: PurityMeter(active: active)
        default:
            if active { ProgressView().controlSize(.small) }
        }
    }
}

// MARK: - Buttons

/// Push buttons of the painted themes (Stalker, Doom, Breaking Bad): the theme's own shape, accent fill when prominent.
struct SkinButtonStyle: ButtonStyle {
    var prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        SkinButtonBody(configuration: configuration, prominent: prominent)
    }
}

private struct SkinButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    @Environment(\.isEnabled) private var enabled
    @Environment(\.controlSize) private var controlSize
    @State private var hover = false

    var body: some View {
        let small = controlSize == .small || controlSize == .mini
        let skin = Skin.current
        configuration.label
            .font(.system(size: small ? 11.5 : 12.5, weight: .semibold).width(skin.fontWidth))
            .foregroundStyle(prominent ? Theme.onAccent : Theme.text)
            .padding(.horizontal, small ? 10 : 14)
            .frame(height: small ? 22 : 28)
            .contentShape(Rectangle())
            .liquidGlass(SkinShape.capsule, tint: prominent ? (skin.accent?.bottom ?? Color.accentColor) : nil, clear: !prominent, rim: hover ? 0.5 : 0.2)
            .opacity(enabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .onHover { hover = $0 }
    }
}

// MARK: - Backdrop

/// The Zone at dusk: burnt sky, a low sun in the haze, a power plant with its vent stack, an unfinished cooling tower,
/// power lines and dead trees. Drawn once per window size, no animation.
struct ZoneBackdrop: View {
    var body: some View {
        Canvas { ctx, size in ZonePainter.paint(&ctx, size) }
            .background(Zone.soot)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

/// Fine film grain over the whole window (static).
struct ZoneGrain: View {
    var body: some View {
        Canvas { ctx, size in
            var rng = ZoneRandom(seed: 0x51A1_4E55)
            let count = Int(size.width * size.height / 180)
            for _ in 0..<count {
                let x = rng.next() * size.width, y = rng.next() * size.height
                let d = 0.5 + rng.next() * 1.2
                let light = rng.next() > 0.6
                ctx.fill(Path(CGRect(x: x, y: y, width: d, height: d)),
                         with: .color(light ? Color(hex: 0xFFE2A8).opacity(0.025 + rng.next() * 0.03) : Color.black.opacity(0.06 + rng.next() * 0.08)))
            }
        }
        .allowsHitTesting(false)
    }
}

/// Small deterministic random generator so the scene is the same on every launch.
struct ZoneRandom {
    var seed: UInt64

    mutating func next() -> Double {
        seed ^= seed << 13
        seed ^= seed >> 7
        seed ^= seed << 17
        return Double(seed % 1_000_000) / 1_000_000
    }
}

enum ZonePainter {
    static func paint(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height
        let horizon = h * 0.7
        var rng = ZoneRandom(seed: 0x2545_F491_4F6C_DD1D)

        sky(&ctx, w, horizon)
        sun(&ctx, w, h, horizon)
        clouds(&ctx, w, horizon, &rng)
        treeLine(&ctx, w, horizon, &rng)
        coolingTower(&ctx, x: w * 0.3, base: horizon, width: max(90, w * 0.1), height: h * 0.17)
        powerPlant(&ctx, w, h, horizon)
        ground(&ctx, w, h, horizon)
        haze(&ctx, w, h, horizon)
        anomaly(&ctx, CGPoint(x: w * 0.36, y: horizon + (h - horizon) * 0.55), &rng)
        pylon(&ctx, x: w * 0.1, base: horizon + h * 0.05, height: h * 0.3)
        pylon(&ctx, x: w * 0.47, base: horizon + h * 0.015, height: h * 0.17)
        pylon(&ctx, x: w * 0.93, base: horizon + h * 0.035, height: h * 0.24)
        wires(&ctx, from: (w * 0.1, horizon + h * 0.05, h * 0.3), to: (w * 0.47, horizon + h * 0.015, h * 0.17))
        wires(&ctx, from: (w * 0.47, horizon + h * 0.015, h * 0.17), to: (w * 0.93, horizon + h * 0.035, h * 0.24))
        deadTree(&ctx, CGPoint(x: w * 0.025, y: h), length: h * 0.2, angle: -90, depth: 6, &rng)
        deadTree(&ctx, CGPoint(x: w * 0.2, y: horizon + h * 0.12), length: h * 0.09, angle: -92, depth: 5, &rng)
        deadTree(&ctx, CGPoint(x: w * 0.78, y: horizon + h * 0.09), length: h * 0.07, angle: -88, depth: 5, &rng)
    }

    private static let near = Color(hex: 0x0B0A07)

    private static func sky(_ ctx: inout GraphicsContext, _ w: CGFloat, _ horizon: CGFloat) {
        let gradient = Gradient(stops: [
            .init(color: Color(hex: 0x121110), location: 0),
            .init(color: Color(hex: 0x271F17), location: 0.38),
            .init(color: Color(hex: 0x5A361C), location: 0.74),
            .init(color: Color(hex: 0xB8642A), location: 1),
        ])
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: horizon + 2)), with: .linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: 0, y: horizon)))
    }

    private static func sun(_ ctx: inout GraphicsContext, _ w: CGFloat, _ h: CGFloat, _ horizon: CGFloat) {
        let c = CGPoint(x: w * 0.72, y: horizon - h * 0.06)
        let glow = Gradient(colors: [Color(hex: 0xFF9A48).opacity(0.42), Color(hex: 0xFF7A30).opacity(0.12), .clear])
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - w * 0.5, y: c.y - w * 0.5, width: w, height: w)),
                 with: .radialGradient(glow, center: c, startRadius: 0, endRadius: w * 0.5))
        let r = max(14, h * 0.035)
        let disc = Gradient(colors: [Color(hex: 0xFFE3A8), Color(hex: 0xFFB060).opacity(0.85), Color(hex: 0xFF9040).opacity(0)])
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 1.6, y: c.y - r * 1.6, width: r * 3.2, height: r * 3.2)),
                 with: .radialGradient(disc, center: c, startRadius: 0, endRadius: r * 1.6))
    }

    private static func clouds(_ ctx: inout GraphicsContext, _ w: CGFloat, _ horizon: CGFloat, _ rng: inout ZoneRandom) {
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 14))
            for i in 0..<9 {
                let y = horizon * (0.12 + 0.75 * rng.next())
                let cw = w * (0.25 + 0.4 * rng.next())
                let ch = 8 + 26 * rng.next()
                let x = w * rng.next() - cw * 0.3
                let lit = y > horizon * 0.6
                let color = lit ? Color(hex: 0x7A4422).opacity(0.55) : Color(hex: 0x15110D).opacity(0.65)
                layer.fill(Path(ellipseIn: CGRect(x: x, y: y, width: cw, height: ch)), with: .color(color))
                if i % 3 == 0 {
                    layer.fill(Path(ellipseIn: CGRect(x: x + cw * 0.2, y: y + ch * 0.55, width: cw * 0.6, height: max(3, ch * 0.25))),
                               with: .color(Color(hex: 0xE08A3E).opacity(0.25)))
                }
            }
        }
    }

    private static func treeLine(_ ctx: inout GraphicsContext, _ w: CGFloat, _ horizon: CGFloat, _ rng: inout ZoneRandom) {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: horizon + 4))
        var x: CGFloat = 0
        while x <= w {
            p.addLine(to: CGPoint(x: x, y: horizon - 3 - 12 * rng.next()))
            x += 3 + 7 * rng.next()
        }
        p.addLine(to: CGPoint(x: w, y: horizon + 4))
        p.closeSubpath()
        ctx.fill(p, with: .color(Color(hex: 0x2A2016)))
    }

    private static func coolingTower(_ ctx: inout GraphicsContext, x: CGFloat, base: CGFloat, width: CGFloat, height: CGFloat) {
        let half = width / 2, top = base - height
        var p = Path()
        p.move(to: CGPoint(x: x - half, y: base))
        p.addQuadCurve(to: CGPoint(x: x - half * 0.72, y: top), control: CGPoint(x: x - half * 0.52, y: base - height * 0.62))
        p.addLine(to: CGPoint(x: x + half * 0.72, y: top))
        p.addQuadCurve(to: CGPoint(x: x + half, y: base), control: CGPoint(x: x + half * 0.52, y: base - height * 0.62))
        p.closeSubpath()
        ctx.fill(p, with: .color(Color(hex: 0x241B13)))
        // Unfinished top: scaffolding ribs sticking out.
        for i in 0..<9 {
            let rx = x - half * 0.7 + CGFloat(i) * half * 0.175
            ctx.stroke(Path { $0.move(to: CGPoint(x: rx, y: top)); $0.addLine(to: CGPoint(x: rx, y: top - 5 - CGFloat(i % 3) * 3)) },
                       with: .color(Color(hex: 0x241B13)), lineWidth: 1.2)
        }
        ctx.fill(Path(CGRect(x: x - half * 0.72, y: top, width: half * 1.44, height: 2)), with: .color(Color(hex: 0x3A2A1C)))
    }

    private static func powerPlant(_ ctx: inout GraphicsContext, _ w: CGFloat, _ h: CGFloat, _ horizon: CGFloat) {
        let color = Color(hex: 0x1A140E)
        let x0 = w * 0.52, unit = max(1, h / 900)
        let blocks: [(CGFloat, CGFloat, CGFloat)] = [  // x offset (of w), width (of w), height (of h)
            (0.0, 0.07, 0.05), (0.06, 0.05, 0.085), (0.105, 0.09, 0.125), (0.19, 0.04, 0.07),
            (0.225, 0.08, 0.055), (0.30, 0.05, 0.04),
        ]
        for b in blocks {
            ctx.fill(Path(CGRect(x: x0 + w * b.0, y: horizon - h * b.2, width: w * b.1, height: h * b.2 + 3)), with: .color(color))
        }
        // Lit windows on the tall hall.
        for i in 0..<6 {
            ctx.fill(Path(CGRect(x: x0 + w * 0.112 + CGFloat(i) * w * 0.013, y: horizon - h * 0.1, width: 2.5 * unit, height: 1.6 * unit)),
                     with: .color(Color(hex: 0xFFB45A).opacity(i % 2 == 0 ? 0.55 : 0.25)))
        }
        // Ventilation stack with its lattice.
        let sx = x0 + w * 0.15, sBase = horizon - h * 0.125, sTop = horizon - h * 0.33
        let bw = w * 0.012, tw = w * 0.006
        var stack = Path()
        stack.move(to: CGPoint(x: sx - bw, y: sBase))
        stack.addLine(to: CGPoint(x: sx - tw, y: sTop))
        stack.addLine(to: CGPoint(x: sx + tw, y: sTop))
        stack.addLine(to: CGPoint(x: sx + bw, y: sBase))
        stack.closeSubpath()
        ctx.fill(stack, with: .color(color))
        let lw = w * 0.026
        var lattice = Path()
        lattice.move(to: CGPoint(x: sx - lw, y: sBase))
        lattice.addLine(to: CGPoint(x: sx - tw * 1.5, y: sTop + h * 0.03))
        lattice.move(to: CGPoint(x: sx + lw, y: sBase))
        lattice.addLine(to: CGPoint(x: sx + tw * 1.5, y: sTop + h * 0.03))
        let steps = 7
        for i in 0..<steps {
            let t0 = CGFloat(i) / CGFloat(steps), t1 = CGFloat(i + 1) / CGFloat(steps)
            let y0 = sBase + (sTop + h * 0.03 - sBase) * t0, y1 = sBase + (sTop + h * 0.03 - sBase) * t1
            let x0l = sx - lw + (lw - tw * 1.5) * t0, x1r = sx + lw - (lw - tw * 1.5) * t1
            lattice.move(to: CGPoint(x: x0l, y: y0))
            lattice.addLine(to: CGPoint(x: x1r, y: y1))
            lattice.move(to: CGPoint(x: sx + lw - (lw - tw * 1.5) * t0, y: y0))
            lattice.addLine(to: CGPoint(x: sx - lw + (lw - tw * 1.5) * t1, y: y1))
        }
        ctx.stroke(lattice, with: .color(color), lineWidth: max(1, unit))
        // Red warning light on top.
        let light = CGPoint(x: sx, y: sTop - 3)
        ctx.fill(Path(ellipseIn: CGRect(x: light.x - 9, y: light.y - 9, width: 18, height: 18)),
                 with: .radialGradient(Gradient(colors: [Zone.blood.opacity(0.8), .clear]), center: light, startRadius: 0, endRadius: 9))
        // Construction crane.
        let cx = x0 + w * 0.29, cTop = horizon - h * 0.2
        var crane = Path()
        crane.move(to: CGPoint(x: cx, y: horizon - h * 0.04))
        crane.addLine(to: CGPoint(x: cx, y: cTop))
        crane.move(to: CGPoint(x: cx - w * 0.025, y: cTop + 4))
        crane.addLine(to: CGPoint(x: cx + w * 0.08, y: cTop + 4))
        crane.move(to: CGPoint(x: cx, y: cTop - 8))
        crane.addLine(to: CGPoint(x: cx + w * 0.07, y: cTop + 4))
        crane.move(to: CGPoint(x: cx + w * 0.06, y: cTop + 4))
        crane.addLine(to: CGPoint(x: cx + w * 0.06, y: cTop + h * 0.06))
        ctx.stroke(crane, with: .color(color), lineWidth: max(1.5, 2 * unit))
    }

    private static func ground(_ ctx: inout GraphicsContext, _ w: CGFloat, _ h: CGFloat, _ horizon: CGFloat) {
        let gradient = Gradient(colors: [Color(hex: 0x1C170F), Color(hex: 0x100E0A), Color(hex: 0x080706)])
        ctx.fill(Path(CGRect(x: 0, y: horizon + 2, width: w, height: h - horizon)),
                 with: .linearGradient(gradient, startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: 0, y: h)))
    }

    private static func haze(_ ctx: inout GraphicsContext, _ w: CGFloat, _ h: CGFloat, _ horizon: CGFloat) {
        let band = h * 0.06
        let gradient = Gradient(colors: [.clear, Color(hex: 0xC0753A).opacity(0.16), .clear])
        ctx.fill(Path(CGRect(x: 0, y: horizon - band, width: w, height: band * 2)),
                 with: .linearGradient(gradient, startPoint: CGPoint(x: 0, y: horizon - band), endPoint: CGPoint(x: 0, y: horizon + band)))
    }

    /// An electrical anomaly crackling on the ground: blue glow and jagged arcs.
    private static func anomaly(_ ctx: inout GraphicsContext, _ c: CGPoint, _ rng: inout ZoneRandom) {
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 90, y: c.y - 40, width: 180, height: 80)),
                 with: .radialGradient(Gradient(colors: [Color(hex: 0x8FD8FF).opacity(0.35), Color(hex: 0x3A7FD0).opacity(0.1), .clear]),
                                       center: c, startRadius: 0, endRadius: 90))
        for _ in 0..<6 {
            var p = Path()
            var point = c
            p.move(to: point)
            let angle = rng.next() * .pi * 2
            for _ in 0..<5 {
                point.x += CGFloat(cos(angle)) * 12 + CGFloat(rng.next() - 0.5) * 16
                point.y += CGFloat(sin(angle)) * 6 + CGFloat(rng.next() - 0.5) * 10
                p.addLine(to: point)
            }
            ctx.stroke(p, with: .color(Color(hex: 0xCDEFFF).opacity(0.75)), lineWidth: 1)
        }
    }

    private static func pylon(_ ctx: inout GraphicsContext, x: CGFloat, base: CGFloat, height: CGFloat) {
        let top = base - height, legs = height * 0.16, arm = height * 0.3
        var p = Path()
        p.move(to: CGPoint(x: x - legs, y: base)); p.addLine(to: CGPoint(x: x - legs * 0.12, y: top))
        p.move(to: CGPoint(x: x + legs, y: base)); p.addLine(to: CGPoint(x: x + legs * 0.12, y: top))
        for i in 0..<6 {
            let t0 = CGFloat(i) / 6, t1 = CGFloat(i + 1) / 6
            let y0 = base - height * t0, y1 = base - height * t1
            let s0 = legs - (legs * 0.88) * t0, s1 = legs - (legs * 0.88) * t1
            p.move(to: CGPoint(x: x - s0, y: y0)); p.addLine(to: CGPoint(x: x + s1, y: y1))
            p.move(to: CGPoint(x: x + s0, y: y0)); p.addLine(to: CGPoint(x: x - s1, y: y1))
        }
        for level in [0.82, 0.62] as [CGFloat] {
            let y = base - height * level
            p.move(to: CGPoint(x: x - arm, y: y)); p.addLine(to: CGPoint(x: x + arm, y: y))
            p.move(to: CGPoint(x: x - arm, y: y)); p.addLine(to: CGPoint(x: x, y: y - height * 0.06))
            p.move(to: CGPoint(x: x + arm, y: y)); p.addLine(to: CGPoint(x: x, y: y - height * 0.06))
        }
        ctx.stroke(p, with: .color(near), lineWidth: max(1, height / 140))
    }

    /// Sagging wires between the cross-arm tips of two pylons (x, base, height).
    private static func wires(_ ctx: inout GraphicsContext, from a: (CGFloat, CGFloat, CGFloat), to b: (CGFloat, CGFloat, CGFloat)) {
        var p = Path()
        for level in [0.82, 0.62] as [CGFloat] {
            for side in [-1.0, 1.0] as [CGFloat] {
                let start = CGPoint(x: a.0 + side * a.2 * 0.3, y: a.1 - a.2 * level)
                let end = CGPoint(x: b.0 + side * b.2 * 0.3, y: b.1 - b.2 * level)
                p.move(to: start)
                p.addQuadCurve(to: end, control: CGPoint(x: (start.x + end.x) / 2, y: max(start.y, end.y) + abs(end.x - start.x) * 0.08))
            }
        }
        ctx.stroke(p, with: .color(near.opacity(0.85)), lineWidth: 0.8)
    }

    private static func deadTree(_ ctx: inout GraphicsContext, _ start: CGPoint, length: CGFloat, angle: Double, depth: Int, _ rng: inout ZoneRandom) {
        guard depth > 0, length > 2 else { return }
        let rad = angle * .pi / 180
        let end = CGPoint(x: start.x + CGFloat(cos(rad)) * length, y: start.y + CGFloat(sin(rad)) * length)
        ctx.stroke(Path { $0.move(to: start); $0.addLine(to: end) }, with: .color(near),
                   style: StrokeStyle(lineWidth: max(0.8, CGFloat(depth) * 1.1), lineCap: .round))
        let branches = depth > 4 ? 2 : (rng.next() > 0.4 ? 2 : 1)
        for i in 0..<branches {
            let spread = 18 + rng.next() * 26
            let turn = (i == 0 ? -spread : spread) + (rng.next() - 0.5) * 14
            deadTree(&ctx, end, length: length * (0.62 + rng.next() * 0.16), angle: angle + turn, depth: depth - 1, &rng)
        }
    }
}

// MARK: - Theme switch effect

/// Played when Stalker is turned on: an emission — red sky flash, flicker and a short shake.
struct EmissionEffect: View {
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            let e = timeline.date.timeIntervalSince(start)
            let fade = max(0, 1 - e / 1.5)
            let flicker = 0.78 + 0.22 * sin(e * 47) * sin(e * 13)
            ZStack {
                RadialGradient(colors: [Color(hex: 0xFF7A2A).opacity(0.85), Color(hex: 0x8A1010).opacity(0.9), Color.black.opacity(0.92)],
                               center: UnitPoint(x: 0.7, y: 0.62), startRadius: 0, endRadius: 1100)
                VStack(spacing: 10) {
                    RadiationSign()
                        .fill(Zone.yellow)
                        .frame(width: 66, height: 66)
                        .shadow(color: Zone.yellow.opacity(0.9), radius: 18)
                    Text("EMISSION")
                        .font(.system(size: 30, weight: .heavy).width(.condensed))
                        .tracking(6)
                        .foregroundStyle(Zone.bone)
                    Text("entering the Zone")
                        .font(.system(size: 13, weight: .medium).width(.condensed))
                        .tracking(2)
                        .foregroundStyle(Zone.bone.opacity(0.8))
                }
                .offset(x: CGFloat(sin(e * 70)) * 4 * fade, y: CGFloat(cos(e * 55)) * 3 * fade)
            }
            .opacity(fade * flicker)
        }
    }
}
