import AppKit
import Combine

final class SpotifyPoller: ObservableObject {
    @Published var running = false
    @Published var playing = false
    @Published var title = ""
    @Published var artist = ""
    @Published var artwork: NSImage?
    @Published var accent = NSColor(white: 0.2, alpha: 1)
    @Published var pid: pid_t = 0
    private var artworkURL = ""

    private let script = NSAppleScript(source: """
    tell application "Spotify"
        if it is running then
            return {player state as string, name of current track, artist of current track, artwork url of current track}
        end if
        return {"off"}
    end tell
    """)!

    func start() {
        poll()
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.poll() }
    }

    private func poll() {
        var err: NSDictionary?
        let r = script.executeAndReturnError(&err)
        pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").first?.processIdentifier ?? 0
        guard r.numberOfItems >= 4 else { running = false; playing = false; return }
        running = true
        playing = r.atIndex(1)?.stringValue == "playing"
        title = r.atIndex(2)?.stringValue ?? ""
        artist = r.atIndex(3)?.stringValue ?? ""
        let url = r.atIndex(4)?.stringValue ?? ""
        if url != artworkURL, let u = URL(string: url), u.scheme == "https" {  // Spotify CDN만, 평문 http 차단
            artworkURL = url
            URLSession.shared.dataTask(with: u) { data, _, _ in
                guard let d = data, let img = NSImage(data: d) else { return }
                let c = Self.dominantColor(img)
                DispatchQueue.main.async { self.artwork = img; self.accent = c }
            }.resume()
        }
    }

    /// 미실행이면 실행, 실행 중이면 맨 앞으로
    func activatePlayer() { NSWorkspace.shared.open(URL(string: "spotify:")!) }

    // ponytail: 8x8로 축소해 가장 채도 높은 픽셀 선택. k-means 필요하면 교체
    static func dominantColor(_ img: NSImage) -> NSColor {
        let n = 8
        var px = [UInt8](repeating: 0, count: n * n * 4)
        guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let ctx = CGContext(data: &px, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return NSColor(white: 0.2, alpha: 1) }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
        var best = NSColor(white: 0.2, alpha: 1), bestScore: CGFloat = -1
        for i in stride(from: 0, to: px.count, by: 4) {
            let c = NSColor(red: CGFloat(px[i]) / 255, green: CGFloat(px[i+1]) / 255, blue: CGFloat(px[i+2]) / 255, alpha: 1)
            let score = c.saturationComponent * (1 - abs(c.brightnessComponent - 0.5))
            if score > bestScore { bestScore = score; best = c }
        }
        return NSColor(hue: best.hueComponent, saturation: min(0.8, best.saturationComponent), brightness: min(0.55, best.brightnessComponent), alpha: 1)
    }
}
