import AppKit
import SwiftUI

/// The update window: checking, up to date, new version with release notes, download progress, errors.
struct UpdateDialog: View {
    @ObservedObject var updater: Updater
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(appeared ? 0.35 : 0)
                .ignoresSafeArea()
                .onTapGesture { close() }
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.system(size: 16, weight: .bold))
                        Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                    }
                }
                details
                buttons
            }
            .padding(22)
            .frame(width: 460)
            .skinPopup(radius: 20)
            .scaleEffect(appeared ? 1 : 0.9)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear { withAnimation(Theme.bouncy) { appeared = true } }
    }

    private var title: String {
        switch updater.state {
        case .idle, .checking: "Checking for updates…"
        case .upToDate: "You're up to date"
        case .available(let r): "DChimera \(r.version) is available"
        case .downloading(let r, _): "Downloading DChimera \(r.version)…"
        case .installing(let r): "Installing DChimera \(r.version)…"
        case .failed: "Update failed"
        }
    }

    private var subtitle: String {
        switch updater.state {
        case .upToDate: "Version \(updater.currentVersion) is the newest."
        case .installing: "DChimera will quit and open again in a moment."
        default: "You have version \(updater.currentVersion)."
        }
    }

    @ViewBuilder
    private var details: some View {
        switch updater.state {
        case .idle, .checking:
            ProgressView().controlSize(.small).frame(maxWidth: .infinity)
        case .available(let r):
            if !r.notes.isEmpty {
                ScrollView {
                    Text(Self.markdown(r.notes))
                        .font(.system(size: 12.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(10)
                }
                .frame(maxHeight: 180)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.field))
            }
        case .downloading(let r, let fraction):
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: fraction)
                Text(r.size > 0 ? "\(Int(fraction * 100))% of \(ByteCountFormatter.string(fromByteCount: r.size, countStyle: .file))" : "\(Int(fraction * 100))%")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
            }
        case .installing:
            ProgressView().controlSize(.small).frame(maxWidth: .infinity)
        case .failed(let message):
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.danger)
                .textSelection(.enabled)
        case .upToDate:
            EmptyView()
        }
    }

    @ViewBuilder
    private var buttons: some View {
        HStack {
            switch updater.state {
            case .available(let r):
                PillButton(title: "Later") { close() }
                    .keyboardShortcut(.cancelAction)
                PillButton(title: "Release page", symbol: "safari") { NSWorkspace.shared.open(r.page) }
                Spacer()
                PillButton(title: "Install & Relaunch", symbol: "arrow.down.circle.fill", prominent: true) {
                    Task { await updater.install() }
                }
            case .downloading:
                Spacer()
                PillButton(title: "Cancel") { updater.cancelDownload() }
                    .keyboardShortcut(.cancelAction)
            case .installing, .checking, .idle:
                Spacer()
            case .failed:
                PillButton(title: "Close") { close() }
                    .keyboardShortcut(.cancelAction)
                PillButton(title: "Releases", symbol: "safari") { NSWorkspace.shared.open(Updater.releasesPage) }
                Spacer()
                PillButton(title: "Try again", symbol: "arrow.clockwise", prominent: true) {
                    Task { await updater.check(userInitiated: true) }
                }
            case .upToDate:
                Spacer()
                PillButton(title: "OK", prominent: true) { close() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func close() {
        switch updater.state {
        case .downloading, .installing: return
        default: withAnimation(Theme.spring) { updater.showDialog = false }
        }
    }

    private static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}
