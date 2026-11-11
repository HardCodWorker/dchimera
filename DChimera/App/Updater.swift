import AppKit
import Foundation

/// Checks GitHub Releases for a newer DChimera and installs it.
///
/// One public release channel serves every platform: `HardCodWorker/dchimera`, tags `vX.Y.Z`.
/// The macOS app takes the `.dmg` asset of the latest release, copies DChimera.app out of it next to the running app,
/// quits, swaps the bundles with a small shell script and opens the new version.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    static let repository = "HardCodWorker/dchimera"
    /// Where the latest release is described. `DCHIMERA_UPDATE_URL` overrides it (a local file or server, for testing).
    static var feedURL: URL {
        if let custom = ProcessInfo.processInfo.environment["DCHIMERA_UPDATE_URL"], let url = URL(string: custom) { return url }
        return URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    }
    static let releasesPage = URL(string: "https://github.com/\(repository)/releases")!

    struct Release: Equatable {
        let version: String
        let notes: String
        let page: URL
        let dmg: URL
        let size: Int64
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case downloading(Release, Double)
        case installing(Release)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    /// The update window is open.
    @Published var showDialog = false
    @Published private(set) var lastChecked: Date?

    var currentVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    var available: Release? {
        switch state {
        case .available(let r), .downloading(let r, _), .installing(let r): r
        default: nil
        }
    }

    var autoCheck: Bool {
        get { UserDefaults.standard.object(forKey: "autoCheckUpdates") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoCheckUpdates") }
    }

    private var downloadTask: URLSessionDownloadTask?

    /// Called once at launch: a quiet check a few seconds later, only if the user keeps automatic checks on.
    func checkOnLaunch() {
        guard autoCheck, ProcessInfo.processInfo.environment["DCHIMERA_DEMO_OUT"] == nil else { return }
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await check(userInitiated: false)
        }
    }

    /// Asks GitHub for the latest release. A user-initiated check opens the update window with the result.
    func check(userInitiated: Bool) async {
        if case .downloading = state { return }
        if case .installing = state { return }
        state = .checking
        if userInitiated { showDialog = true }
        do {
            let release = try await Self.fetchLatest()
            lastChecked = Date()
            if let release, Self.isNewer(release.version, than: currentVersion) {
                state = .available(release)
                if userInitiated { showDialog = true }
            } else {
                state = .upToDate
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Downloads the new version, puts it next to the running app, quits and relaunches into it.
    func install() async {
        guard let release = available else { return }
        do {
            let target = Bundle.main.bundleURL
            try Self.checkReplaceable(target)
            state = .downloading(release, 0)
            let dmg = try await download(release)
            state = .installing(release)
            let staged = try await Self.stage(dmg: dmg, expectedVersion: release.version, next: target)
            try Self.swapAndRelaunch(staged: staged, target: target)
            NSApp.terminate(nil)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        if let release = available { state = .available(release) }
    }

    // MARK: - Release feed

    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
            let size: Int64?
        }

        let tag_name: String
        let body: String?
        let html_url: URL?
        let draft: Bool?
        let prerelease: Bool?
        let assets: [Asset]
    }

    enum UpdateError: LocalizedError {
        case http(Int)
        case noReleases
        case noMacBuild(String)
        case notReplaceable(String)
        case badPackage(String)

        var errorDescription: String? {
            switch self {
            case .http(let code): "GitHub answered with HTTP \(code)."
            case .noReleases: "No releases are published yet."
            case .noMacBuild(let v): "Release \(v) has no macOS .dmg yet."
            case .notReplaceable(let why): why
            case .badPackage(let why): "The downloaded package looks wrong: \(why)"
            }
        }
    }

    private static func fetchLatest() async throws -> Release? {
        var request = URLRequest(url: feedURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("DChimera-Updater", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 404 { throw UpdateError.noReleases }
            guard (200..<300).contains(http.statusCode) else { throw UpdateError.http(http.statusCode) }
        }
        let json = try JSONDecoder().decode(GitHubRelease.self, from: data)
        if json.draft == true || json.prerelease == true { return nil }
        let version = json.tag_name.hasPrefix("v") ? String(json.tag_name.dropFirst()) : json.tag_name
        guard let asset = json.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }) else {
            throw UpdateError.noMacBuild(version)
        }
        return Release(version: version, notes: json.body ?? "", page: json.html_url ?? releasesPage,
                       dmg: asset.browser_download_url, size: asset.size ?? 0)
    }

    /// Compares dotted versions numerically: 0.10.0 is newer than 0.9.3.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ v: String) -> [Int] {
            v.split(whereSeparator: { $0 == "." || $0 == "-" }).map { Int($0.filter(\.isNumber)) ?? 0 }
        }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: - Download

    private func download(_ release: Release) async throws -> URL {
        let progress = DownloadProgress { [weak self] fraction in
            Task { @MainActor in
                guard let self, case .downloading(let r, _) = self.state else { return }
                self.state = .downloading(r, fraction)
            }
        }
        let session = URLSession(configuration: .ephemeral, delegate: progress, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { continuation in
            progress.completion = { result in continuation.resume(with: result) }
            let task = session.downloadTask(with: release.dmg)
            downloadTask = task
            task.resume()
        }
    }

    // MARK: - Install

    /// The running app must sit in a folder we can write to, not in a read-only translocated copy.
    private static func checkReplaceable(_ target: URL) throws {
        if target.path.contains("/AppTranslocation/") {
            throw UpdateError.notReplaceable("Move DChimera to the Applications folder first, open it from there, then update.")
        }
        let parent = target.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            throw UpdateError.notReplaceable("No permission to write to \(parent.path). Install the update from the .dmg by hand.")
        }
    }

    /// Mounts the .dmg, checks the app inside and copies it next to the running app under a temporary name.
    private static func stage(dmg: URL, expectedVersion: String, next target: URL) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let mount = fm.temporaryDirectory.appendingPathComponent("dchimera-update-\(UUID().uuidString)")
            try fm.createDirectory(at: mount, withIntermediateDirectories: true)
            try run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path, dmg.path])
            defer {
                _ = try? run("/usr/bin/hdiutil", ["detach", mount.path, "-force"])
                try? fm.removeItem(at: mount)
                try? fm.removeItem(at: dmg)
            }
            let app = mount.appendingPathComponent("DChimera.app")
            guard let bundle = Bundle(url: app), bundle.bundleIdentifier == Bundle.main.bundleIdentifier else {
                throw UpdateError.badPackage("no DChimera.app with the same bundle id inside")
            }
            let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
            guard version == expectedVersion else {
                throw UpdateError.badPackage("the app inside is version \(version), the release says \(expectedVersion)")
            }
            try run("/usr/bin/codesign", ["--verify", "--deep", app.path])
            let staged = target.deletingLastPathComponent().appendingPathComponent(".DChimera-\(version)-update.app")
            try? fm.removeItem(at: staged)
            try run("/usr/bin/ditto", [app.path, staged.path])
            _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged.path])
            return staged
        }.value
    }

    /// Writes a script that waits for this process to quit, swaps the bundles (rolling back on failure) and opens the result.
    private static func swapAndRelaunch(staged: URL, target: URL) throws {
        let script = """
        #!/bin/sh
        PID=\(ProcessInfo.processInfo.processIdentifier)
        TARGET=\(shellQuote(target.path))
        NEW=\(shellQuote(staged.path))
        OLD="$TARGET.old-$$"
        i=0
        while kill -0 "$PID" 2>/dev/null && [ $i -lt 300 ]; do sleep 0.1; i=$((i+1)); done
        if mv "$TARGET" "$OLD"; then
          if mv "$NEW" "$TARGET"; then rm -rf "$OLD"; else mv "$OLD" "$TARGET"; rm -rf "$NEW"; fi
        fi
        open "$TARGET"
        rm -f "$0"
        """
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("dchimera-swap-\(UUID().uuidString).sh")
        try script.write(to: file, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [file.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    private nonisolated static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    @discardableResult
    private nonisolated static func run(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.badPackage("\(URL(fileURLWithPath: tool).lastPathComponent) failed: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return output
    }
}

/// URLSession delegate that reports download progress and hands back the finished file.
private final class DownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let onProgress: (Double) -> Void
    var completion: ((Result<URL, Error>) -> Void)?

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The file at `location` is deleted when this method returns, so move it first.
        let kept = FileManager.default.temporaryDirectory.appendingPathComponent("DChimera-update-\(UUID().uuidString).dmg")
        do {
            if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw Updater.UpdateError.http(http.statusCode)
            }
            try FileManager.default.moveItem(at: location, to: kept)
            completion?(.success(kept))
        } catch {
            completion?(.failure(error))
        }
        completion = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { completion?(.failure(error)) }
        completion = nil
    }
}
