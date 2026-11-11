import SwiftUI

// MARK: - Glass

/// Oil-film colors used for iridescent edges and puddles.
enum Iris {
    static let colors: [Color] = [Color(hex: 0x7CF3FF), Color(hex: 0xA88BFF), Color(hex: 0xFF8AD8), Color(hex: 0xFFC27A),
                                  Color(hex: 0x9BFFB0), Color(hex: 0x7CF3FF)]
}

/// Groups glass shapes so nearby ones flow into each other (macOS 26).
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *), !GlassFallback.forced {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

/// Debug snapshots cannot draw system glass; DCHIMERA_GLASS_FALLBACK=1 makes the app use the material version.
enum GlassFallback {
    static let forced = ProcessInfo.processInfo.environment["DCHIMERA_GLASS_FALLBACK"] != nil
}

extension View {
    /// Liquid Glass tinted like wet asphalt (macOS 26), frosted dark material before that; with an iridescent rim.
    func glassSurface<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        liquidGlass(shape, tint: tint, interactive: interactive)
    }

    /// The theme's surface for panels, buttons and selections.
    /// Wet Asphalt: Liquid Glass (`clear` is the more transparent kind, `tint` colors it).
    /// Chat: flat cards. Matrix: black boxes with a green frame. `tint` marks a selected or active item.
    @ViewBuilder
    func liquidGlass<S: Shape>(_ shape: S, tint: Color? = nil, clear: Bool = false, interactive: Bool = false, rim: Double = 0.25) -> some View {
        let skin = Skin.current
        if skin.isGlass {
            // System glass gets the plain Capsule / RoundedRectangle, as it did before SkinShape existed.
            if let s = shape as? SkinShape {
                if let radius = s.radius {
                    self.asphaltGlass(RoundedRectangle(cornerRadius: radius, style: .continuous), tint: tint, clear: clear, interactive: interactive, rim: rim)
                } else {
                    self.asphaltGlass(Capsule(), tint: tint, clear: clear, interactive: interactive, rim: rim)
                }
            } else {
                self.asphaltGlass(shape, tint: tint, clear: clear, interactive: interactive, rim: rim)
            }
        } else if skin.isStalker {
            self.zoneSurface(shape, tint: tint, clear: clear, rim: rim)
        } else if skin.kind == .doom {
            self.doomSurface(shape, tint: tint, clear: clear, rim: rim)
        } else if skin.kind == .breakingBad {
            self.labSurface(shape, tint: tint, clear: clear, rim: rim)
        } else if skin.isMatrix {
            self
                .background(shape.fill(tint ?? Color.black.opacity(0.88)))
                .overlay(shape.stroke(Color(hex: 0x22FF66).opacity(tint != nil ? 0.9 : (clear ? 0.25 : 0.45)), lineWidth: 1))
        } else {
            self
                .background(shape.fill(tint ?? (clear ? Theme.hover : Theme.header)))
                .overlay(shape.stroke(Theme.divider, lineWidth: tint == nil ? 1 : 0))
                .shadow(color: .black.opacity(clear || tint != nil ? 0 : 0.06), radius: 6, y: 2)
        }
    }

    /// Wet Asphalt: Liquid Glass on macOS 26, frosted material before.
    @ViewBuilder
    func asphaltGlass<S: Shape>(_ shape: S, tint: Color?, clear: Bool, interactive: Bool, rim: Double) -> some View {
        let asphalt = Color(hex: 0x2B3036)
        let glassTint = tint.map { $0.opacity(0.55) } ?? asphalt.opacity(clear ? 0.12 : 0.28)
        if #available(macOS 26.0, *), !GlassFallback.forced {
            self.glassEffect((clear ? Glass.clear : Glass.regular).tint(glassTint).interactive(interactive), in: shape)
                .iridescentRim(shape, strength: rim)
        } else {
            self
                .background(shape.fill(.ultraThinMaterial).opacity(clear ? 0.7 : 1))
                .background(shape.fill(tint.map { $0.opacity(0.75) } ?? asphalt.opacity(clear ? 0.2 : 0.4)))
                .iridescentRim(shape, strength: rim)
        }
    }

    /// Thin rainbow edge, like light split by the edge of a glass pane, plus a white highlight on top.
    func iridescentRim<S: Shape>(_ shape: S, strength: Double = 0.25) -> some View {
        self
            .overlay(shape.stroke(AngularGradient(colors: Iris.colors, center: .center, angle: .degrees(-40)), lineWidth: 1)
                .opacity(strength * 0.5)
                .blendMode(.screen)
                .allowsHitTesting(false))
            .overlay(shape.stroke(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0)], startPoint: .top, endPoint: .center), lineWidth: 1)
                .allowsHitTesting(false))
    }

    /// Stalker surface: dark soot panel with a rust stain, a rusty edge and bright corner brackets on big panels;
    /// selected items are radiation yellow with faint hazard stripes.
    func zoneSurface<S: Shape>(_ shape: S, tint: Color?, clear: Bool, rim: Double) -> some View {
        let bigPanel = tint == nil && !clear
        let fill: Color = tint ?? Zone.panel.opacity(clear ? 0.5 : 0.8)
        let edge: Color = tint == nil ? Zone.edge.opacity(0.4 + rim) : Color.black.opacity(0.35)
        let shadow: Color = tint.map { $0.opacity(0.45) } ?? Color.black.opacity(clear ? 0 : 0.5)
        return self
            .background(ZoneFill(shape: shape, fill: fill, stained: bigPanel))
            .overlay(ZoneEdge(shape: shape, edge: edge, hazard: tint != nil, brackets: bigPanel))
            .shadow(color: shadow, radius: tint != nil ? 8 : 12, y: tint != nil ? 0 : 4)
    }

    /// Doom surface: riveted dark metal plates with a fire glow; hellfire gradient with grate lines when selected.
    func doomSurface<S: Shape>(_ shape: S, tint: Color?, clear: Bool, rim: Double) -> some View {
        let plate = tint == nil && !clear
        let fill: Color = tint ?? Hell.metal.opacity(clear ? 0.55 : 0.86)
        let shadow: Color = tint.map { $0.opacity(0.55) } ?? Color.black.opacity(clear ? 0 : 0.6)
        let radius = (shape as? SkinShape)?.radius
        return self
            .background(DoomFill(shape: shape, fill: fill, tinted: tint != nil, plate: plate))
            .overlay(DoomEdge(shape: shape, tinted: tint != nil, rim: rim, rivets: plate && shape is SkinShape, radius: radius))
            .shadow(color: shadow, radius: tint != nil ? 10 : 12, y: tint != nil ? 0 : 4)
    }

    /// Breaking Bad surface: lab-green panels with a hexagon lattice; crystal-blue facets when selected.
    func labSurface<S: Shape>(_ shape: S, tint: Color?, clear: Bool, rim: Double) -> some View {
        let big = tint == nil && !clear
        let fill: Color = tint ?? Lab.panel.opacity(clear ? 0.5 : 0.82)
        let shadow: Color = tint.map { $0.opacity(0.5) } ?? Color.black.opacity(clear ? 0 : 0.45)
        return self
            .background(LabFill(shape: shape, fill: fill, tinted: tint != nil, lattice: big))
            .overlay(LabEdge(shape: shape, tinted: tint != nil, rim: rim, double: big && shape is SkinShape))
            .shadow(color: shadow, radius: tint != nil ? 9 : 12, y: tint != nil ? 0 : 4)
    }

    /// Soft green bloom used by the Matrix theme.
    @ViewBuilder
    func matrixGlow(_ radius: CGFloat = 3) -> some View {
        if Skin.current.isMatrix {
            self.shadow(color: Color(hex: 0x22FF66).opacity(0.55), radius: radius)
        } else {
            self
        }
    }

    /// Background of a full-height panel (sidebar, strip).
    @ViewBuilder
    func skinPanel(_ color: Color) -> some View {
        if Skin.current.isGlass {
            self
        } else {
            self.background(color)
        }
    }

    /// Background of a header or footer bar.
    @ViewBuilder
    func skinBar() -> some View {
        let skin = Skin.current
        if skin.isGlass {
            self.glassSurface(Rectangle())
        } else if skin.isMatrix {
            self.background(skin.header.color)
                .overlay(alignment: .bottom) { Rectangle().fill(skin.divider.color).frame(height: 1) }
        } else {
            self.background(skin.header.color)
        }
    }

    /// Background of a floating card or popup (quick switcher, toast, dialogs, completion list).
    @ViewBuilder
    func skinPopup(radius: CGFloat? = nil) -> some View {
        let skin = Skin.current
        let r = radius ?? skin.cardRadius
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        if skin.isGlass {
            self.glassSurface(shape)
                .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
        } else if skin.isStalker {
            self.background(SkinShape(radius: r).fill(Zone.panelSolid.opacity(0.97)))
                .overlay(SkinShape(radius: r).stroke(Zone.edge, lineWidth: 1))
                .overlay(SkinShape(radius: r, corners: true).stroke(Zone.amber.opacity(0.9), style: StrokeStyle(lineWidth: 1.6, lineCap: .square)))
                .shadow(color: .black.opacity(0.6), radius: 22, y: 10)
        } else if skin.kind == .doom {
            self.background(SkinShape(radius: r).fill(Color(hex: 0x1E1513).opacity(0.97)))
                .overlay(DoomEdge(shape: SkinShape(radius: r), tinted: false, rim: 0.3, rivets: true, radius: r))
                .shadow(color: Hell.fire.opacity(0.25), radius: 22, y: 8)
        } else if skin.kind == .breakingBad {
            self.background(SkinShape(radius: r).fill(Color(hex: 0x15221C).opacity(0.97)))
                .overlay(LabEdge(shape: SkinShape(radius: r), tinted: false, rim: 0.3, double: true))
                .shadow(color: .black.opacity(0.55), radius: 22, y: 10)
        } else if skin.isMatrix {
            self.background(shape.fill(Color.black.opacity(0.94)))
                .overlay(shape.stroke(Color(hex: 0x22FF66).opacity(0.75), lineWidth: 1))
                .shadow(color: Color(hex: 0x22FF66).opacity(0.35), radius: 14)
        } else {
            self.background(shape.fill(.regularMaterial).shadow(color: .black.opacity(0.22), radius: 18, y: 8))
                .overlay(shape.stroke(Theme.divider, lineWidth: 0.5))
        }
    }

    /// Text field background.
    @ViewBuilder
    func skinField(radius: CGFloat? = nil, focused: Bool = false) -> some View {
        let skin = Skin.current
        let shape = RoundedRectangle(cornerRadius: radius ?? skin.fieldRadius, style: .continuous)
        if skin.isGlass {
            self.glassSurface(shape)
        } else if skin.isMatrix {
            self.background(shape.fill(skin.field.color))
                .overlay(shape.stroke(Color(hex: 0x22FF66).opacity(focused ? 0.9 : 0.35), lineWidth: 1))
        } else {
            self.background(shape.fill(skin.field.color))
        }
    }
}

