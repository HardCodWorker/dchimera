import SwiftUI

// The Breaking Bad theme: a desert lab. Dark lab-green panels with a hexagon (benzene) lattice,
// crystal-blue selections, element-green keywords, a golden desert behind.

enum Lab {
    static let panel = Color(hex: 0x14201B)
    static let edge = Color(hex: 0x3E8E52)
    static let leaf = Color(hex: 0x58C26A)
    static let crystal = Color(hex: 0x5FD3F0)
    static let crystalLight = Color(hex: 0xBFF4FF)
    static let crystalDeep = Color(hex: 0x1FA2D6)
    static let desert = Color(hex: 0xE2B04A)
}

// MARK: - Shapes

/// A crystal shard: pointed top, flat bottom.
struct CrystalShard: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.3))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.78, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.22, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.3))
        p.closeSubpath()
        return p
    }
}

/// Pointy-top hexagon.
struct Hexagon: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        for i in 0..<6 {
            let a = Double(i) * 60 - 90
            let point = CGPoint(x: r.midX + r.width / 2 * CGFloat(cos(a * .pi / 180)), y: r.midY + r.height / 2 * CGFloat(sin(a * .pi / 180)))
            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - Surfaces

/// Lab panel fill: dark green, a hexagon lattice and warm desert light on big panels; crystal gradient when selected.
struct LabFill<S: Shape>: View {
    let shape: S
    let fill: Color
    let tinted: Bool
    let lattice: Bool

    var body: some View {
        ZStack {
            if tinted {
                shape.fill(LinearGradient(colors: [Lab.crystalLight, fill], startPoint: .topLeading, endPoint: .bottomTrailing))
            } else {
                shape.fill(fill)
            }
            if lattice {
                HexLattice().opacity(0.07).clipShape(shape)
                shape.fill(RadialGradient(colors: [Lab.desert.opacity(0.09), .clear], center: .topLeading, startRadius: 0, endRadius: 420))
            }
        }
    }
}

/// Lab panel edge: element-green line (double on big panels), crystal facets on selections.
struct LabEdge<S: Shape>: View {
    let shape: S
    let tinted: Bool
    let rim: Double
    let double: Bool

