import SwiftUI

struct WidgetView: View {
    @ObservedObject var spotify: SpotifyPoller
    @ObservedObject var audio: AudioTap
    @State private var angle = 0.0
    // 곡 전환 모션: 새 커버가 오면 6시부터 시계방향 부채꼴로 덮음
    @State private var shownArt: NSImage?
    @State private var prevArt: NSImage?   // 와이프 중 아래에 깔리는 이전 커버
    @State private var wipe = 1.0
    @State private var wipeDir = 1.0       // 1: 다음곡(시계방향), -1: 이전곡(반시계)
    @State private var hovering = false
    @State private var volume = 50.0
    @State private var editingVolume = false
    private let spin = Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                cd
                if hovering && spotify.running { controls.transition(.opacity) }
            }
            .padding(.top, 10).padding(.bottom, 36)
            VStack(spacing: 5) {
                waveform
                Text(spotify.running ? spotify.title : "Spotify 꺼짐")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Text(spotify.artist)
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
            }
            .padding(5).padding(.horizontal, 5).padding(.vertical, 5)
            .frame(width: 160)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(nsColor: spotify.accent).opacity(0.92))
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
            )
            .animation(.easeInOut(duration: 0.6), value: spotify.accent)
            .padding(.bottom, 20)
        }
        .frame(width: 184, height: 212)
        .opacity(spotify.running ? 1 : 0.6)
        .onReceive(spin) { _ in
            if spotify.playing { angle += 1.2 }
        }
        .onChange(of: spotify.artwork) { wipeTo($1) }
        .onChange(of: spotify.volume) { if !editingVolume { volume = Double($1) } }
        .onHover { h in withAnimation(.easeInOut(duration: 0.2)) { hovering = h } }
        .onTapGesture { spotify.activatePlayer() }
    }

    private var cd: some View {
        ZStack {
            ZStack {
                if let img = prevArt { Image(nsImage: img).resizable().scaledToFill().frame(width: 150, height: 150) }
                Group {
                    if let img = shownArt { Image(nsImage: img).resizable().scaledToFill() }
                    else { Circle().fill(Color(white: 0.2)) }
                }
                .frame(width: 150, height: 150)
                .mask(Sector(progress: wipe, dir: wipeDir).rotationEffect(.degrees(-angle)))  // 역회전해 화면 기준 6시에서 시작
            }
            .frame(width: 150, height: 150).clipShape(Circle())  // 두 커버 모두 원 안으로
            // CD 광택
            Circle().fill(AngularGradient(colors: [.clear, .white.opacity(0.25), .clear, .white.opacity(0.15), .clear, .white.opacity(0.2), .clear], center: .center))
            Circle().stroke(.white.opacity(0.35), lineWidth: 1)
            Circle().fill(.black.opacity(0.85)).frame(width: 24, height: 24)
            Circle().stroke(.white.opacity(0.5), lineWidth: 1).frame(width: 24, height: 24)
        }
        .frame(width: 150, height: 150)
        .rotationEffect(.degrees(angle))
        .shadow(color: .black.opacity(0.45), radius: 5, y: 3)
    }

    private func wipeTo(_ img: NSImage?) {
        guard shownArt != nil else { shownArt = img; return }  // 첫 로드는 그냥 표시
        prevArt = shownArt; shownArt = img; wipe = 0
        // 같은 런루프면 wipe = 0과 합쳐져 애니메이션이 안 보임
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.6)) { wipe = 1 } completion: {
                prevArt = nil
                wipeDir = 1  // ponytail: Spotify 쪽에서 넘긴 곡은 방향을 모르니 시계방향
            }
        }
    }

    private var controls: some View {
        ZStack {
            Circle().fill(.black.opacity(0.5)).frame(width: 150, height: 150)
            VStack(spacing: 14) {
                HStack(spacing: 18) {
                    button("backward.fill", 16) { wipeDir = -1; spotify.send("previous track") }
                    button(spotify.playing ? "pause.fill" : "play.fill", 26) { spotify.send("playpause") }
                    button("forward.fill", 16) { wipeDir = 1; spotify.send("next track") }
                }
                HStack(spacing: 4) {
                    Image(systemName: "speaker.fill").font(.system(size: 8))
                    Slider(value: $volume, in: 0...100) { editing in
                        editingVolume = editing
                        if !editing { spotify.setVolume(Int(volume)) }
                    }
                    .controlSize(.mini).frame(width: 70)
                }
                .foregroundStyle(.white)
            }
            .padding(.top, 20)  // 가운데 구멍 피해 살짝 아래로
        }
    }

    private func button(_ symbol: String, _ size: CGFloat, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size)).foregroundStyle(.white)
                .frame(width: 30, height: 30).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 커버 색과 같은 색상(hue)의 밝은 톤
    private var waveColor: Color {
        let a = spotify.accent.usingColorSpace(.sRGB) ?? spotify.accent  // 회색 기본값은 hue 못 읽어 크래시
        return Color(nsColor: NSColor(hue: a.hueComponent, saturation: min(0.7, a.saturationComponent + 0.2), brightness: 1, alpha: 1))
    }

    private var waveform: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<AudioTap.bandCount, id: \.self) { i in
                let v = spotify.playing ? CGFloat(audio.bands[i]) : 0
                Capsule().fill(waveColor).frame(width: 3, height: 3 + v * 21)
            }
        }
        .frame(height: 24)
        .animation(.easeOut(duration: 0.07), value: audio.bands)
    }
}

/// 6시에서 시작하는 부채꼴. progress 0→1로 한 바퀴
struct Sector: Shape {
    var progress: Double
    var dir: Double
    var animatableData: Double { get { progress } set { progress = newValue } }

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        p.move(to: c)
        // y축이 아래라 clockwise: false가 화면상 시계방향
        p.addArc(center: c, radius: max(rect.width, rect.height), startAngle: .degrees(90),
                 endAngle: .degrees(90 + dir * 360 * progress), clockwise: dir < 0)
        p.closeSubpath()
        return p
    }
}
