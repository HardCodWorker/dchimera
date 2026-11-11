import SwiftUI

struct SettingsView: View {
    @AppStorage("appearance") private var appearance: Appearance = .system
    @AppStorage("accentIndex") private var accentIndex = 0
    @AppStorage("rowLimit") private var rowLimit = 1000
    @AppStorage("editorFontSize") private var fontSize = 13.0
    @AppStorage("confirmDangerous") private var confirmDangerous = true
    @AppStorage("skin") private var skinRaw = SkinKind.telegram.rawValue
    @AppStorage("autoCheckUpdates") private var autoCheckUpdates = true
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        Form {
            Section("Theme") {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(160), spacing: 14), count: 3), spacing: 16) {
                    ForEach(SkinKind.allCases) { kind in
                        let selected = skinRaw == kind.rawValue
                        VStack(spacing: 6) {
                            SkinPreview(kind: kind, selected: selected)
                                .scaleEffect(selected ? 1.03 : 1)
                            Label(kind.title, systemImage: kind.symbol)
                                .font(.system(size: 12.5, weight: selected ? .bold : .medium))
                            Text(kind.subtitle)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(width: 150)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(Theme.bouncy) { skinRaw = kind.rawValue } }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            Section("Look") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(Appearance.allCases) { a in Label(a.title, systemImage: a.symbol).tag(a) }
                }
                .pickerStyle(.segmented)
                if skinRaw == SkinKind.matrix.rawValue {
                    Text("Matrix always uses phosphor green and a dark window.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                if let kind = SkinKind(rawValue: skinRaw), Skin.make(kind).isScenic {
                    Text("\(kind.title) always uses its own accent and a dark window.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Accent")
                    Spacer()
                    ForEach(Theme.accents.indices, id: \.self) { i in
                        let option = Theme.accents[i]
                        Circle()
                            .fill(LinearGradient(colors: [option.top, option.bottom], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 22, height: 22)
                            .overlay(Circle().stroke(Color.primary.opacity(accentIndex == i ? 0.8 : 0), lineWidth: 2).padding(-4))
                            .scaleEffect(accentIndex == i ? 1.12 : 1)
                            .onTapGesture { withAnimation(Theme.bouncy) { accentIndex = i } }
                            .help(option.name)
                    }
                }
            }
            Section("Console") {
                Picker("Row limit", selection: $rowLimit) {
                    ForEach([100, 500, 1000, 5000, 10000], id: \.self) { Text(Fmt.grouped($0)).tag($0) }
                }
                HStack {
                    Text("Editor font")
                    Slider(value: $fontSize, in: 11...18, step: 1)
                    Text("\(Int(fontSize)) pt").monospacedDigit().frame(width: 40)
                }
                Toggle("Ask before DROP, TRUNCATE, ALTER and DELETE/UPDATE without WHERE", isOn: $confirmDangerous)
            }
            Section("Updates") {
                LabeledContent("Version") {
                    HStack(spacing: 10) {
                        Text(updater.currentVersion).monospacedDigit()
                        if let release = updater.available {
                            Text("\(release.version) available").foregroundStyle(Theme.success)
                        }
                    }
                }
                Toggle("Check for updates when DChimera starts", isOn: $autoCheckUpdates)
                HStack {
                    Button(updater.available == nil ? "Check Now" : "Show Update…") {
                        if updater.available != nil { updater.showDialog = true } else { Task { await updater.check(userInitiated: true) } }
                    }
                    if let checked = updater.lastChecked {
                        Text("Last checked \(Fmt.time(checked))").font(.system(size: 11.5)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Link("Releases on GitHub", destination: Updater.releasesPage).font(.system(size: 11.5))
                }
            }
            Section("Storage") {
                LabeledContent("Connections & history") {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([AppPaths.dataDirectory]) }
                }
                Text("Passwords are kept in the macOS Keychain (service “\(Keychain.service)”), never in files.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 620, height: 860)
    }
}