    var body: some View {
        ZStack {
            if tinted {
                CrystalFacets().opacity(0.35).clipShape(shape)
            }
            shape.stroke(tinted ? Color.white.opacity(0.35) : Lab.edge.opacity(0.3 + rim), lineWidth: 1)
            if double {
                shape.stroke(Lab.edge.opacity(0.18), lineWidth: 1).padding(4)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Faint benzene-like hexagon grid.
struct HexLattice: View {
    var body: some View {
        Canvas { ctx, size in
            let r: CGFloat = 14
            let dx = r * sqrt(3), dy = r * 1.5
            var row = 0
            var y: CGFloat = 0
            var path = Path()
            while y < size.height + r {
                var x: CGFloat = row % 2 == 0 ? 0 : dx / 2
                while x < size.width + dx {
                    for i in 0..<6 {
                        let a = (Double(i) * 60 - 90) * .pi / 180
                        let point = CGPoint(x: x + r * CGFloat(cos(a)), y: y + r * CGFloat(sin(a)))
                        if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                    path.closeSubpath()
                    x += dx
                }
                y += dy
                row += 1
            }
            ctx.stroke(path, with: .color(Lab.leaf), lineWidth: 0.8)
        }
        .allowsHitTesting(false)
    }
}

/// Light facets over a crystal-blue selection.
struct CrystalFacets: View {
    var body: some View {
        Canvas { ctx, size in
            var rng = ZoneRandom(seed: 0xB1_0E_C2_57A1)
            var x: CGFloat = -20
            while x < size.width + 20 {
                let span = 18 + 26 * rng.next()
                var p = Path()
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x + span, y: 0))
                p.addLine(to: CGPoint(x: x + span * (0.2 + 0.6 * rng.next()), y: size.height))
                p.closeSubpath()
                ctx.fill(p, with: .color(.white.opacity(0.1 + 0.25 * rng.next())))
                x += span * (1 + rng.next())
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Toolbar gauge

/// Purity meter in the toolbar: steady high purity when idle, "cooking" with chasing cells while a query runs.
struct PurityMeter: View {
    let active: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: active ? 0.12 : 1.2)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let step = Int(t / 0.12)
            let noise = GaugeNoise.value(t, step: 1.2, salt: 99)
            HStack(spacing: 7) {
                CrystalShard()
                    .fill(LinearGradient(colors: [Lab.crystalLight, Lab.crystalDeep], startPoint: .top, endPoint: .bottom))
                    .frame(width: 10, height: 14)
                    .shadow(color: Lab.crystal.opacity(active ? 0.9 : 0.5), radius: active ? 6 : 3)
                HStack(spacing: 2) {
                    ForEach(0..<8, id: \.self) { i in
                        Hexagon()
                            .fill(Self.lit(i, step: step, active: active) ? Lab.crystal : Color.white.opacity(0.09))
                            .frame(width: 7, height: 8)
                    }
                }
                Text(active ? "cooking…" : String(format: "%.1f%%", 99.0 + noise * 0.2))
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(active ? Lab.crystal : Theme.secondaryText)
                    .frame(width: 54, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .liquidGlass(SkinShape.capsule, clear: true, rim: active ? 0.5 : 0.2)
        }
        .help(active ? "Query running" : "Purity")
    }

    private static func lit(_ i: Int, step: Int, active: Bool) -> Bool {
        guard active else { return i < 7 }
        let head = step % 10
        return i <= head && i > head - 4
    }
}

// MARK: - Backdrop

/// Desert at golden hour: mesas, a straight road with telephone poles, an old RV with a thin plume of smoke. Static.
struct DesertBackdrop: View {
    var body: some View {
        Canvas { ctx, size in DesertPainter.paint(&ctx, size) }
            .background(Color(hex: 0x120C07))
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

enum DesertPainter {
    static func paint(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height
        let horizon = h * 0.68
        var rng = ZoneRandom(seed: 0xDE5E_A7_2008)

        let sky = Gradient(stops: [
            .init(color: Color(hex: 0x1C2B2C), location: 0),
            .init(color: Color(hex: 0x3E4A3A), location: 0.35),
            .init(color: Color(hex: 0x9A8442), location: 0.72),
            .init(color: Color(hex: 0xF0C36A), location: 1),
        ])
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: horizon + 2)), with: .linearGradient(sky, startPoint: .zero, endPoint: CGPoint(x: 0, y: horizon)))
        let sun = CGPoint(x: w * 0.22, y: horizon - h * 0.08)
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .radialGradient(Gradient(colors: [Color(hex: 0xFFD27A).opacity(0.45), Color(hex: 0xE2A040).opacity(0.12), .clear]),
                                       center: sun, startRadius: 0, endRadius: w * 0.45))
        let r = max(14, h * 0.04)
        ctx.fill(Path(ellipseIn: CGRect(x: sun.x - r, y: sun.y - r, width: 2 * r, height: 2 * r)), with: .color(Color(hex: 0xFFF1C2).opacity(0.95)))

        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 6))
            for _ in 0..<6 {
                let y = horizon * (0.15 + 0.6 * rng.next())
                let cw = w * (0.15 + 0.3 * rng.next())
                layer.fill(Path(ellipseIn: CGRect(x: w * rng.next() - cw * 0.3, y: y, width: cw, height: 3 + 5 * rng.next())),
                           with: .color(Color(hex: 0xFFE0A0).opacity(0.22)))
            }
        }

        mesas(&ctx, w, h, horizon, color: Color(hex: 0xA07848).opacity(0.75), scale: 0.6, &rng)
        mesas(&ctx, w, h, horizon, color: Color(hex: 0x6A4A28), scale: 1, &rng)

        let haze = Gradient(colors: [.clear, Color(hex: 0xF0C36A).opacity(0.22), .clear])
        ctx.fill(Path(CGRect(x: 0, y: horizon - h * 0.04, width: w, height: h * 0.08)),
                 with: .linearGradient(haze, startPoint: CGPoint(x: 0, y: horizon - h * 0.04), endPoint: CGPoint(x: 0, y: horizon + h * 0.04)))

        let ground = Gradient(colors: [Color(hex: 0x5A3E20), Color(hex: 0x2E2012), Color(hex: 0x120C07)])
        ctx.fill(Path(CGRect(x: 0, y: horizon, width: w, height: h - horizon)),
                 with: .linearGradient(ground, startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: 0, y: h)))

        road(&ctx, w, h, horizon)
        scrub(&ctx, w, h, horizon, &rng)
        rv(&ctx, CGPoint(x: w * 0.74, y: horizon + (h - horizon) * 0.32), scale: max(0.7, h / 900), &rng)
    }

