import SwiftUI

// The Doom theme: hell-forged metal plates with rivets, hellfire accents,
// a burning sky over spiked fortresses and rivers of lava.

enum Hell {
    static let metal = Color(hex: 0x1A1311)
    static let steelLight = Color(hex: 0x9A6248)
    static let steelDark = Color(hex: 0x2A1712)
    static let fire = Color(hex: 0xFF5A1F)
    static let flame = Color(hex: 0xFF8A3A)
    static let blood = Color(hex: 0xC8160E)
    static let ember = Color(hex: 0xFFB347)
    static let bone = Color(hex: 0xF2DFCC)
}

// MARK: - Surfaces

/// Doom panel fill: dark metal with a top-down sheen and a fire glow from below; hellfire gradient when selected.
struct DoomFill<S: Shape>: View {
    let shape: S
    let fill: Color
    let tinted: Bool
    let plate: Bool

    var body: some View {
        ZStack {
            if tinted {
                shape.fill(LinearGradient(colors: [Hell.flame, fill], startPoint: .top, endPoint: .bottom))
            } else {
                shape.fill(fill)
            }
            if plate {
                shape.fill(LinearGradient(colors: [Color.white.opacity(0.05), .clear, Color.black.opacity(0.25)], startPoint: .top, endPoint: .bottom))
                shape.fill(RadialGradient(colors: [Hell.fire.opacity(0.16), .clear], center: .bottom, startRadius: 0, endRadius: 380))
            }
        }
    }
}

/// Doom panel edge: black outer line, bevelled steel inner line, grate lines on selections, rivets on big plates.
struct DoomEdge<S: Shape>: View {
    let shape: S
    let tinted: Bool
    let rim: Double
    let rivets: Bool
    let radius: CGFloat?

    var body: some View {
        ZStack {
            if tinted {
                GrateLines().opacity(0.16).clipShape(shape)
            }
            shape.stroke(Color.black.opacity(0.7), lineWidth: 2.5)
            shape.stroke(LinearGradient(colors: [Hell.steelLight.opacity(0.4 + rim), Hell.steelDark.opacity(0.85)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
            if rivets {
                Canvas { ctx, size in Rivets.draw(&ctx, size, radius: radius) }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Thin dark horizontal lines, like a metal grate.
struct GrateLines: View {
    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = 1
            while y < size.height {
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black))
                y += 3
            }
        }
        .allowsHitTesting(false)
    }
}

/// Rivets along the top and bottom edges of a big plate.
enum Rivets {
    static func draw(_ ctx: inout GraphicsContext, _ size: CGSize, radius: CGFloat?) {
        guard size.width > 120, size.height > 70 else { return }
        let rect = CGRect(origin: .zero, size: size)
        let inset = SkinShape.cut(radius: radius, rect: rect) + 9
        let count = max(2, Int((size.width - 2 * inset) / 170) + 1)
        let step = (size.width - 2 * inset) / CGFloat(count - 1)
        for i in 0..<count {
            let x = inset + CGFloat(i) * step
            rivet(&ctx, CGPoint(x: x, y: 7))
            rivet(&ctx, CGPoint(x: x, y: size.height - 7))
        }
    }

    private static func rivet(_ ctx: inout GraphicsContext, _ c: CGPoint) {
        let r: CGFloat = 2.8
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r - 1, y: c.y - r - 0.5, width: 2 * r + 2, height: 2 * r + 2)), with: .color(.black.opacity(0.6)))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                 with: .radialGradient(Gradient(colors: [Color(hex: 0xD9A07E), Color(hex: 0x6A3E2C), Color(hex: 0x2A1712)]),
                                       center: CGPoint(x: c.x - 1, y: c.y - 1), startRadius: 0, endRadius: r + 1))
    }
}

// MARK: - Toolbar gauge