/// Panel fill of the Stalker theme, with a rust stain on big panels.
struct ZoneFill<S: Shape>: View {
    let shape: S
    let fill: Color
    let stained: Bool

    var body: some View {
        ZStack {
            shape.fill(fill)
            if stained {
                shape.fill(RadialGradient(colors: [Zone.rust.opacity(0.2), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 420))
            }
        }
    }
}

/// Edges of a Stalker panel: rusty outline, top highlight, hazard texture on selections, corner brackets on big panels.
struct ZoneEdge<S: Shape>: View {
    let shape: S
    let edge: Color
    let hazard: Bool
    let brackets: Bool

    var body: some View {
        ZStack {
            if hazard {
                HazardStripes(stripe: 6, base: false).opacity(0.1).clipShape(shape)
            }
            shape.stroke(edge, lineWidth: 1)
            shape.stroke(LinearGradient(colors: [Color.white.opacity(0.08), .clear], startPoint: .top, endPoint: .center), lineWidth: 1)
            if brackets, let s = shape as? SkinShape {
                SkinShape(radius: s.radius, corners: true)
                    .stroke(Skin.current.accent?.bottom ?? Zone.amber, style: StrokeStyle(lineWidth: 1.6, lineCap: .square))
                    .opacity(0.85)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Row background

/// Selected / hovered row in the lists, drawn per theme.
struct SkinRowBackground: View {
    let selected: Bool
    let hover: Bool
    var radius: CGFloat?
    @Environment(\.palette) private var palette

    var body: some View {
        let skin = Skin.current
        let shape = RoundedRectangle(cornerRadius: radius ?? skin.rowRadius, style: .continuous)
        if skin.isMatrix {
            shape.fill(selected ? AnyShapeStyle(Color(hex: 0x22FF66)) : AnyShapeStyle(hover ? skin.hover.color : Color.clear))
                .overlay(alignment: .leading) {
                    if hover && !selected { Rectangle().fill(Color(hex: 0x22FF66)).frame(width: 2) }
                }
                .shadow(color: selected ? Color(hex: 0x22FF66).opacity(0.6) : .clear, radius: 8)
        } else if skin.isGlass {
            shape.fill(selected ? AnyShapeStyle(palette.gradient) : AnyShapeStyle(hover ? skin.hover.color : Color.clear))
                .shadow(color: selected ? palette.accent.opacity(0.45) : .clear, radius: 12, y: 3)
        } else {
            shape.fill(selected ? AnyShapeStyle(palette.gradient) : AnyShapeStyle(hover ? skin.hover.color : Color.clear))
        }
    }
}

// MARK: - Bubbles

/// Background of a chat bubble.
struct SkinBubble: View {
    let outgoing: Bool
    var error = false
    var hover = false
    @Environment(\.palette) private var palette

    var body: some View {
        let skin = Skin.current
        if skin.isMatrix {
            let green = error ? Color(hex: 0xFF4B4B) : Color(hex: 0x22FF66)
            let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
            shape.fill(outgoing ? Color(hex: 0x00140A) : Color.black.opacity(0.92))
                .overlay(shape.stroke(green.opacity(outgoing ? 0.9 : 0.5), lineWidth: 1))
                .overlay(alignment: outgoing ? .trailing : .leading) {
                    Rectangle().fill(green).frame(width: 3)
                }
                .shadow(color: green.opacity(hover ? 0.6 : 0.3), radius: hover ? 12 : 6)
        } else if skin.isGlass {
            let shape = RoundedRectangle(cornerRadius: skin.bubbleRadius, style: .continuous)
            if outgoing {
                Color.clear.glassSurface(shape, tint: palette.accent.opacity(0.85), interactive: true)
            } else if error {
                Color.clear.glassSurface(shape, tint: Theme.danger.opacity(0.35))
            } else {
                Color.clear.glassSurface(shape)
            }
        } else {
            if outgoing {
                BubbleShape(outgoing: true)
                    .fill(palette.gradient)
                    .shadow(color: palette.accent.opacity(hover ? 0.35 : 0.18), radius: hover ? 10 : 4, y: 2)
            } else {
                BubbleShape(outgoing: false)
                    .fill(skin.bubbleIn.color)
                    .overlay(BubbleShape(outgoing: false).fill(error ? Theme.danger.opacity(0.10) : .clear))
                    .overlay(BubbleShape(outgoing: false).stroke(error ? Theme.danger.opacity(0.35) : .clear, lineWidth: 1))
                    .shadow(color: .black.opacity(0.07), radius: 3, y: 1)
            }
        }
    }
}

// MARK: - Backdrops

/// What sits behind the whole window.
struct SkinBackdrop: View {
    var body: some View {
        switch Skin.current.kind {
        case .glass: AsphaltBackground()
        case .stalker: ZoneBackdrop()
        case .doom: HellBackdrop()
        case .breakingBad: DesertBackdrop()
        case .matrix: Color.black.ignoresSafeArea()
        case .telegram: Theme.chatBackground.ignoresSafeArea()
        }
    }
}

/// Effects drawn over the whole window (Matrix scanlines and vignette).
struct SkinOverlay: View {
    var body: some View {
        if Skin.current.isMatrix {
            ZStack {
                Canvas { ctx, size in
                    var y: CGFloat = 0
                    while y < size.height {
                        ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black.opacity(0.22)))
                        y += 3
                    }
                }
                RadialGradient(colors: [.clear, .black.opacity(0.45)], center: .center, startRadius: 380, endRadius: 1100)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        } else if Skin.current.isStalker {
            ZStack {
                ZoneGrain()
                RadialGradient(colors: [.clear, Color(hex: 0x0A0603).opacity(0.5)], center: .center, startRadius: 420, endRadius: 1150)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        } else if Skin.current.kind == .doom {
            RadialGradient(colors: [.clear, Color(hex: 0x1A0000).opacity(0.6)], center: .center, startRadius: 400, endRadius: 1150)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        } else if Skin.current.kind == .breakingBad {
            ZStack {
                ZoneGrain().opacity(0.6)
                RadialGradient(colors: [.clear, Color(hex: 0x1A1206).opacity(0.45)], center: .center, startRadius: 420, endRadius: 1150)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}

/// Falling green glyph columns.
struct MatrixRain: View {
    var intensity: Double = 0.55

    private static let glyphs: [String] = Array("ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ0123456789:.=*+-<>¦|").map(String.init)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let colWidth: CGFloat = 15, rowHeight: CGFloat = 17
                let cols = Int(size.width / colWidth) + 1
                let rows = Int(size.height / rowHeight) + 1
                let count = Self.glyphs.count
                for c in 0..<cols {
                    let seed = (c &* 2654435761) & 0x7FFFFFFF
                    let speed = 5.0 + Double(seed % 11)
                    let trail = 8 + seed % 20
                    let cycle = Double(rows + trail + seed % 40)
                    let head = Int((t * speed + Double(seed % 997)).truncatingRemainder(dividingBy: cycle))
                    for k in 0..<trail {
                        let r = head - k
                        guard r >= 0, r < rows else { continue }
                        let flicker = Int(t * (k == 0 ? 14 : 1.3)) &+ r &* 7
                        let index = (seed &+ r &* 31 &+ flicker) % count
                        guard let symbol = ctx.resolveSymbol(id: k == 0 ? 1000 + index : index) else { continue }
                        var g = ctx
                        g.opacity = k == 0 ? 1 : max(0.06, 1 - Double(k) / Double(trail))
                        g.draw(symbol, at: CGPoint(x: CGFloat(c) * colWidth + colWidth / 2, y: CGFloat(r) * rowHeight + rowHeight / 2))
                    }
                }
            } symbols: {
                ForEach(Self.glyphs.indices, id: \.self) { i in
                    Text(Self.glyphs[i])
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(hex: 0x1EF26A))
                        .tag(i)
                }
                ForEach(Self.glyphs.indices.map { $0 + 1000 }, id: \.self) { i in
                    Text(Self.glyphs[i - 1000])
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: 0xE2FFEC))
                        .shadow(color: Color(hex: 0x6BFF9E), radius: 4)
                        .tag(i)
                }
            }
        }
        .opacity(intensity)
        .background(Color.black)
        .ignoresSafeArea()
    }
}

/// Short effect played when a theme is turned on.
struct SkinSwitchEffect: View {
    let kind: SkinKind
    @State private var progress: CGFloat = 0

