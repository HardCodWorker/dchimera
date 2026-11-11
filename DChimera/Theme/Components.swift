import SwiftUI

// MARK: - Avatar

struct AvatarView: View {
    let initials: String
    let colorIndex: Int
    var size: CGFloat = 52
    var status: DBSession.Status = .idle
    var symbol: String?

    @State private var spin = false

    var body: some View {
        let skin = Skin.current
        let shape = RoundedRectangle(cornerRadius: size * skin.avatarCorner, style: .continuous)
        let ink: Color = skin.isMatrix ? Color(hex: 0x5CFF95) : .white
        ZStack {
            shape
                .fill(Theme.avatarGradient(colorIndex))
                .overlay(
                    shape.fill(LinearGradient(colors: [.white.opacity(skin.isMatrix ? 0.04 : 0.22), .clear], startPoint: .top, endPoint: .center))
                )
                .overlay {
                    if skin.isMatrix {
                        shape.stroke(Color(hex: 0x22FF66).opacity(0.8), lineWidth: 1)
                    } else if skin.isGlass {
                        shape.stroke(LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 1.2)
                    }
                }
                .shadow(color: skin.isMatrix ? Color(hex: 0x22FF66).opacity(0.35) : .clear, radius: 6)
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(ink)
            } else {
                Text(skin.isMatrix ? "[\(initials)]" : initials)
                    .font(.system(size: size * (skin.isMatrix ? 0.26 : 0.36), weight: skin.isMatrix ? .bold : .semibold, design: skin.isMatrix ? .monospaced : .rounded))
                    .foregroundStyle(ink)
                    .minimumScaleFactor(0.5)
                    .matrixGlow(4)
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .topLeading) {
            // Breaking Bad: avatars look like periodic-table tiles with an atomic number.
            if skin.kind == .breakingBad && symbol == nil {
                Text("\(initials.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 118 + 1)")
                    .font(.system(size: size * 0.17, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.85))
                    .padding(size * 0.08)
            }
        }
        .overlay {
            if status == .connecting {
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(Theme.avatarGradient(colorIndex), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: size + 7, height: size + 7)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .onAppear {
                        withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { spin = true }
                    }
                    .onDisappear { spin = false }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            StatusDot(status: status, size: max(10, size * 0.26))
                .offset(x: 1, y: 1)
        }
        .animation(Theme.spring, value: status)
    }
}

struct StatusDot: View {
    let status: DBSession.Status
    var size: CGFloat = 14

    var body: some View {
        Group {
            switch status {
            case .connected:
                Circle().fill(Theme.success)
            case .failed:
                Circle().fill(Theme.danger)
                    .overlay(Image(systemName: "exclamationmark").font(.system(size: size * 0.55, weight: .black)).foregroundStyle(.white))
            default:
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(Theme.sidebar, lineWidth: status == .connected || isFailed ? 2.5 : 0))
        .scaleEffect(status == .connected || isFailed ? 1 : 0.01)
    }

    private var isFailed: Bool {
        if case .failed = status { return true }
        return false
    }
}

/// Table / topic icon: a rounded square with a gradient, like a group avatar.
struct TopicIcon: View {
    let symbol: String
    let colorIndex: Int
    var size: CGFloat = 34

    var body: some View {
        let skin = Skin.current
        let shape = RoundedRectangle(cornerRadius: skin.isMatrix ? 3 : size * 0.3, style: .continuous)
        shape
            .fill(Theme.avatarGradient(colorIndex))
            .overlay {
                if skin.isMatrix { shape.stroke(Color(hex: 0x22FF66).opacity(0.7), lineWidth: 1) }
                if skin.isGlass { shape.stroke(LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 1) }
            }
            .overlay(Image(systemName: symbol).font(.system(size: size * 0.45, weight: .semibold)).foregroundStyle(skin.isMatrix ? Color(hex: 0x5CFF95) : .white).matrixGlow())
            .frame(width: size, height: size)
    }
}

// MARK: - Badge

struct CountBadge: View {
    let text: String
    var muted = false
    @Environment(\.palette) private var palette

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(muted ? Theme.secondaryText : Theme.onAccent)
            .padding(.horizontal, 7)
            .frame(minWidth: 22, minHeight: 20)
            .background(RoundedRectangle(cornerRadius: Skin.current.isMatrix ? 2 : 10, style: .continuous).fill(muted ? AnyShapeStyle(Theme.field) : AnyShapeStyle(palette.gradient)))
            .contentTransition(.numericText())
    }
}

// MARK: - Buttons

struct SpringButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.92

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct IconButton: View {
    let symbol: String
    var help: String = ""
    var size: CGFloat = 30
    var tint: Color?
    var active = false
    let action: () -> Void

    @State private var hover = false
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.48, weight: .semibold))
                .foregroundStyle(active ? palette.accent : (tint ?? Theme.secondaryText))
                .frame(width: size, height: size)
                .background(Circle().fill(active ? palette.accent.opacity(0.14) : (hover ? Theme.hover : .clear)))
                .contentShape(Circle())
        }
        .buttonStyle(SpringButtonStyle())
        .help(help)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
    }
}