    /// Flat-topped mesas along the horizon.
    private static func mesas(_ ctx: inout GraphicsContext, _ w: CGFloat, _ h: CGFloat, _ horizon: CGFloat, color: Color, scale: CGFloat,
                              _ rng: inout ZoneRandom) {
        var p = Path()
        var x = -w * 0.05 + w * 0.1 * rng.next()
        while x < w {
            let width = w * (0.08 + 0.16 * rng.next()) * (scale < 1 ? 1.3 : 1)
            let height = h * (0.04 + 0.1 * rng.next()) * scale
            let slope = width * (0.12 + 0.12 * rng.next())
            p.move(to: CGPoint(x: x, y: horizon + 2))
            p.addLine(to: CGPoint(x: x + slope, y: horizon - height + 4))
            p.addLine(to: CGPoint(x: x + slope + 6, y: horizon - height))
            p.addLine(to: CGPoint(x: x + width - slope - 6, y: horizon - height))
            p.addLine(to: CGPoint(x: x + width - slope, y: horizon - height + 4))
            p.addLine(to: CGPoint(x: x + width, y: horizon + 2))
            p.closeSubpath()
            x += width + w * (0.03 + 0.12 * rng.next())
        }
        ctx.fill(p, with: .color(color))
    }

    /// Straight road to the horizon with a dashed center line and telephone poles.
    private static func road(_ ctx: inout GraphicsContext, _ w: CGFloat, _ h: CGFloat, _ horizon: CGFloat) {
        let vanish = CGPoint(x: w * 0.56, y: horizon)
        var road = Path()
        road.move(to: CGPoint(x: vanish.x - 2, y: horizon))
        road.addLine(to: CGPoint(x: vanish.x + 2, y: horizon))
        road.addLine(to: CGPoint(x: w * 0.82, y: h))
        road.addLine(to: CGPoint(x: w * 0.3, y: h))
        road.closeSubpath()
        ctx.fill(road, with: .color(Color(hex: 0x1C1712)))
        for i in 0..<14 {
            let t0 = pow(CGFloat(i) / 14, 2), t1 = pow((CGFloat(i) + 0.45) / 14, 2)
            let center0 = CGPoint(x: vanish.x + (w * 0.56 - vanish.x) * t0, y: horizon + (h - horizon) * t0)
            let center1 = CGPoint(x: vanish.x + (w * 0.56 - vanish.x) * t1, y: horizon + (h - horizon) * t1)
            ctx.stroke(Path { $0.move(to: center0); $0.addLine(to: center1) }, with: .color(Lab.desert.opacity(0.8)), lineWidth: max(0.6, 4 * t1))
        }
        var poles = Path()
        var tops: [CGPoint] = []
        for t in [0.08, 0.16, 0.28, 0.45, 0.7, 1.05] as [CGFloat] {
            let base = CGPoint(x: vanish.x + (w * 0.95 - vanish.x) * t, y: horizon + (h - horizon) * t)
            let height = h * 0.32 * t + 4
            let top = CGPoint(x: base.x, y: base.y - height)
            poles.move(to: base)
            poles.addLine(to: top)
            poles.move(to: CGPoint(x: top.x - height * 0.12, y: top.y + height * 0.06))
            poles.addLine(to: CGPoint(x: top.x + height * 0.12, y: top.y + height * 0.06))
            tops.append(CGPoint(x: top.x, y: top.y + height * 0.06))
        }
        ctx.stroke(poles, with: .color(Color(hex: 0x16100A)), lineWidth: 2)
        var wires = Path()
        for (a, b) in zip(tops, tops.dropFirst()) {
            wires.move(to: a)
            wires.addQuadCurve(to: b, control: CGPoint(x: (a.x + b.x) / 2, y: max(a.y, b.y) + abs(b.x - a.x) * 0.06))
        }
        ctx.stroke(wires, with: .color(Color(hex: 0x16100A).opacity(0.8)), lineWidth: 0.8)
    }

    private static func scrub(_ ctx: inout GraphicsContext, _ w: CGFloat, _ h: CGFloat, _ horizon: CGFloat, _ rng: inout ZoneRandom) {
        for _ in 0..<40 {
            let t = rng.next()
            let y = horizon + (h - horizon) * CGFloat(t * t) + 4
            let s = 3 + 16 * CGFloat(t)
            let x = w * rng.next()
            if x > w * 0.28 && x < w * 0.84 && y > horizon + (h - horizon) * 0.25 { continue }
            ctx.fill(Path(ellipseIn: CGRect(x: x, y: y - s * 0.5, width: s * 1.6, height: s * 0.7)), with: .color(Color(hex: 0x1E170C).opacity(0.9)))
        }
    }

