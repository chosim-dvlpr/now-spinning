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
    private var updateItem: NSMenuItem!
    private var pending: Updater.Release?
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
        updateItem = menu.addItem(withTitle: "업데이트 확인…", action: #selector(checkUpdateClicked), keyEquivalent: "u")
        updateItem.target = self
        menu.addItem(withTitle: "Quit NowSpinning", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        checkUpdate(silent: true)

        spotify.$pid.removeDuplicates().sink { [audio] in audio.retarget(pid: $0) }.store(in: &bag)
        spotify.start()
        audio.start()
    }

    @objc private func checkUpdateClicked() { checkUpdate(silent: false) }

    /// 실행 시 조용히 확인해 메뉴 제목만 바꾸고, 버튼을 누르면 내려받아 설치 후 재실행
    private func checkUpdate(silent: Bool) {
        if let r = pending { return install(r) }
        updateItem.title = "확인 중…"; updateItem.isEnabled = false
        Updater.latest { r in
            DispatchQueue.main.async {
                self.pending = r
                self.updateItem.isEnabled = true
                self.updateItem.title = r.map { "v\($0.version) 업데이트 설치" } ?? "업데이트 확인…"
                if !silent, r == nil { self.alert("최신 버전입니다 (v\(Updater.current))") }
            }
        }
    }

    private func install(_ r: Updater.Release) {
        updateItem.title = "v\(r.version) 내려받는 중…"; updateItem.isEnabled = false
        Updater.install(r) { msg in
            DispatchQueue.main.async {
                self.updateItem.isEnabled = true; self.updateItem.title = "v\(r.version) 업데이트 설치"
                self.alert("업데이트 실패: \(msg)")
            }
        }
    }

    private func alert(_ text: String) {
        let a = NSAlert(); a.messageText = "NowSpinning"; a.informativeText = text; a.runModal()
    }
}