struct PillButton: View {
    let title: String
    var symbol: String?
    var prominent = false
    var destructive = false
    let action: () -> Void

    @State private var hover = false
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11.5, weight: .bold)) }
                Text(title).font(.system(size: 12.5, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .foregroundStyle(destructive ? .white : (prominent ? Theme.onAccent : palette.accent))
            .background(
                SkinShape(radius: Skin.current.isMatrix ? 3 : 14).fill(background)
                    .shadow(color: prominent ? palette.accent.opacity(hover ? 0.45 : 0.25) : .clear, radius: hover ? 10 : 6, y: 3)
            )
            .overlay {
                if Skin.current.isMatrix && !prominent && !destructive {
                    RoundedRectangle(cornerRadius: 3).stroke(palette.accent.opacity(hover ? 0.9 : 0.45), lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(SpringButtonStyle(scale: 0.95))
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
    }

    private var background: AnyShapeStyle {
        if destructive { return AnyShapeStyle(Theme.danger) }
        if prominent { return AnyShapeStyle(palette.gradient) }
        return AnyShapeStyle(palette.accent.opacity(hover ? 0.18 : 0.11))
    }
}

// MARK: - Search field

struct SearchField: View {
    @Binding var text: String
    var prompt = "Search"
    var focus: FocusState<Bool>.Binding?

    @FocusState private var ownFocus: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isFocused ? palette.accent : Theme.secondaryText)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused(focus ?? $ownFocus)
            if !text.isEmpty {
                Button {
                    withAnimation(Theme.spring) { text = "" }
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.tertiaryText)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .skinField(radius: min(Skin.current.fieldRadius, 16), focused: isFocused)
        .overlay(RoundedRectangle(cornerRadius: min(Skin.current.fieldRadius, 16), style: .continuous)
            .stroke(isFocused && !Skin.current.isMatrix ? palette.accent : .clear, lineWidth: 1.5))
        .animation(Theme.spring, value: isFocused)
        .animation(Theme.spring, value: text.isEmpty)
    }

    private var isFocused: Bool { focus?.wrappedValue ?? ownFocus }
}

// MARK: - Typing indicator

struct TypingDots: View {
    var color: Color = Theme.secondaryText

    var body: some View {
        if Skin.current.isMatrix {
            TimelineView(.periodic(from: .now, by: 0.42)) { context in
                let on = Int(context.date.timeIntervalSinceReferenceDate / 0.42) % 2 == 0
                Text(on ? "█" : " ")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Color(hex: 0x39FF7A))
                    .matrixGlow()
                    .frame(width: 12)
            }
            .frame(height: 14)
        } else {
            dots
        }
    }

    private var dots: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    let phase = sin((t * 6) - Double(i) * 0.9)
                    Circle()
                        .fill(color)
                        .frame(width: 7, height: 7)
                        .scaleEffect(0.75 + 0.3 * max(0, phase))
                        .opacity(0.45 + 0.55 * max(0, phase))
                        .offset(y: -3 * max(0, phase))
                }
            }
        }
        .frame(height: 14)
    }
}

/// A soft breathing circle behind the green status dot.
struct PulseRing: View {
    var color: Color = Theme.success
    @State private var on = false

    var body: some View {
        Circle()
            .stroke(color.opacity(on ? 0 : 0.7), lineWidth: on ? 1 : 3)
            .scaleEffect(on ? 2.2 : 0.8)
            .onAppear {
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { on = true }
            }
    }
}

// MARK: - Shimmer

struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, .white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: phase * geo.size.width * 1.6)
                }
                .mask(content)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

extension View {
    func shimmer() -> some View { modifier(Shimmer()) }
}

struct SkeletonRows: View {
    var rows = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<rows, id: \.self) { i in
                HStack(spacing: 12) {
                    ForEach(0..<5, id: \.self) { c in
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Theme.field)
                            .frame(width: CGFloat(60 + ((i * 37 + c * 53) % 90)), height: 12)
                    }
                }
            }
        }
        .padding(20)
        .shimmer()
    }
}

// MARK: - Bubble shape

