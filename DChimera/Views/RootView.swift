import SwiftUI

/// One interface for every theme: the table-first workspace. Themes change how it looks.
struct RootView: View {
    @EnvironmentObject private var app: AppModel
    @AppStorage("accentIndex") private var accentIndex = 0
    @AppStorage("appearance") private var appearance: Appearance = .system
    @AppStorage("skin") private var skinRaw = SkinKind.telegram.rawValue
    @State private var switchEffect: SkinKind?
    @ObservedObject private var updater = Updater.shared

    /// Makes `Skin.current` match the stored choice before any child view reads it.
    private static func sync(_ kind: SkinKind) {
        if Skin.current.kind != kind { Skin.current = Skin.make(kind) }
    }

    var body: some View {
        let kind = SkinKind(rawValue: skinRaw) ?? .telegram
        Self.sync(kind)
        let palette = Palette(index: accentIndex)
        return ZStack {
            themed(kind)
                .id(kind)
                .transition(.opacity)
            if let effect = switchEffect {
                SkinSwitchEffect(kind: effect)
                    .id(effect)
                    .zIndex(30)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: kind)
        .environment(\.palette, palette)
        .environmentObject(app.chrome)
        .background(WindowChromeReader(chrome: app.chrome))
        .tint(palette.accent)
        .sheet(item: $app.editor) { request in
            ConnectionEditor(request: request)
                .environmentObject(app)
                .environment(\.palette, palette)
                .fontDesign(Skin.current.fontDesign)
                .fontWidth(Skin.current.fontWidth)
        }
        .onAppear { app.applyAppearance(appearance) }
        .onChange(of: appearance) { _, new in
            withAnimation(Theme.softSpring) { app.applyAppearance(new) }
        }
        .onChange(of: skinRaw) { _, new in
            Self.sync(SkinKind(rawValue: new) ?? .telegram)
            app.applyAppearance(appearance)
            switchEffect = SkinKind(rawValue: new)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { switchEffect = nil }
        }
    }

    private func themed(_ kind: SkinKind) -> some View {
        let skin = Skin.current
        return ZStack {
            SkinBackdrop()
            WorkspaceRoot()
                .ignoresSafeArea()
            if app.quickSwitcher {
                QuickSwitcher()
                    .zIndex(10)
            }
            if let request = app.danger {
                DangerDialog(request: request)
                    .zIndex(11)
                    .transition(.opacity)
            }
            if updater.showDialog {
                UpdateDialog(updater: updater)
                    .zIndex(11.5)
                    .transition(.opacity)
            }
            VStack {
                if let toast = app.toast {
                    ToastView(toast: toast)
                        .id(toast.id)
                        .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.8, anchor: .top)))
                }
                Spacer()
            }
            .padding(.top, 14)
            .allowsHitTesting(false)
            .zIndex(12)
            SkinOverlay()
                .zIndex(20)
        }
        .fontDesign(skin.fontDesign)
        .fontWidth(skin.fontWidth)
        .if(skin.paintsText) { $0.foregroundStyle(Theme.text) }
    }
}

struct ToastView: View {
    let toast: Toast
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(toast.isError ? Theme.danger : palette.accent)
                .symbolEffect(.bounce, value: toast.id)
            Text(toast.text)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .skinPopup(radius: 22)
        .frame(maxWidth: 520)
    }
}

struct DangerDialog: View {
    let request: DangerRequest
    @EnvironmentObject private var app: AppModel
    @State private var appeared = false
    @State private var wobble = false

    var body: some View {
        ZStack {
            Color.black.opacity(appeared ? 0.35 : 0)
                .ignoresSafeArea()
                .onTapGesture { app.resolveDanger(false) }
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.warning)
                    .rotationEffect(.degrees(wobble ? 8 : -8))
                    .onAppear { withAnimation(.easeInOut(duration: 0.12).repeatCount(6, autoreverses: true)) { wobble = true } }
                Text("Run on “\(request.connectionName)”?")
                    .font(.system(size: 16, weight: .bold))
                Text(request.reason)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                ScrollView {
                    Text(SyntaxColors.attributed(request.sql, onAccent: false, size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 140)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.field))
                HStack {
                    PillButton(title: "Cancel") { app.resolveDanger(false) }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    PillButton(title: "Run anyway", symbol: "play.fill", destructive: true) { app.resolveDanger(true) }
                }
            }
            .padding(22)
            .frame(width: 440)
            .skinPopup(radius: 20)
            .overlay(alignment: .top) {
                if Skin.current.isStalker {
                    HazardStripes().frame(height: 6).padding(.horizontal, 16).padding(.top, 1)
                }
            }
            .scaleEffect(appeared ? 1 : 0.85)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear { withAnimation(Theme.bouncy) { appeared = true } }
    }
}

/// The sidebar container: a solid column, or a floating glass panel in Liquid Glass.
