import AppKit
import CoreText
import SwiftUI

/// A color that has a light and a dark value, usable from SwiftUI and AppKit.
struct SkinColor {
    let ns: NSColor
    let color: Color

    init(_ light: UInt32, _ dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) {
        let ns = NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: isDark ? darkAlpha : lightAlpha)
        }
        self.ns = ns
        self.color = Color(nsColor: ns)
    }

    init(_ both: UInt32, alpha: CGFloat = 1) {
        self.init(both, both, lightAlpha: alpha, darkAlpha: alpha)
    }
}

enum SkinKind: String, CaseIterable, Identifiable {
    case telegram, matrix, glass, stalker, doom, breakingBad

    var id: String { rawValue }

    var title: String {
        switch self {
        case .telegram: "Chat"
        case .matrix: "Matrix"
        case .glass: "Wet Asphalt"
        case .stalker: "Stalker"
        case .doom: "Doom"
        case .breakingBad: "Breaking Bad"
        }
    }

    var subtitle: String {
        switch self {
        case .telegram: "Light, airy messenger colors with soft cards"
        case .matrix: "Green phosphor on black, monospaced, terminal frames"
        case .glass: "Wet-asphalt greys on Liquid Glass"
        case .stalker: "The Zone: rust, dusk sky, radiation yellow"
        case .doom: "Hellfire, riveted metal, lava under a burning sky"
        case .breakingBad: "Desert lab: crystal blue, chemistry green"
        }
    }

    var symbol: String {
        switch self {
        case .telegram: "bubble.left.and.bubble.right.fill"
        case .matrix: "terminal.fill"
        case .glass: "tablecells.fill"
        case .stalker: "atom"
        case .doom: "flame.fill"
        case .breakingBad: "testtube.2"
        }
    }

    /// Color of the theme's icon in quick switcher lists.
    var colorIndex: Int {
        switch self {
        case .telegram: 5
        case .matrix: 3
        case .glass: 4
        case .stalker: 1
        case .doom: 0
        case .breakingBad: 7
        }
    }
}

/// Everything that makes a theme look like itself: surfaces, text, shapes, fonts, syntax and grid colors.
struct Skin {
    let kind: SkinKind
    var sidebar: SkinColor
    var chat: SkinColor
    var bubbleIn: SkinColor
    var header: SkinColor
    var divider: SkinColor
    var hover: SkinColor
    var field: SkinColor
    var secondary: SkinColor
    var tertiary: SkinColor
    var grid: SkinColor
    var gridHeader: SkinColor
    var gridStripe: SkinColor
    var gridLine: SkinColor
    var strip: SkinColor
    var numeric: SkinColor
    /// Main text color; nil means the system label color.
    var text: SkinColor?
    /// Text drawn on top of the accent (selected rows, prominent buttons).
    var onAccent: Color
    var accent: AccentOption?
    var avatarGradients: [(Color, Color)]?

    var keyword: SkinColor
    var string: SkinColor
    var number: SkinColor
    var comment: SkinColor
    var quoted: SkinColor
    var function: SkinColor
    var param: SkinColor

    var fontDesign: Font.Design
    var bubbleRadius: CGFloat
    var rowRadius: CGFloat
    var fieldRadius: CGFloat
    var cardRadius: CGFloat
    /// 0.5 is a circle, smaller values give rounded squares.
    var avatarCorner: CGFloat
    var forcesDark: Bool
    var gridFont: NSFont
    /// Width of the UI font (Stalker uses condensed type).
    var fontWidth: Font.Width = .standard
    /// Column title font of the data grid; nil means the default.
    var gridHeaderFont: NSFont? = nil