/// Rounded bubble with a small tail at the bottom corner (right for outgoing, left for incoming).
struct BubbleShape: Shape {
    var outgoing: Bool
    var tail = true
    var radius: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(radius, rect.height / 2, rect.width / 2)
        let small: CGFloat = tail ? 5 : r
        let w = rect.width, h = rect.height
        // corners: tl, tr, br, bl
        let tl = r, tr = r
        let br = outgoing ? small : r
        let bl = outgoing ? r : small
        p.move(to: CGPoint(x: tl, y: 0))
        p.addLine(to: CGPoint(x: w - tr, y: 0))
        p.addArc(center: CGPoint(x: w - tr, y: tr), radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: w, y: h - br))
        p.addArc(center: CGPoint(x: w - br, y: h - br), radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: bl, y: h))
        p.addArc(center: CGPoint(x: bl, y: h - bl), radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: 0, y: tl))
        p.addArc(center: CGPoint(x: tl, y: tl), radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()

        if tail {
            if outgoing {
                p.move(to: CGPoint(x: w - 1, y: h - 15))
                p.addQuadCurve(to: CGPoint(x: w + 7, y: h), control: CGPoint(x: w, y: h - 3))
                p.addQuadCurve(to: CGPoint(x: w - 12, y: h), control: CGPoint(x: w - 2, y: h + 0.5))
                p.closeSubpath()
            } else {
                p.move(to: CGPoint(x: 1, y: h - 15))
                p.addQuadCurve(to: CGPoint(x: -7, y: h), control: CGPoint(x: 0, y: h - 3))
                p.addQuadCurve(to: CGPoint(x: 12, y: h), control: CGPoint(x: 2, y: h + 0.5))
                p.closeSubpath()
            }
        }
        return p
    }
}

// MARK: - Wallpaper

/// Soft gradient with a scattered pattern of database doodles.
struct Wallpaper: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme

    private static let symbols = ["cylinder", "tablecells", "key", "bolt", "magnifyingglass", "chart.bar", "curlybraces",
                                  "number", "arrow.triangle.branch", "server.rack", "sparkles", "doc.text", "link",
                                  "chart.pie", "square.stack.3d.up", "terminal", "list.bullet.rectangle", "paperplane"]

    var body: some View {
        switch Skin.current.kind {
        case .matrix: MatrixRain(intensity: 0.42)
        case .glass: Color.clear
        case .stalker: ZoneBackdrop()
        case .doom: HellBackdrop()
        case .breakingBad: DesertBackdrop()
        case .telegram: doodles
        }
    }

    private var doodles: some View {
        ZStack {
            Theme.chatBackground
            LinearGradient(colors: [palette.light.opacity(scheme == .dark ? 0.10 : 0.22), .clear, palette.accent.opacity(scheme == .dark ? 0.08 : 0.16)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Canvas { context, size in
                let tile: CGFloat = 180
                let cols = Int(size.width / tile) + 2
                let rows = Int(size.height / tile) + 2
                for r in 0..<rows {
                    for c in 0..<cols {
                        for k in 0..<4 {
                            let seed = (r * 131 + c * 71 + k * 29) & 0xFFFF
                            let idx = (seed * 7 + k) % Self.symbols.count
                            guard let image = context.resolveSymbol(id: idx) else { continue }
                            let x = CGFloat(c) * tile + CGFloat((seed * 13) % Int(tile))
                            let y = CGFloat(r) * tile + CGFloat((seed * 29 + k * 47) % Int(tile))
                            var ctx = context
                            ctx.translateBy(x: x, y: y)
                            ctx.rotate(by: .degrees(Double((seed % 60) - 30)))
                            ctx.draw(image, at: .zero)
                        }
                    }
                }
            } symbols: {
                ForEach(Self.symbols.indices, id: \.self) { i in
                    Image(systemName: Self.symbols[i])
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(scheme == .dark ? Color.white.opacity(0.045) : palette.accent.opacity(0.10))
                        .tag(i)
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Misc

struct CenterPill: View {
    let text: String
    var symbol: String?
    var isError = false

    var body: some View {
        let skin = Skin.current
        HStack(spacing: 5) {
            if skin.isMatrix {
                Text(isError ? "!!" : "//").font(.system(size: 11, weight: .bold, design: .monospaced))
            } else if let symbol {
                Image(systemName: symbol).font(.system(size: 10.5, weight: .bold))
            }
            Text(text).font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(skin.isMatrix ? (isError ? Color(hex: 0xFF5C5C) : Color(hex: 0x39FF7A)) : (skin.isGlass ? Color.primary : .white))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background {
            if skin.isMatrix {
                RoundedRectangle(cornerRadius: 2).fill(Color.black.opacity(0.85))
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke((isError ? Color(hex: 0xFF5C5C) : Color(hex: 0x22FF66)).opacity(0.5)))
            } else if skin.isGlass {
                Color.clear.glassSurface(Capsule(), tint: isError ? Theme.danger.opacity(0.6) : nil)
            } else {
                Capsule().fill(isError ? Theme.danger.opacity(0.85) : Color.black.opacity(0.28))
            }
        }
        .matrixGlow(2)
    }
}

struct HairlineDivider: View {
    var vertical = false

    var body: some View {
        Rectangle()
            .fill(Theme.divider)
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}

extension View {
    /// Applies `transform` only when `condition` holds.
    @ViewBuilder
    func `if`<T: View>(_ condition: Bool, transform: (Self) -> T) -> some View {
        if condition { transform(self) } else { self }
    }
}
