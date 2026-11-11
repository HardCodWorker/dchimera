import AppKit
import SwiftUI

@main
struct DChimeraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var app = AppModel.shared

    var body: some Scene {
        WindowGroup("DChimera", id: "main") {
            RootView()
                .environmentObject(app)
                .frame(minWidth: 1020, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1320, height: 840)
        .commands { DChimeraCommands(app: app) }

        Settings {
            SettingsView()
                .environmentObject(app)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        Task { @MainActor in Updater.shared.checkOnLaunch() }
        #if DEBUG
        Task { @MainActor in
            if UpdateSelfTest.startIfRequested() { return }
            if !GridBenchmark.startIfRequested() { DemoAutomation.startIfRequested() }
        }
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct DChimeraCommands: Commands {
    @ObservedObject var app: AppModel

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { Task { await Updater.shared.check(userInitiated: true) } }
        }
        CommandGroup(replacing: .newItem) {
            Button("New Connection…") { app.newConnection() }
                .keyboardShortcut("n")
            Button("Add Demo Database") { app.addDemoDatabase() }
        }
        CommandMenu("Query") {
            Button("Run Statement") { app.openSession?.runFromComposer(all: false) }
                .keyboardShortcut(.return, modifiers: .command)
            Button("Run All") { app.openSession?.runFromComposer(all: true) }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
            Divider()
            Button("Quick Switcher") { withAnimation(Theme.bouncy) { app.quickSwitcher.toggle() } }
                .keyboardShortcut("k")
            Button("Refresh") {
                guard let s = app.openSession else { return }
                if let t = s.activeTab?.table {
                    Task { await s.model(for: t).reload() }
                } else {
                    Task { await s.reloadSchema() }
                }
            }
            .keyboardShortcut("r")
            Button("All Connections") { app.closeConnectionView() }
                .keyboardShortcut("[")
            Button("New SQL Tab") { app.openSession?.newQueryTab() }
                .keyboardShortcut("t")
            Button("Next Theme") {
                let all = SkinKind.allCases
                let current = SkinKind(rawValue: UserDefaults.standard.string(forKey: "skin") ?? "") ?? .telegram
                let next = all[((all.firstIndex(of: current) ?? 0) + 1) % all.count]
                UserDefaults.standard.set(next.rawValue, forKey: "skin")
            }
            .keyboardShortcut("t", modifiers: [.command, .control])
            Divider()
            ForEach(Array(app.sortedConnections.prefix(9).enumerated()), id: \.element.id) { i, c in
                Button(c.displayName) { app.open(c.id) }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
            }
        }
    }
}
