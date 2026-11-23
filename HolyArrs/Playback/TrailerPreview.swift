import AVFoundation
import SwiftUI
import UIKit

/// A looping trailer preview behind a billboard. Starts after a short pause so scrolling
/// past does not start streams, stops when it leaves the screen, and only uses trailers HolyArrs already resolved.
struct TrailerPreview: View {
    @Environment(AppModel.self) private var app
    @AppStorage("autoplayPreviews") private var autoplay = true
    let kind: String?
    let tmdb: String?
    @Binding var muted: Bool
    @Binding var playing: Bool

    @State private var player: AVQueuePlayer?
    /// True while this view counts as a user of the shared player.
    @State private var holding = false

    private var key: String { "\(kind ?? "")/\(tmdb ?? "")" }

    var body: some View {
        ZStack {
            if let player {
                PlayerLayerView(player: player)
                    .opacity(playing ? 1 : 0)
                    .animation(.easeIn(duration: 0.8), value: playing)
            }
        }
        .allowsHitTesting(false)
        .task(id: "\(key)/\(autoplay)") { await start() }
        .onDisappear { stop() }
        .onChange(of: muted) { _, m in player?.isMuted = m }
    }

    private func start() async {
        stop()
        guard autoplay, let kind, let tmdb, kind == "movie" || kind == "show", let c = app.client else { return }
        // The same title is already playing (for example Home's billboard before "More info"): carry on from
        // where it is, with its sound setting, instead of starting the trailer again.
        if let shared = TrailerPlayers.shared.player(for: key) {
            TrailerPlayers.shared.hold()
            holding = true
            muted = shared.isMuted
            player = shared
            shared.play()
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { playing = true }
            return
        }
        try? await Task.sleep(for: .seconds(1.5))
        if Task.isCancelled { return }
        guard let t: TrailerStream = try? await c.get("/trailer/\(kind)/\(tmdb.q)"), let s = t.url, let url = URL(string: s) else { return }
        if Task.isCancelled { return }
        let item = AVPlayerItem(url: url)
        let q = AVQueuePlayer()
        q.isMuted = muted
        let looper = AVPlayerLooper(player: q, templateItem: item)
        TrailerPlayers.shared.adopt(key, player: q, looper: looper)
        TrailerPlayers.shared.hold()
        holding = true
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
        if holding { TrailerPlayers.shared.release() }
        holding = false
        player = nil
        playing = false
    }
}

/// The one trailer preview player, shared by every billboard showing the same title, so moving from a
/// billboard to the title's page keeps the trailer going. It pauses shortly after the last billboard leaves.
@MainActor
final class TrailerPlayers {
    static let shared = TrailerPlayers()
    private var key: String?
    private var current: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var holders = 0
    private var pauseTask: Task<Void, Never>?

    func player(for key: String) -> AVQueuePlayer? { self.key == key ? current : nil }

    /// Takes over a new trailer; the previous one is stopped for good.
    func adopt(_ key: String, player: AVQueuePlayer, looper: AVPlayerLooper) {
        if let old = current, old !== player {
            old.pause()
            old.removeAllItems()
        }
        self.key = key
        current = player
        self.looper = looper
        holders = 0
    }

    func hold() {
        holders += 1
        pauseTask?.cancel()
    }

    func release() {
        holders = max(0, holders - 1)
        guard holders == 0 else { return }
        pauseTask?.cancel()
        // A short grace period: the next page may pick the same trailer up (it loads its details first).
        pauseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, !Task.isCancelled, self.holders == 0 else { return }
            self.current?.pause()
        }
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