/// Rage meter in the toolbar: smoldering when idle, flaring while a query runs.
struct RageMeter: View {
    let active: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: active ? 0.08 : 0.35)) { timeline in
            let noise = GaugeNoise.value(timeline.date.timeIntervalSinceReferenceDate, step: active ? 0.08 : 0.35, salt: 66)
            let level = active ? 0.7 + 0.3 * noise : 0.14 + 0.16 * noise
            HStack(spacing: 7) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [Hell.ember, Hell.fire, Hell.blood], startPoint: .top, endPoint: .bottom))
                    .scaleEffect(1 + 0.15 * level)
                    .shadow(color: Hell.fire.opacity(0.35 + 0.5 * level), radius: 2 + 6 * level)
                HStack(spacing: 1.5) {
                    ForEach(0..<10, id: \.self) { i in
                        Rectangle()
                            .fill(Double(i) / 10 < level ? Self.segment(i) : Color.white.opacity(0.08))
                            .frame(width: 5, height: 10)
                    }
                }
                Text("RAGE \(Int(level * 100))%")
                    .font(.system(size: 10.5, weight: .heavy).monospacedDigit())
                    .foregroundStyle(active ? Hell.ember : Theme.secondaryText)
                    .frame(width: 66, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .liquidGlass(SkinShape.capsule, clear: true, rim: active ? 0.5 : 0.2)
        }
        .help(active ? "Query running" : "Smoldering")
    }

    private static func segment(_ i: Int) -> Color {
        i < 4 ? Hell.blood : (i < 7 ? Hell.fire : Hell.ember)
    }
}

// MARK: - Backdrop