    var body: some View {
        Group {
            switch kind {
            case .matrix:
                ZStack {
                    MatrixRain(intensity: 1)
                    Text("dchimera // matrix mode")
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(hex: 0x6BFF9E))
                        .shadow(color: Color(hex: 0x22FF66), radius: 10)
                }
                .opacity(1 - progress)
            case .glass:
                Skin.current.chat.color.opacity(0.9 * (1 - progress))
            case .stalker:
                EmissionEffect()
            case .doom:
                MeltEffect()
            case .breakingBad:
                CookEffect()
            case .telegram:
                LinearGradient(colors: [Color(hex: 0x45B0F7).opacity(0.5), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .opacity(1 - progress)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeIn(duration: kind == .matrix ? 1.4 : 0.8).delay(kind == .matrix ? 0.5 : 0)) { progress = 1 }
        }
    }
}

/// Small picture of a theme for the theme picker.
struct SkinPreview: View {
    let kind: SkinKind
    var selected = false

    var body: some View {
        ZStack {
            backdrop
            HStack(spacing: 6) {
                sidebar
                    .frame(width: 34)
                    .padding(kind == .telegram || kind == .matrix ? 0 : 5)
                VStack(spacing: 6) {
                    HStack {
                        Spacer()
                        accentBlock.frame(width: 46, height: 14)
                    }
                    HStack {
                        plainBlock.frame(width: 58, height: 22)
                        Spacer()
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 150, height: 92)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 3 : 1))
        .shadow(color: selected ? Color.accentColor.opacity(0.35) : .clear, radius: 10)
    }

    @ViewBuilder
    private var backdrop: some View {
        switch kind {
        case .telegram:
            LinearGradient(colors: [Color(hex: 0xCFE0EC), Color(hex: 0xE3ECF2)], startPoint: .top, endPoint: .bottom)
        case .matrix:
            ZStack {
                Color.black
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(0..<7, id: \.self) { i in
                        Text(String(repeating: "ｱ1ﾈ0ｼ7ﾜ", count: 3).prefix(14 + i % 3))
                            .font(.system(size: 7, design: .monospaced))
                            .foregroundStyle(Color(hex: 0x1EF26A).opacity(0.25 + Double(i % 3) * 0.2))
                    }
                }
            }
        case .glass:
            Color(hex: 0x2B2F34)
        case .stalker:
            Canvas { ctx, size in ZonePainter.paint(&ctx, size) }
        case .doom:
            Canvas { ctx, size in HellPainter.paint(&ctx, size) }
        case .breakingBad:
            Canvas { ctx, size in DesertPainter.paint(&ctx, size) }
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        switch kind {
        case .telegram:
            Rectangle().fill(Skin.telegram.sidebar.color)
        case .matrix:
            RoundedRectangle(cornerRadius: 2).fill(Skin.matrix.sidebar.color)
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color(hex: 0x22FF66).opacity(0.6)))
        case .glass:
            RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.08))
        case .stalker:
            Chamfer(cut: 5).fill(Zone.panel.opacity(0.85))
                .overlay(Chamfer(cut: 5).stroke(Zone.amber.opacity(0.8), lineWidth: 1))
        case .doom:
            Chamfer(cut: 4).fill(Hell.metal.opacity(0.9))
                .overlay(Chamfer(cut: 4).stroke(Hell.steelLight.opacity(0.7), lineWidth: 1))
        case .breakingBad:
            RoundedRectangle(cornerRadius: 4).fill(Lab.panel.opacity(0.9))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Lab.edge.opacity(0.8), lineWidth: 1))
        }
    }

    @ViewBuilder
    private var accentBlock: some View {
        switch kind {
        case .telegram:
            RoundedRectangle(cornerRadius: 6).fill(LinearGradient(colors: [Color(hex: 0x45B0F7), Color(hex: 0x2B7DE9)], startPoint: .top, endPoint: .bottom))
        case .matrix:
            RoundedRectangle(cornerRadius: 1).fill(Color(hex: 0x00140A))
                .overlay(RoundedRectangle(cornerRadius: 1).stroke(Color(hex: 0x22FF66)))
        case .glass:
            RoundedRectangle(cornerRadius: 6).fill(LinearGradient(colors: [Color(hex: 0xFFCB72), Color(hex: 0xF29A2E)], startPoint: .top, endPoint: .bottom))
        case .stalker:
            HazardStripes(stripe: 4).clipShape(Chamfer(cut: 4))
        case .doom:
            Chamfer(cut: 3).fill(LinearGradient(colors: [Hell.flame, Hell.blood], startPoint: .top, endPoint: .bottom))
        case .breakingBad:
            RoundedRectangle(cornerRadius: 3).fill(LinearGradient(colors: [Lab.crystalLight, Lab.crystalDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }

    @ViewBuilder
    private var plainBlock: some View {
        switch kind {
        case .telegram:
            RoundedRectangle(cornerRadius: 6).fill(Color.white)
        case .matrix:
            RoundedRectangle(cornerRadius: 1).fill(Color.black)
                .overlay(RoundedRectangle(cornerRadius: 1).stroke(Color(hex: 0x22FF66).opacity(0.5)))
        case .glass:
            RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.12))
        case .stalker:
            Chamfer(cut: 5).fill(Zone.panel.opacity(0.85))
                .overlay(Chamfer(cut: 5).stroke(Zone.edge, lineWidth: 1))
        case .doom:
            Chamfer(cut: 4).fill(Hell.metal.opacity(0.9))
                .overlay(Chamfer(cut: 4).stroke(Hell.steelDark, lineWidth: 1))
        case .breakingBad:
            RoundedRectangle(cornerRadius: 4).fill(Lab.panel.opacity(0.9))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Lab.edge.opacity(0.5), lineWidth: 1))
        }
    }
}