    var isMatrix: Bool { kind == .matrix }
    var isGlass: Bool { kind == .glass }
    var isStalker: Bool { kind == .stalker }
    /// Themes drawn entirely by the app: a painted scene behind, own panel shapes, own buttons and toolbar gauge.
    var isScenic: Bool { kind == .stalker || kind == .doom || kind == .breakingBad }
    /// Themes whose own text color is applied to the whole window.
    var paintsText: Bool { kind == .matrix || isScenic }
    var textColor: Color { text?.color ?? .primary }
    var nsText: NSColor { text?.ns ?? .labelColor }

    nonisolated(unsafe) static var current = Skin.make(.telegram)

    static func make(_ kind: SkinKind) -> Skin {
        switch kind {
        case .telegram: telegram
        case .matrix: matrix
        case .glass: glass
        case .stalker: stalker
        case .doom: doom
        case .breakingBad: breakingBad
        }
    }

    static let telegram = Skin(
        kind: SkinKind.telegram,
        sidebar: SkinColor(0xFFFFFF, 0x17212B),
        chat: SkinColor(0xD9E4EC, 0x0E1621),
        bubbleIn: SkinColor(0xFFFFFF, 0x182533),
        header: SkinColor(0xFFFFFF, 0x17212B),
        divider: SkinColor(0xE4E8EC, 0x0A1119),
        hover: SkinColor(0xF2F4F7, 0x202B36),
        field: SkinColor(0xF0F2F5, 0x242F3D),
        secondary: SkinColor(0x707A85, 0x7D8E9F),
        tertiary: SkinColor(0xA2AAB3, 0x56677A),
        grid: SkinColor(0xFFFFFF, 0x131C26),
        gridHeader: SkinColor(0xF5F7FA, 0x1A2532),
        gridStripe: SkinColor(0xF8FAFC, 0x16202B),
        gridLine: SkinColor(0xEAEDF1, 0x0F1720),
        strip: SkinColor(0xF3F5F8, 0x0F161F),
        numeric: SkinColor(0x3B82D6, 0x5EA2F0),
        text: noText,
        onAccent: Color.white,
        accent: noAccent,
        avatarGradients: noAvatars,
        keyword: SkinColor(0x8A3FD1, 0xC792EA),
        string: SkinColor(0x2B8A4E, 0xC3E88D),
        number: SkinColor(0xD2550E, 0xF78C6C),
        comment: SkinColor(0x8C97A3, 0x5F7184),
        quoted: SkinColor(0x0A7BAA, 0x89DDFF),
        function: SkinColor(0x1F68E0, 0x82AAFF),
        param: SkinColor(0xB07A00, 0xFFCB6B),
        fontDesign: Font.Design.default,
        bubbleRadius: 16,
        rowRadius: 12,
        fieldRadius: 19,
        cardRadius: 18,
        avatarCorner: 0.5,
        forcesDark: false,
        gridFont: NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .regular)
    )

    private static let matrixAccent = AccentOption(name: "Phosphor", top: Color(hex: 0x5CFF95), bottom: Color(hex: 0x00D85A))
    private static let matrixAvatars: [(Color, Color)] = [
        (Color(hex: 0x0A2E16), Color(hex: 0x03140A)),
        (Color(hex: 0x0E3A1C), Color(hex: 0x041A0C)),
        (Color(hex: 0x113F20), Color(hex: 0x05200E)),
        (Color(hex: 0x0B3319), Color(hex: 0x02120A)),
    ]
    private static let noAccent: AccentOption? = nil
    private static let noAvatars: [(Color, Color)]? = nil
    private static let noText: SkinColor? = nil

    static let matrix = Skin(
        kind: SkinKind.matrix,
        sidebar: SkinColor(0x010804),
        chat: SkinColor(0x000000),
        bubbleIn: SkinColor(0x010F06),
        header: SkinColor(0x010804),
        divider: SkinColor(0x0C4A22),
        hover: SkinColor(0x062A12),
        field: SkinColor(0x021408),
        secondary: SkinColor(0x2DCB64),
        tertiary: SkinColor(0x1A7F3D),
        grid: SkinColor(0x000703),
        gridHeader: SkinColor(0x031B0B),
        gridStripe: SkinColor(0x020F07),
        gridLine: SkinColor(0x0A3017),
        strip: SkinColor(0x000000),
        numeric: SkinColor(0xA8FFC8),
        text: SkinColor(0x39FF7A),
        onAccent: Color.black,
        accent: matrixAccent,
        avatarGradients: matrixAvatars,
        keyword: SkinColor(0x5CFF95),
        string: SkinColor(0xC4FFB8),
        number: SkinColor(0x7DFF3A),
        comment: SkinColor(0x2A7A44),
        quoted: SkinColor(0x8BFFD0),
        function: SkinColor(0xB6FFDA),
        param: SkinColor(0xE9FF8C),
        fontDesign: Font.Design.monospaced,
        bubbleRadius: 3,
        rowRadius: 3,
        fieldRadius: 3,
        cardRadius: 4,
        avatarCorner: 0.14,
        forcesDark: true,
        gridFont: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    )

    private static let rain = AccentOption(name: "Rain", top: Color(hex: 0x74B4EE), bottom: Color(hex: 0x3F86C8))
    private static let asphaltText: SkinColor? = SkinColor(0xE4E7EA)

    /// "Wet asphalt" is a color: dark grey with a cool blue cast. Flat, no effects.
    static let glass = Skin(
        kind: SkinKind.glass,
        sidebar: SkinColor(0x25292D),
        chat: SkinColor(0x2B2F34),
        bubbleIn: SkinColor(0x33383E),
        header: SkinColor(0x31363B),
        divider: SkinColor(0x1C1F22),
        hover: SkinColor(0xFFFFFF, alpha: 0.08),
        field: SkinColor(0x000000, alpha: 0.28),
        secondary: SkinColor(0xA7AFB7),
        tertiary: SkinColor(0x6E767E),
        grid: SkinColor(0x22262A, alpha: 0.55),
        gridHeader: SkinColor(0x2C3136, alpha: 0.6),
        gridStripe: SkinColor(0x2B3035, alpha: 0.55),
        gridLine: SkinColor(0xFFFFFF, alpha: 0.07),
        strip: SkinColor(0x212428),
        numeric: SkinColor(0x8EC3F2),
        text: asphaltText,
        onAccent: Color.white,
        accent: rain,
        avatarGradients: noAvatars,
        keyword: SkinColor(0x86B7E8),
        string: SkinColor(0xA8D5A2),
        number: SkinColor(0xE5B66B),
        comment: SkinColor(0x6B737B),
        quoted: SkinColor(0x9DCBD8),
        function: SkinColor(0xC6A6E8),
        param: SkinColor(0xE8C27A),
        fontDesign: Font.Design.default,
        bubbleRadius: 8,
        rowRadius: 5,
        fieldRadius: 6,
        cardRadius: 10,
        avatarCorner: 0.5,
        forcesDark: true,
        gridFont: NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .regular)
    )

    private static let radiation = AccentOption(name: "Radiation", top: Color(hex: 0xFFD84D), bottom: Color(hex: 0xE8A417))
    private static let zoneText: SkinColor? = SkinColor(0xE6DCC0)
    private static let zoneAvatars: [(Color, Color)] = [
        (Color(hex: 0xC4703A), Color(hex: 0x8A3F1C)),
        (Color(hex: 0x8E9A4E), Color(hex: 0x5A6430)),
        (Color(hex: 0xD9B44A), Color(hex: 0xA07A1E)),
        (Color(hex: 0x7C8C86), Color(hex: 0x4A5652)),
        (Color(hex: 0xB0553E), Color(hex: 0x6E2A1E)),
        (Color(hex: 0x6FA59A), Color(hex: 0x3D6B62)),
    ]

    /// Condensed system font with fixed-width digits, so numbers still line up in the grid.
    private static let zoneGridFont: NSFont = {
        let base = NSFont.systemFont(ofSize: 13, weight: .regular, width: .condensed)
        let features: [[NSFontDescriptor.FeatureKey: Int]] = [[.typeIdentifier: kNumberSpacingType, .selectorIdentifier: kMonospacedNumbersSelector]]
        return NSFont(descriptor: base.fontDescriptor.addingAttributes([.featureSettings: features]), size: 13) ?? base
    }()

    /// "The Zone": soot and rust, bone-colored text, radiation-yellow accent, cut-corner panels.
    static let stalker = Skin(
        kind: SkinKind.stalker,
        sidebar: SkinColor(0x1C1A13),
        chat: SkinColor(0x14120D),
        bubbleIn: SkinColor(0x2A261C),
        header: SkinColor(0x24211A),
        divider: SkinColor(0x3A3222),
        hover: SkinColor(0xF2C230, alpha: 0.10),
        field: SkinColor(0x0B0A07, alpha: 0.55),
        secondary: SkinColor(0xB8A880),
        tertiary: SkinColor(0x7D7154),
        grid: SkinColor(0x15130E, alpha: 0.8),
        gridHeader: SkinColor(0x2A2519, alpha: 0.92),
        gridStripe: SkinColor(0x1D1A12, alpha: 0.8),
        gridLine: SkinColor(0x4A3F2A, alpha: 0.45),
        strip: SkinColor(0x100F0B),
        numeric: SkinColor(0xF29A4A),
        text: zoneText,
        onAccent: Color(hex: 0x16130C),
        accent: radiation,
        avatarGradients: zoneAvatars,
        keyword: SkinColor(0xF2C230),
        string: SkinColor(0xA9C46C),
        number: SkinColor(0xFF8A3D),
        comment: SkinColor(0x6E6650),
        quoted: SkinColor(0x7FD6C2),
        function: SkinColor(0x9FE870),
        param: SkinColor(0xFF6B4A),
        fontDesign: Font.Design.default,
        bubbleRadius: 4,
        rowRadius: 3,
        fieldRadius: 4,
        cardRadius: 6,
        avatarCorner: 0.16,
        forcesDark: true,
        gridFont: zoneGridFont,
        fontWidth: Font.Width.condensed,
        gridHeaderFont: NSFont.systemFont(ofSize: 12.5, weight: .bold, width: .condensed)
    )

    private static let hellfire = AccentOption(name: "Hellfire", top: Color(hex: 0xFF7A2E), bottom: Color(hex: 0xD3200F))
    private static let doomText: SkinColor? = SkinColor(0xF2DFCC)
    private static let doomAvatars: [(Color, Color)] = [
        (Color(hex: 0xE0442A), Color(hex: 0x8A0E08)),
        (Color(hex: 0xFF9A3C), Color(hex: 0xB8420E)),
        (Color(hex: 0x9CDB43), Color(hex: 0x4A7A12)),
        (Color(hex: 0xB07A62), Color(hex: 0x5A3426)),
        (Color(hex: 0xB45CE0), Color(hex: 0x5E1E86)),
        (Color(hex: 0x8C8C8C), Color(hex: 0x3E3A38)),
    ]

    /// Hell-forged metal: riveted plates, hellfire accent, a burning sky with lava below.
    static let doom = Skin(
        kind: SkinKind.doom,
        sidebar: SkinColor(0x1A1311),
        chat: SkinColor(0x0E0908),
        bubbleIn: SkinColor(0x2A1D19),
        header: SkinColor(0x231815),
        divider: SkinColor(0x3E2720),
        hover: SkinColor(0xFF5A1F, alpha: 0.12),
        field: SkinColor(0x070404, alpha: 0.6),
        secondary: SkinColor(0xC29A82),
        tertiary: SkinColor(0x7E5D50),
        grid: SkinColor(0x120C0B, alpha: 0.82),
        gridHeader: SkinColor(0x2B1B17, alpha: 0.94),
        gridStripe: SkinColor(0x1A1210, alpha: 0.82),
        gridLine: SkinColor(0x55302A, alpha: 0.45),
        strip: SkinColor(0x0C0807),
        numeric: SkinColor(0xFFB347),
        text: doomText,
        onAccent: Color.white,
        accent: hellfire,
        avatarGradients: doomAvatars,
        keyword: SkinColor(0xFF5233),
        string: SkinColor(0x9CDB43),
        number: SkinColor(0xFFB347),
        comment: SkinColor(0x6E5248),
        quoted: SkinColor(0xFF9A6B),
        function: SkinColor(0xFFD24A),
        param: SkinColor(0xD86BFF),
        fontDesign: Font.Design.default,
        bubbleRadius: 3,
        rowRadius: 2,
        fieldRadius: 3,
        cardRadius: 4,
        avatarCorner: 0.12,
        forcesDark: true,
        gridFont: NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .medium),
        fontWidth: Font.Width.standard,
        gridHeaderFont: NSFont.systemFont(ofSize: 12, weight: .heavy)
    )

    private static let crystal = AccentOption(name: "Crystal", top: Color(hex: 0x8FE8FF), bottom: Color(hex: 0x1FA2D6))
    private static let labText: SkinColor? = SkinColor(0xEAF2E3)
    private static let labAvatars: [(Color, Color)] = [
        (Color(hex: 0x4CAF50), Color(hex: 0x1E6B2A)),
        (Color(hex: 0x3FA34D), Color(hex: 0x14522A)),
        (Color(hex: 0x5FD3F0), Color(hex: 0x1F7FB0)),
        (Color(hex: 0xE2B04A), Color(hex: 0x9A6A1C)),
        (Color(hex: 0x66BB6A), Color(hex: 0x2E7D32)),
        (Color(hex: 0x8D9E4A), Color(hex: 0x4F5A1E)),
    ]

    /// Desert lab: dark lab-green panels with a hexagon lattice, crystal-blue accent, element-green keywords.
    static let breakingBad = Skin(
        kind: SkinKind.breakingBad,
        sidebar: SkinColor(0x14201B),
        chat: SkinColor(0x0F1713),
        bubbleIn: SkinColor(0x1C2A23),
        header: SkinColor(0x1A2620),
        divider: SkinColor(0x2C4036),
        hover: SkinColor(0x7FE3FF, alpha: 0.1),
        field: SkinColor(0x050A08, alpha: 0.55),
        secondary: SkinColor(0xA9BFA8),
        tertiary: SkinColor(0x6C8070),
        grid: SkinColor(0x0F1814, alpha: 0.84),
        gridHeader: SkinColor(0x1E2E26, alpha: 0.94),
        gridStripe: SkinColor(0x15211B, alpha: 0.84),
        gridLine: SkinColor(0x2F4A3C, alpha: 0.5),
        strip: SkinColor(0x0B120E),
        numeric: SkinColor(0x7FE3FF),
        text: labText,
        onAccent: Color(hex: 0x04161F),
        accent: crystal,
        avatarGradients: labAvatars,
        keyword: SkinColor(0x58C26A),
        string: SkinColor(0xF2D16B),
        number: SkinColor(0x7FE3FF),
        comment: SkinColor(0x5E7266),
        quoted: SkinColor(0xB6E3A0),
        function: SkinColor(0x9AD8FF),
        param: SkinColor(0xFFB25A),
        fontDesign: Font.Design.default,
        bubbleRadius: 6,
        rowRadius: 5,
        fieldRadius: 5,
        cardRadius: 7,
        avatarCorner: 0.1,
        forcesDark: true,
        gridFont: NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .regular),
        fontWidth: Font.Width.standard,
        gridHeaderFont: NSFont.systemFont(ofSize: 12, weight: .bold)
    )
}
