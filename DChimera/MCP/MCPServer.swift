import AppKit
import Foundation

/// `DChimera --mcp [--write]`: an MCP server on stdin / stdout (JSON-RPC 2.0, one message per line).
/// Claude Code, Claude Desktop or Cursor start it as a child process; no window opens.
/// The mode is fixed per process: the user registers a read-only and a read-write entry and picks one in Claude.
/// Nothing else may write to stdout in this mode — diagnostics go to stderr.
final class MCPServer: @unchecked Sendable {
    static let protocolVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]

    private let mode = MCPMode.fromArguments
    private let tools: MCPTools
    private let output = DispatchQueue(label: "dchimera.mcp.output")
    private var lastEnabled: Bool
    private var poll: DispatchSourceTimer?

    private init() {
        tools = MCPTools(mode: mode)
        lastEnabled = MCPConfigStore.load().enabled
    }

    /// Entry point for `--mcp`. Never returns: exits when the client closes stdin.
    static func runForever() -> Never {
        let server = MCPServer()
        server.watchMode()
        Thread.detachNewThread { server.readLoop() }
        // The main thread runs a plain run loop and stays free for the windows MCPConfirm shows.
        // Not dispatchMain(): it ends the main thread, the main queue then runs on worker threads
        // and AppKit refuses to create windows there.
        RunLoop.main.add(Timer(timeInterval: 86_400, repeats: true) { _ in }, forMode: .default)
        while true {
            RunLoop.main.run(mode: .default, before: .distantFuture)
        }
    }

    // MARK: Input

    private func readLoop() {
        while let line = readLine(strippingNewline: true) {
            let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            // One request at a time, in order: the drivers keep one connection each.
            let done = DispatchSemaphore(value: 0)
            Task.detached {
                await self.handle(text)
                done.signal()
            }
            done.wait()
        }
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            await self.tools.closeAll()
            done.signal()
        }
        _ = done.wait(timeout: .now() + 3)
        exit(0)
    }

    private func handle(_ text: String) async {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            send(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
            return
        }
        if let batch = object as? [[String: Any]] {
            for message in batch { await handle(message: message) }
        } else if let message = object as? [String: Any] {
            await handle(message: message)
        } else {
            send(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32600, "message": "Invalid request"]])
        }
    }

    private func handle(message: [String: Any]) async {
        guard let method = message["method"] as? String else { return } // a response to us: we send no requests
        let id = message["id"]
        let params = message["params"] as? [String: Any] ?? [:]
        guard let id, !(id is NSNull) else { return } // a notification: nothing to answer

        switch method {
        case "initialize":
            let asked = params["protocolVersion"] as? String ?? ""
            let version = Self.protocolVersions.contains(asked) ? asked : Self.protocolVersions[0]
            reply(id, [
                "protocolVersion": version,
                "capabilities": ["tools": ["listChanged": true]],
                "serverInfo": [
                    "name": mode.serverName,
                    "title": mode == .readWrite ? "DChimera (read & write)" : "DChimera (read only)",
                    "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
                ],
                "instructions": MCPTools.instructions(for: mode),
            ])
        case "ping":
            reply(id, [:])
        case "tools/list":
            let enabled = MCPConfigStore.load().enabled
            output.sync { lastEnabled = enabled }
            reply(id, ["tools": enabled ? MCPTools.definitions(for: mode) : []])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            let outcome = await tools.call(name, arguments: arguments)
            var result: [String: Any] = ["content": [["type": "text", "text": outcome.text]]]
            if outcome.isError { result["isError"] = true }
            reply(id, result)
        case "resources/list":
            reply(id, ["resources": []])
        case "prompts/list":
            reply(id, ["prompts": []])
        default:
            send(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found: \(method)"]])
        }
    }

    // MARK: Output

    private func reply(_ id: Any, _ result: [String: Any]) {
        send(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func send(_ message: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: message, options: [.withoutEscapingSlashes]) else { return }
        data.append(0x0A)
        output.sync {
            FileHandle.standardOutput.write(data)
        }
    }

    /// The switch in Settings → Claude (MCP) can turn access off while Claude is connected:
    /// tell the client the tool list changed.
    private func watchMode() {
        let timer = DispatchSource.makeTimerSource(queue: output)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let enabled = MCPConfigStore.load().enabled
            guard enabled != self.lastEnabled else { return }
            self.lastEnabled = enabled
            var data = (try? JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "method": "notifications/tools/list_changed"],
                                                     options: [.withoutEscapingSlashes])) ?? Data()
            data.append(0x0A)
            FileHandle.standardOutput.write(data)
        }
        timer.resume()
        poll = timer
    }

    static func log(_ text: String) {
        FileHandle.standardError.write(Data("dchimera-mcp: \(text)\n".utf8))
    }
}