    /// A boxy old RV with a lit window and a thin plume of smoke from its roof vent.
    private static func rv(_ ctx: inout GraphicsContext, _ at: CGPoint, scale s: CGFloat, _ rng: inout ZoneRandom) {
        let color = Color(hex: 0x15100A)
        let body = CGRect(x: at.x, y: at.y - 34 * s, width: 92 * s, height: 30 * s)
        ctx.fill(Path(roundedRect: body, cornerRadius: 4 * s), with: .color(color))
        ctx.fill(Path(roundedRect: CGRect(x: body.maxX - 4 * s, y: at.y - 22 * s, width: 22 * s, height: 18 * s), cornerRadius: 4 * s), with: .color(color))
        ctx.fill(Path(CGRect(x: body.minX + 4 * s, y: body.minY - 3 * s, width: 30 * s, height: 3 * s)), with: .color(color))
        ctx.fill(Path(CGRect(x: body.minX + 14 * s, y: body.minY + 7 * s, width: 16 * s, height: 7 * s)), with: .color(Color(hex: 0xFFC46A).opacity(0.85)))
        ctx.fill(Path(CGRect(x: body.minX + 40 * s, y: body.minY + 7 * s, width: 12 * s, height: 7 * s)), with: .color(Color(hex: 0xFFC46A).opacity(0.45)))
        for wx in [body.minX + 16 * s, body.maxX + 6 * s] {
            ctx.fill(Path(ellipseIn: CGRect(x: wx - 6 * s, y: at.y - 8 * s, width: 12 * s, height: 12 * s)), with: .color(Color(hex: 0x080604)))
        }
        let vent = CGPoint(x: body.minX + 64 * s, y: body.minY)
        ctx.fill(Path(CGRect(x: vent.x - 2 * s, y: vent.y - 6 * s, width: 4 * s, height: 6 * s)), with: .color(color))
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 5 * s))
            var p = vent
            for i in 0..<9 {
                p.y -= 14 * s
                p.x += (6 + 4 * CGFloat(rng.next())) * s
                let r = (5 + CGFloat(i) * 2.6) * s
                layer.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                           with: .color(Color(hex: 0xE8E4D8).opacity(0.32 - Double(i) * 0.03)))
            }
        }
    }
}

// MARK: - Theme switch effect

/// Played when Breaking Bad is turned on: a chemical haze blooms and blue crystal shards scatter.
struct CookEffect: View {
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            let e = timeline.date.timeIntervalSince(start)
            let fade = max(0, 1 - e / 1.5)
            ZStack {
                RadialGradient(colors: [Color(hex: 0xF2C66B).opacity(0.6), Color(hex: 0x2E7D32).opacity(0.55), Color.black.opacity(0.85)],
                               center: .center, startRadius: 0, endRadius: 900)
                ForEach(0..<5, id: \.self) { i in
                    let a = Double(i) * 72 * .pi / 180
                    let tone = i % 2 == 0 ? Color(hex: 0xC9E26A) : Color(hex: 0x58C26A)
                    Circle()
                        .fill(RadialGradient(colors: [tone.opacity(0.45), tone.opacity(0.15), .clear], center: .center, startRadius: 0, endRadius: 210))
                        .frame(width: 420, height: 420)
                        .scaleEffect(0.6 + e * 1.2)
                        .offset(x: CGFloat(cos(a)) * 160 * CGFloat(e), y: CGFloat(sin(a)) * 100 * CGFloat(e))
                }
                ForEach(0..<16, id: \.self) { i in
                    let a = Double(i) / 16 * 2 * .pi + 0.3
                    let d = CGFloat(60 + 520 * min(1, e / 1.1)) * CGFloat(0.7 + 0.3 * sin(Double(i) * 1.7))
                    CrystalShard()
                        .fill(LinearGradient(colors: [Lab.crystalLight, Lab.crystalDeep], startPoint: .top, endPoint: .bottom))
                        .frame(width: 14, height: 24)
                        .shadow(color: Lab.crystal, radius: 6)
                        .rotationEffect(.radians(a + e * 3))
                        .offset(x: CGFloat(cos(a)) * d, y: CGFloat(sin(a)) * d)
                }
                Text("Let's cook.")
                    .font(.system(size: 34, weight: .bold, design: .serif))
                    .foregroundStyle(Color.white)
                    .shadow(color: .black.opacity(0.6), radius: 8)
            }
            .opacity(fade)
        }
    }
}