/// Still wet-asphalt surface: cool graphite gradient and fine aggregate grain. No animation.
struct AsphaltBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x353B41), Color(hex: 0x262A2F), Color(hex: 0x2D3237)], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color(hex: 0x6E8FAF).opacity(0.16), .clear], center: .init(x: 0.7, y: 0.15), startRadius: 0, endRadius: 700)
            AsphaltGrain()
        }
        .ignoresSafeArea()
    }
}

/// Fine light and dark specks of the asphalt aggregate. Drawn once per size.
struct AsphaltGrain: View {
    var body: some View {
        Canvas { ctx, size in
            var seed: UInt64 = 0x2545F4914F6CDD1D
            func next() -> Double {
                seed ^= seed << 13
                seed ^= seed >> 7
                seed ^= seed << 17
                return Double(seed % 1_000_000) / 1_000_000
            }
            let count = Int(size.width * size.height / 140)
            for _ in 0..<count {
                let x = next() * size.width, y = next() * size.height
                let d = 0.6 + next() * 1.5
                let light = next() > 0.5
                let alpha = light ? 0.03 + next() * 0.06 : 0.08 + next() * 0.10
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: d, height: d)),
                         with: .color(light ? Color.white.opacity(alpha) : Color.black.opacity(alpha)))
            }
        }
        .allowsHitTesting(false)
    }
}