/// macOS windows the MCP server shows the user: a confirmation before a dangerous statement,
/// and the password of a connection Claude adds (so the password never goes through Claude).
enum MCPConfirm {
    /// nil when the user cancelled; an empty string means "no password".
    static func askPassword(connection: String, target: String) -> String? {
        #if DEBUG
        if let password = ProcessInfo.processInfo.environment["DCHIMERA_MCP_PASSWORD"] {
            MCPServer.log("password asked for \(connection) (\(target))")
            return password == "<cancel>" ? nil : password
        }
        #endif
        return DispatchQueue.main.sync {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            let alert = NSAlert()
            alert.messageText = "Claude is adding the connection “\(connection)”"
            alert.informativeText = "\(target)\n\nType its password. DChimera keeps it in the Keychain; Claude never sees it. Leave it empty if the database needs no password."
            let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
            field.placeholderString = "Password"
            alert.accessoryView = field
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Cancel")
            alert.window.level = .floating
            alert.window.initialFirstResponder = field
            let answer = present(alert, takeFocus: true)
            return answer == .alertFirstButtonReturn ? field.stringValue : nil
        }
    }

    static func ask(connection: String, reasons: [String], sql: String) -> Bool {
        #if DEBUG
        if let answer = ProcessInfo.processInfo.environment["DCHIMERA_MCP_CONFIRM"] {
            MCPServer.log("confirm (\(answer)): \(reasons.joined(separator: " "))")
            return answer == "yes"
        }
        #endif
        return DispatchQueue.main.sync {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Claude wants to run this on “\(connection)”"
            alert.informativeText = reasons.joined(separator: "\n")
            let shown = sql.count > 1500 ? String(sql.prefix(1500)) + "\n…" : sql
            let text = NSTextField(wrappingLabelWithString: shown)
            text.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
            text.isSelectable = true
            text.preferredMaxLayoutWidth = 420
            text.frame.size = text.fittingSize
            alert.accessoryView = text
            alert.addButton(withTitle: "Cancel")
            // Only a click runs it: the button takes no keyboard focus and has no key; Return and Esc mean Cancel.
            let run = alert.addButton(withTitle: "Run anyway")
            run.hasDestructiveAction = true
            run.refusesFirstResponder = true
            run.keyEquivalent = ""
            alert.window.level = .floating
            let answer = present(alert, takeFocus: false)
            return answer == .alertSecondButtonReturn
        }
    }

    /// `takeFocus`: bring DChimera forward so the password field gets the keyboard without a click.
    private static func present(_ alert: NSAlert, takeFocus: Bool) -> NSApplication.ModalResponse {
        if takeFocus {
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            NSApp.activate(ignoringOtherApps: true)
        }
        #if DEBUG
        // DCHIMERA_MCP_WINDOW_TEST=1: show the real window, report whether it is on screen, close it after 1.5 s.
        if let test = ProcessInfo.processInfo.environment["DCHIMERA_MCP_WINDOW_TEST"] {
            if test == "keys" {
                // Press Tab, Tab, Space, Tab, Space, Return in the window, as someone typing into it would.
                let keys: [(String, UInt16)] = [("\t", 48), ("\t", 48), (" ", 49), ("\t", 48), (" ", 49), ("\r", 36)]
                for (i, key) in keys.enumerated() {
                    let t = Timer(timeInterval: 0.4 + Double(i) * 0.15, repeats: false) { _ in
                        let w = alert.window
                        guard let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                       windowNumber: w.windowNumber, context: nil, characters: key.0,
                                                       charactersIgnoringModifiers: key.0, isARepeat: false, keyCode: key.1) else { return }
                        let focused = (w.firstResponder as? NSButton)?.title ?? w.firstResponder.map { String(describing: type(of: $0)) } ?? "none"
                        MCPServer.log("key \(key.1), focus on: \(focused)")
                        if !w.performKeyEquivalent(with: e) { w.sendEvent(e) }
                    }
                    RunLoop.main.add(t, forMode: .modalPanel)
                }
            }
            let timer = Timer(timeInterval: 1.8, repeats: false) { _ in
                let w = alert.window
                MCPServer.log("window test: appActive=\(NSApp.isActive) visible=\(w.isVisible) onScreen=\(w.occlusionState.contains(.visible)) key=\(w.isKeyWindow) level=\(w.level.rawValue) title=\(alert.messageText)")
                NSApp.abortModal()
            }
            RunLoop.main.add(timer, forMode: .modalPanel)
        }
        #endif
        let response = alert.runModal()
        #if DEBUG
        MCPServer.log("window closed: response=\(response.rawValue) title=\(alert.messageText)")
        #endif
        return response
    }
}