/// Hell at dusk: a burning sky, jagged mountains, a spiked fortress, lava rivers and floating embers. Static.
struct HellBackdrop: View {
    var body: some View {
        Canvas { ctx, size in HellPainter.paint(&ctx, size) }
            .background(Color(hex: 0x0A0505))
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

enum HellPainter {
    static func paint(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height
        let horizon = h * 0.72
        var rng = ZoneRandom(seed: 0x0D00_A666_1993)

        let sky = Gradient(stops: [
            .init(color: Color(hex: 0x060202), location: 0),
            .init(color: Color(hex: 0x250604), location: 0.4),
            .init(color: Color(hex: 0x7A1406), location: 0.78),
            .init(color: Color(hex: 0xFF5A1A), location: 1),
        ])
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: horizon + 2)), with: .linearGradient(sky, startPoint: .zero, endPoint: CGPoint(x: 0, y: horizon)))
        let glowCenter = CGPoint(x: w * 0.55, y: horizon)
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .radialGradient(Gradient(colors: [Color(hex: 0xFF6A20).opacity(0.35), Color(hex: 0xC8160E).opacity(0.12), .clear]),
                                       center: glowCenter, startRadius: 0, endRadius: w * 0.7))

        smoke(&ctx, w, horizon, &rng)
        ridge(&ctx, w, base: horizon + 2, low: h * 0.05, high: h * 0.2, step: (24, 70), color: Color(hex: 0x3A0905), &rng)
        fortress(&ctx, w, h, horizon)
        ridge(&ctx, w, base: horizon + h * 0.04, low: h * 0.01, high: h * 0.07, step: (14, 40), color: Color(hex: 0x170403), &rng)

        let ground = Gradient(colors: [Color(hex: 0x1A0503), Color(hex: 0x0C0302), Color(hex: 0x050101)])
        ctx.fill(Path(CGRect(x: 0, y: horizon + h * 0.035, width: w, height: h - horizon)),
                 with: .linearGradient(ground, startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: 0, y: h)))

        lava(&ctx, w, h, &rng)
        embers(&ctx, w, h, &rng)
    }

    private static func smoke(_ ctx: inout GraphicsContext, _ w: CGFloat, _ horizon: CGFloat, _ rng: inout ZoneRandom) {
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 18))
            for _ in 0..<10 {
                let y = horizon * (0.1 + 0.8 * rng.next())
                let cw = w * (0.2 + 0.4 * rng.next())
                let ch = 14 + 40 * rng.next()
                let x = w * rng.next() - cw * 0.3
                layer.fill(Path(ellipseIn: CGRect(x: x, y: y, width: cw, height: ch)), with: .color(Color(hex: 0x120404).opacity(0.7)))
                if y > horizon * 0.5 {
                    layer.fill(Path(ellipseIn: CGRect(x: x + cw * 0.15, y: y + ch * 0.6, width: cw * 0.7, height: ch * 0.3)),
                               with: .color(Color(hex: 0xFF4A10).opacity(0.25)))
                }
            }
        }
    }

    /// A jagged mountain line from left to right, filled down to below the base.
    private static func ridge(_ ctx: inout GraphicsContext, _ w: CGFloat, base: CGFloat, low: CGFloat, high: CGFloat,
                              step: (CGFloat, CGFloat), color: Color, _ rng: inout ZoneRandom) {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: base + 40))
        var x: CGFloat = 0
        var peak = true
        while x <= w + step.1 {
            let height = peak ? low + (high - low) * rng.next() : low * rng.next()
            p.addLine(to: CGPoint(x: x, y: base - height))
            x += step.0 + (step.1 - step.0) * rng.next()
            peak.toggle()
        }
        p.addLine(to: CGPoint(x: w, y: base + 40))
        p.closeSubpath()
        ctx.fill(p, with: .color(color))
    }

    /// Spiked fortress with horned towers and a burning gate.
    private static func fortress(_ ctx: inout GraphicsContext, _ w: CGFloat, _ h: CGFloat, _ horizon: CGFloat) {
        let color = Color(hex: 0x120303)
        let x0 = w * 0.6, base = horizon + h * 0.02
        let wallTop = base - h * 0.09
        var p = Path(CGRect(x: x0, y: wallTop, width: w * 0.22, height: base - wallTop))
        // Spikes along the wall.
        var sx = x0
        while sx < x0 + w * 0.22 {
            p.move(to: CGPoint(x: sx, y: wallTop))
            p.addLine(to: CGPoint(x: sx + 4, y: wallTop - 9))
            p.addLine(to: CGPoint(x: sx + 8, y: wallTop))
            sx += 12
        }
        // Towers with pointed roofs and horns.
        let towers: [(CGFloat, CGFloat, CGFloat)] = [(0.0, 0.025, 0.17), (0.09, 0.035, 0.24), (0.19, 0.025, 0.15)]
        for t in towers {
            let tx = x0 + w * t.0, tw = w * t.1, top = base - h * t.2
            p.addRect(CGRect(x: tx, y: top, width: tw, height: base - top))
            p.move(to: CGPoint(x: tx - 3, y: top))
            p.addLine(to: CGPoint(x: tx + tw / 2, y: top - h * 0.05))
            p.addLine(to: CGPoint(x: tx + tw + 3, y: top))
            p.move(to: CGPoint(x: tx, y: top + 4))
            p.addQuadCurve(to: CGPoint(x: tx - tw * 0.6, y: top - h * 0.03), control: CGPoint(x: tx - tw * 0.5, y: top + 2))
            p.addLine(to: CGPoint(x: tx + 3, y: top + 9))
            p.move(to: CGPoint(x: tx + tw, y: top + 4))
            p.addQuadCurve(to: CGPoint(x: tx + tw * 1.6, y: top - h * 0.03), control: CGPoint(x: tx + tw * 1.5, y: top + 2))
            p.addLine(to: CGPoint(x: tx + tw - 3, y: top + 9))
        }
        ctx.fill(p, with: .color(color))
        // Gate and windows glowing with fire.
        let gate = CGRect(x: x0 + w * 0.098, y: base - h * 0.045, width: w * 0.02, height: h * 0.045)
        ctx.fill(Path(roundedRect: gate, cornerRadius: gate.width / 2), with: .linearGradient(Gradient(colors: [Hell.ember, Hell.fire]),
                 startPoint: CGPoint(x: gate.midX, y: gate.minY), endPoint: CGPoint(x: gate.midX, y: gate.maxY)))
        ctx.fill(Path(ellipseIn: gate.insetBy(dx: -30, dy: -20)),
                 with: .radialGradient(Gradient(colors: [Hell.fire.opacity(0.35), .clear]), center: CGPoint(x: gate.midX, y: gate.maxY), startRadius: 0, endRadius: 50))
        for (i, t) in towers.enumerated() {
            let tx = x0 + w * t.0 + w * t.1 / 2, top = base - h * t.2
            ctx.fill(Path(CGRect(x: tx - 1.5, y: top + h * 0.03 + CGFloat(i) * 6, width: 3, height: 5)), with: .color(Hell.fire.opacity(0.9)))
        }
    }

    /// A winding lava river across the ground with glowing cracks.
    private static func lava(_ ctx: inout GraphicsContext, _ w: CGFloat, _ h: CGFloat, _ rng: inout ZoneRandom) {
        var river = Path()
        let y0 = h * 0.86
        river.move(to: CGPoint(x: -10, y: y0))
        river.addCurve(to: CGPoint(x: w * 0.45, y: h * 0.82), control1: CGPoint(x: w * 0.15, y: h * 0.9), control2: CGPoint(x: w * 0.3, y: h * 0.78))
        river.addCurve(to: CGPoint(x: w + 10, y: h * 0.9), control1: CGPoint(x: w * 0.65, y: h * 0.87), control2: CGPoint(x: w * 0.85, y: h * 0.84))
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 14))
            layer.stroke(river, with: .color(Hell.fire.opacity(0.7)), lineWidth: 26)
        }
        ctx.stroke(river, with: .linearGradient(Gradient(colors: [Hell.fire, Hell.ember, Hell.fire]), startPoint: .zero, endPoint: CGPoint(x: w, y: 0)), lineWidth: 7)
        ctx.stroke(river, with: .color(Color(hex: 0xFFE7A0).opacity(0.8)), lineWidth: 1.5)
        var cracks = Path()
        for _ in 0..<14 {
            var point = CGPoint(x: w * rng.next(), y: h * (0.78 + 0.2 * rng.next()))
            let direction: CGFloat = rng.next() > 0.5 ? 1 : -1
            cracks.move(to: point)
            for _ in 0..<5 {
                point.x += direction * CGFloat(8 + 22 * rng.next())
                point.y += CGFloat(rng.next() - 0.5) * 14
                cracks.addLine(to: point)
            }
        }
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 3))
            layer.stroke(cracks, with: .color(Hell.fire.opacity(0.8)), lineWidth: 3)
        }
        ctx.stroke(cracks, with: .color(Hell.ember.opacity(0.85)), lineWidth: 0.9)
    }

    private static func embers(_ ctx: inout GraphicsContext, _ w: CGFloat, _ h: CGFloat, _ rng: inout ZoneRandom) {
        var points: [(CGPoint, CGFloat, Double)] = []
        for _ in 0..<140 {
            let y = h * (0.25 + 0.75 * rng.next())
            points.append((CGPoint(x: w * rng.next(), y: y), 0.8 + 1.8 * rng.next(), 0.35 + 0.6 * rng.next()))
        }
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 3))
            for (p, r, a) in points {
                layer.fill(Path(ellipseIn: CGRect(x: p.x - r * 2, y: p.y - r * 2, width: r * 4, height: r * 4)), with: .color(Hell.fire.opacity(a * 0.6)))
            }
        }
        for (p, r, a) in points {
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r / 2, y: p.y - r / 2, width: r, height: r)), with: .color(Hell.ember.opacity(a)))
        }
    }
}

