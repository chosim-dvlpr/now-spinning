import SwiftUI
import Combine

@main
struct NowSpinningApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel!
    private var statusItem: NSStatusItem!
    private let spotify = SpotifyPoller()
    private var bag = Set<AnyCancellable>()
    private let audio = AudioTap()

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 184, height: 212),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: WidgetView(spotify: spotify, audio: audio))
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.maxX - 204, y: f.maxY - 232))
        }
        panel.orderFrontRegardless()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "opticaldisc", accessibilityDescription: nil)
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit NowSpinning", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        spotify.$pid.removeDuplicates().sink { [audio] in audio.retarget(pid: $0) }.store(in: &bag)
        spotify.start()
        audio.start()
    }
}
