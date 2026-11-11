import AppKit
import SwiftUI

/// Where the window's close / minimize / zoom buttons are, in SwiftUI coordinates (top-left origin).
/// The content runs under the hidden title bar, so the layout leaves exactly this much room for them.
@MainActor
final class WindowChrome: ObservableObject {
    @Published var controls = CGRect(x: 12, y: 10, width: 66, height: 18)

    /// Height to keep free at the top of a column that starts at the window's left edge.
    var topInset: CGFloat { controls == .zero ? 12 : controls.maxY + 10 }
    /// Width to keep free on the left of the first row.
    var leadingInset: CGFloat { controls == .zero ? 0 : controls.maxX + 10 }

    /// The floating sidebar of Wet Asphalt starts below the buttons; other themes keep them inside the sidebar.
    var buttonsInsideSidebar: Bool { !Skin.current.isGlass }

    /// Top edge of the floating sidebar panel.
    var panelTop: CGFloat { max(topInset - 2, 10) }

    /// Unused horizontal offset kept for the title row (the panel never sits under the buttons).
    var panelOffset: CGFloat { 0 }

    /// Leading padding of the sidebar's first row.
    var titleLeading: CGFloat { buttonsInsideSidebar ? max(leadingInset, 12) : 14 }

    /// Height of the sidebar's first row: centered on the window buttons when they are inside the sidebar.
    var buttonRowHeight: CGFloat {
        guard buttonsInsideSidebar, controls != .zero else { return 40 }
        return max(2 * controls.midY, controls.maxY + 6, 36)
    }

    /// Free space above a sidebar column's first content.
    var columnTopInset: CGFloat { buttonsInsideSidebar ? max(topInset, 12) : 12 }
}

/// Invisible view that measures the window buttons and keeps `WindowChrome` up to date.
struct WindowChromeReader: NSViewRepresentable {
    let chrome: WindowChrome

    func makeNSView(context: Context) -> ChromeProbeView {
        let view = ChromeProbeView()
        view.chrome = chrome
        return view
    }

    func updateNSView(_ nsView: ChromeProbeView, context: Context) {
        nsView.chrome = chrome
    }
}

final class ChromeProbeView: NSView {
    weak var chrome: WindowChrome?
    private var observers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        guard let window else { return }
        let names: [Notification.Name] = [NSWindow.didResizeNotification, NSWindow.didEnterFullScreenNotification,
                                          NSWindow.didExitFullScreenNotification, NSWindow.didBecomeKeyNotification]
        for name in names {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                self?.measure()
            })
        }
        DispatchQueue.main.async { [weak self] in self?.measure() }
    }

    func measure() {
        guard let window, let content = window.contentView else { return }
        let rect: CGRect
        if window.styleMask.contains(.fullScreen) {
            rect = .zero
        } else {
            let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { window.standardWindowButton($0) }
                .filter { !$0.isHidden }
            guard !buttons.isEmpty else { return }
            let frames = buttons.map { $0.convert($0.bounds, to: nil) }
            let union = frames.dropFirst().reduce(frames[0]) { $0.union($1) }
            let height = content.convert(content.bounds, to: nil).maxY
            rect = CGRect(x: union.minX, y: height - union.maxY, width: union.width, height: union.height).integral
        }
        if let chrome = chrome, chrome.controls != rect {
            Task { @MainActor in chrome.controls = rect }
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}
