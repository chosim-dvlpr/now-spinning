import AppKit

/// GitHub Releases에서 최신 버전을 확인하고, 내려받아 앱 번들을 교체한 뒤 재실행한다.
/// ponytail: Sparkle 대신 수제. 서명 검증 없음(ad-hoc 서명이라 의미 없음). HTTPS + GitHub만 신뢰.
final class Updater {
    static let repo = "chosim-dvlpr/now-spinning"
    static let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

    struct Release { let version: String; let zipURL: URL }

    static func latest(_ done: @escaping (Release?) -> Void) {
        let api = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        URLSession.shared.dataTask(with: api) { data, _, _ in
            guard let data, let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = j["tag_name"] as? String,
                  let assets = j["assets"] as? [[String: Any]],
                  let zip = assets.first(where: { ($0["name"] as? String) == "NowSpinning.zip" })?["browser_download_url"] as? String,
                  let url = URL(string: zip), url.scheme == "https", url.host == "github.com"
            else { return done(nil) }
            let v = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            done(isNewer(v, than: current) ? Release(version: v, zipURL: url) : nil)
        }.resume()
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        a.compare(b, options: .numeric) == .orderedDescending
    }

    /// 내려받기 → 임시 폴더에 풀기 → 현재 번들을 휴지통으로 → 새 번들을 제자리에 → 재실행
    static func install(_ r: Release, _ fail: @escaping (String) -> Void) {
        URLSession.shared.downloadTask(with: r.zipURL) { tmp, _, err in
            guard let tmp else { return fail(err?.localizedDescription ?? "다운로드 실패") }
            do {
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent("NowSpinning-update-\(r.version)")
                try? FileManager.default.removeItem(at: dir)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try run("/usr/bin/ditto", ["-x", "-k", tmp.path, dir.path])
                let newApp = dir.appendingPathComponent("NowSpinning.app")
                guard FileManager.default.fileExists(atPath: newApp.path) else { return fail("zip 안에 NowSpinning.app이 없음") }
                try run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])
                let dest = Bundle.main.bundleURL
                try FileManager.default.trashItem(at: dest, resultingItemURL: nil)
                try FileManager.default.moveItem(at: newApp, to: dest)
                // 같은 번들 ID가 떠 있으면 open이 기존 인스턴스를 활성화만 하므로, 종료 후 1초 뒤에 열도록 분리된 셸에 맡김
                let relaunch = Process()
                relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
                relaunch.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", dest.path]
                try relaunch.run()
                DispatchQueue.main.async { NSApp.terminate(nil) }
            } catch { fail(error.localizedDescription) }
        }.resume()
    }

    private static func run(_ path: String, _ args: [String]) throws {
        let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
        try p.run(); p.waitUntilExit()
        if p.terminationStatus != 0 { throw NSError(domain: "Updater", code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "\(path) 실패"]) }
    }
}
