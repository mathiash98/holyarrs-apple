import AVFoundation
import SwiftUI
import UIKit

/// A muted, looping trailer behind a billboard (like Netflix previews). Starts after a short pause so scrolling
/// past does not start streams, stops when it leaves the screen, and only uses trailers HolyArrs already resolved.
struct TrailerPreview: View {
    @Environment(AppModel.self) private var app
    @AppStorage("autoplayPreviews") private var autoplay = true
    let kind: String?
    let tmdb: String?
    @Binding var muted: Bool
    @Binding var playing: Bool

    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?

    var body: some View {
        ZStack {
            if let player {
                PlayerLayerView(player: player)
                    .opacity(playing ? 1 : 0)
                    .animation(.easeIn(duration: 0.8), value: playing)
            }
        }
        .allowsHitTesting(false)
        .task(id: "\(kind ?? "")/\(tmdb ?? "")/\(autoplay)") { await start() }
        .onDisappear { stop() }
        .onChange(of: muted) { _, m in player?.isMuted = m }
    }

    private func start() async {
        stop()
        guard autoplay, let kind, let tmdb, kind == "movie" || kind == "show", let c = app.client else { return }
        try? await Task.sleep(for: .seconds(1.5))
        if Task.isCancelled { return }
        guard let t: TrailerStream = try? await c.get("/trailer/\(kind)/\(tmdb.q)"), let s = t.url, let url = URL(string: s) else { return }
        if Task.isCancelled { return }
        let item = AVPlayerItem(url: url)
        let q = AVQueuePlayer()
        q.isMuted = muted
        looper = AVPlayerLooper(player: q, templateItem: item)
        player = q
        q.play()
        // Wait for the first frames before fading in.
        for _ in 0 ..< 40 {
            if Task.isCancelled { return }
            if q.timeControlStatus == .playing && q.currentTime().seconds > 0.3 { playing = true; return }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    private func stop() {
        player?.pause()
        player?.removeAllItems()
        looper = nil
        player = nil
        playing = false
    }
}

/// An AVPlayerLayer filling its frame (aspect fill), with no controls.
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    final class LayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
    func makeUIView(context: Context) -> LayerView {
        let v = LayerView()
        v.playerLayer.videoGravity = .resizeAspectFill
        v.playerLayer.player = player
        v.isUserInteractionEnabled = false
        return v
    }
    func updateUIView(_ v: LayerView, context: Context) {
        if v.playerLayer.player !== player { v.playerLayer.player = player }
    }
}
