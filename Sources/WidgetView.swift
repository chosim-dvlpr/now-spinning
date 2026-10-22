import SwiftUI

struct WidgetView: View {
    @ObservedObject var spotify: SpotifyPoller
    @ObservedObject var audio: AudioTap
    @State private var angle = 0.0
    private let spin = Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .bottom) {
            cd.padding(.top, 10).padding(.bottom, 36)
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
        .onReceive(spin) { _ in if spotify.playing { angle += 1.2 } }
        .onTapGesture { spotify.activatePlayer() }
    }

    private var cd: some View {
        ZStack {
            Group {
                if let img = spotify.artwork { Image(nsImage: img).resizable().scaledToFill() }
                else { Circle().fill(Color(white: 0.2)) }
            }
            .frame(width: 150, height: 150).clipShape(Circle())
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