// MARK: - Theme switch effect

/// Played when Doom is turned on: a blood-red screen that melts away in uneven columns.
struct MeltEffect: View {
    @State private var start = Date()
    private static let columns = 48

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { timeline in
                let e = timeline.date.timeIntervalSince(start)
                let colWidth = geo.size.width / CGFloat(Self.columns)
                ZStack(alignment: .topLeading) {
                    ForEach(0..<Self.columns, id: \.self) { i in
                        let t = max(0, e - Self.delay(i))
                        Rectangle()
                            .fill(LinearGradient(colors: [Color(hex: 0x3A0503), Color(hex: 0xA3120A), Color(hex: 0xFF5A1A)], startPoint: .top, endPoint: .bottom))
                            .frame(width: colWidth + 1, height: geo.size.height)
                            .offset(x: CGFloat(i) * colWidth, y: CGFloat(t * t) * geo.size.height * 1.9)
                    }
                    VStack(spacing: 8) {
                        Text("DOOM")
                            .font(.system(size: 64, weight: .black).width(.expanded))
                            .foregroundStyle(LinearGradient(colors: [Hell.ember, Hell.fire, Hell.blood], startPoint: .top, endPoint: .bottom))
                            .shadow(color: .black.opacity(0.8), radius: 0, x: 3, y: 3)
                        Text("welcome to hell")
                            .font(.system(size: 13, weight: .heavy).width(.expanded))
                            .tracking(3)
                            .foregroundStyle(Hell.bone.opacity(0.85))
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .opacity(e < 0.35 ? 1 : max(0, 1 - (e - 0.35) / 0.35))
                }
            }
        }
    }

    /// Start delay of a column, 0...0.35 s, uneven like dripping paint.
    private static func delay(_ i: Int) -> Double {
        var x = UInt64(i + 1) &* 0x9E3779B97F4A7C15
        x ^= x >> 31
        return 0.12 + Double(x % 1000) / 1000 * 0.23
    }
}
