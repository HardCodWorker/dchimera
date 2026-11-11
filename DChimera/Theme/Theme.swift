import AppKit
import SwiftUI

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Auto"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.stars.fill"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

struct AccentOption: Identifiable {
    let name: String
    let top: Color
    let bottom: Color
    var id: String { name }
}

/// User settings stored in UserDefaults (also bound with @AppStorage in views).
enum AppSettings {
    static var rowLimit: Int {
        let v = UserDefaults.standard.integer(forKey: "rowLimit")
        return v > 0 ? v : 1000
    }

    static var confirmDangerous: Bool {
        UserDefaults.standard.object(forKey: "confirmDangerous") as? Bool ?? true
    }

    static var editorFontSize: CGFloat {
        let v = UserDefaults.standard.double(forKey: "editorFontSize")
        return v > 0 ? v : 13
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }

    static func dynamic(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: isDark ? darkAlpha : lightAlpha)
        })
    }
}

enum Theme {
    static let accents: [AccentOption] = [
        AccentOption(name: "Sky", top: Color(hex: 0x45B0F7), bottom: Color(hex: 0x2B7DE9)),
        AccentOption(name: "Violet", top: Color(hex: 0xA187FF), bottom: Color(hex: 0x6B4FE6)),
        AccentOption(name: "Mint", top: Color(hex: 0x3DDBA9), bottom: Color(hex: 0x10A37F)),
        AccentOption(name: "Sunset", top: Color(hex: 0xFFAA5C), bottom: Color(hex: 0xF0603C)),
        AccentOption(name: "Rose", top: Color(hex: 0xFF83B0), bottom: Color(hex: 0xE2457C)),
        AccentOption(name: "Graphite", top: Color(hex: 0x97A3B8), bottom: Color(hex: 0x5D6A82)),
    ]

    static let baseAvatarGradients: [(Color, Color)] = [
        (Color(hex: 0xFF8E86), Color(hex: 0xE5534B)),
        (Color(hex: 0xFFC069), Color(hex: 0xF08A24)),
        (Color(hex: 0xB693FF), Color(hex: 0x7C5CE0)),
        (Color(hex: 0x7EE08F), Color(hex: 0x34B05A)),
        (Color(hex: 0x6FD6F5), Color(hex: 0x2E9FD8)),
        (Color(hex: 0x76A9FF), Color(hex: 0x4569E0)),
        (Color(hex: 0xFF8FC6), Color(hex: 0xD9488E)),
        (Color(hex: 0x5FE3C8), Color(hex: 0x1BA88E)),
    ]

    static var avatarGradients: [(Color, Color)] { Skin.current.avatarGradients ?? baseAvatarGradients }

    static func avatarGradient(_ index: Int) -> LinearGradient {
        let pair = avatarGradients[((index % avatarGradients.count) + avatarGradients.count) % avatarGradients.count]
        return LinearGradient(colors: [pair.0, pair.1], startPoint: .top, endPoint: .bottom)
    }

    /// Stable color for a name (same on every launch).
    static func colorIndex(for name: String) -> Int {
        let h = name.unicodeScalars.reduce(UInt32(7)) { ($0 &* 31) &+ $1.value }
        return Int(h % UInt32(baseAvatarGradients.count))
    }

    static var sidebar: Color { Skin.current.sidebar.color }
    static var chatBackground: Color { Skin.current.chat.color }
    static var bubbleIn: Color { Skin.current.bubbleIn.color }
    static var header: Color { Skin.current.header.color }
    static var divider: Color { Skin.current.divider.color }
    static var hover: Color { Skin.current.hover.color }
    static var field: Color { Skin.current.field.color }
    static var secondaryText: Color { Skin.current.secondary.color }
    static var tertiaryText: Color { Skin.current.tertiary.color }
    static var grid: Color { Skin.current.grid.color }
    static var gridHeader: Color { Skin.current.gridHeader.color }
    static var gridStripe: Color { Skin.current.gridStripe.color }
    static var gridLine: Color { Skin.current.gridLine.color }
    static var strip: Color { Skin.current.strip.color }
    static var numeric: Color { Skin.current.numeric.color }
    static var onAccent: Color { Skin.current.onAccent }
    static var text: Color { Skin.current.textColor }
    static let danger = Color(hex: 0xEF5B5B)
    static let success = Color(hex: 0x3CC47C)
    static let warning = Color(hex: 0xF5A524)
    static let edited = Color(hex: 0xF5C542)

    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.78)
    static let softSpring = Animation.spring(response: 0.5, dampingFraction: 0.86)
    static let bouncy = Animation.spring(response: 0.42, dampingFraction: 0.62)

    /// Body font in the theme's design (rounded for glass, monospaced for matrix).
    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: Skin.current.fontDesign)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// The accent the user picked, passed down the view tree.
struct Palette {
    var index: Int

    var option: AccentOption { Skin.current.accent ?? Theme.accents[min(max(index, 0), Theme.accents.count - 1)] }
    var accent: Color { option.bottom }
    var light: Color { option.top }
    var gradient: LinearGradient { LinearGradient(colors: [option.top, option.bottom], startPoint: .topLeading, endPoint: .bottomTrailing) }
}

extension Palette {
    /// The palette the user picked, for AppKit code that has no SwiftUI environment.
    static var current: Palette { Palette(index: UserDefaults.standard.integer(forKey: "accentIndex")) }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette(index: 0)
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

// MARK: - Number formatting

enum Fmt {
    static func compact(_ n: Int) -> String {
        let v = Double(n)
        switch abs(v) {
        case 1_000_000_000...: return String(format: "%.1fB", v / 1_000_000_000).replacingOccurrences(of: ".0B", with: "B")
        case 1_000_000...: return String(format: "%.1fM", v / 1_000_000).replacingOccurrences(of: ".0M", with: "M")
        case 10_000...: return String(format: "%.0fK", v / 1_000)
        case 1_000...: return String(format: "%.1fK", v / 1_000).replacingOccurrences(of: ".0K", with: "K")
        default: return "\(n)"
        }
    }

    static func grouped(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    static func duration(_ t: TimeInterval) -> String {
        if t < 0.001 { return "<1 ms" }
        if t < 1 { return "\(Int(t * 1000)) ms" }
        if t < 60 { return String(format: "%.2f s", t) }
        return String(format: "%dm %02ds", Int(t) / 60, Int(t) % 60)
    }

    static func time(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    static func listDate(_ d: Date?) -> String {
        guard let d else { return "" }
        let cal = Calendar.current
        if cal.isDateInToday(d) { return time(d) }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = cal.isDate(d, equalTo: Date(), toGranularity: .year) ? "d MMM" : "dd.MM.yy"
        return f.string(from: d)
    }

    static func dayTitle(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "MMMM d"
        return f.string(from: d)
    }
}
