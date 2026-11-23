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
    /// Black bars baked into the trailer file (many are 2.39:1 films inside a 16:9 video).
    @State private var box: Letterbox?

    private var key: String { "\(kind ?? "")/\(tmdb ?? "")" }

    var body: some View {
        ZStack {
            if let player {
                GeometryReader { g in
                    PlayerLayerView(player: player)
                        // Zoom just enough that the baked-in black bars fall outside the frame.
                        .scaleEffect(box?.cropScale(frame: g.size) ?? 1)
                }
                .clipped()
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
            box = TrailerPlayers.shared.letterbox
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
        let k = key
        Task {
            let found = await Letterbox.measure(url: url)
            TrailerPlayers.shared.setLetterbox(found, for: k)
            if player === q { box = found }
        }
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
        box = nil
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
    private(set) var letterbox: Letterbox?

    func setLetterbox(_ l: Letterbox?, for key: String) { if self.key == key { letterbox = l } }

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
        letterbox = nil
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

/// The black bars at the top and bottom of a trailer file, measured on a few frames.
nonisolated struct Letterbox: Sendable, Equatable {
    /// The video's size and the bar height as a fraction of it (each side).
    var size: CGSize
    var bar: CGFloat

    /// How much to zoom an aspect-fill video in `frame` so the picture (without bars) fills it.
    func cropScale(frame: CGSize) -> CGFloat {
        guard bar > 0.02, size.width > 0, size.height > 0, frame.width > 0, frame.height > 0 else { return 1 }
        let fill = max(frame.width / size.width, frame.height / size.height)
        let picture = size.height * (1 - 2 * bar) * fill
        return min(max(1, frame.height / picture), 1.6)
    }

    static func measure(url: URL) async -> Letterbox? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let natural = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform) else { return nil }
        let r = CGRect(origin: .zero, size: natural).applying(transform)
        let size = CGSize(width: abs(r.width), height: abs(r.height))
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 192, height: 192)
        var bars: [CGFloat] = []
        // Several frames, so one dark scene does not look like a bar; the smallest bar wins.
        for t in [6.0, 14.0, 24.0] {
            if let (img, _) = try? await gen.image(at: CMTime(seconds: t, preferredTimescale: 600)) {
                bars.append(barFraction(img))
            }
        }
        guard let bar = bars.min() else { return nil }
        return Letterbox(size: size, bar: bar)
    }

    /// The share of rows at the top and bottom that are (nearly) black; the smaller side counts.
    private static func barFraction(_ img: CGImage) -> CGFloat {
        let w = img.width, h = img.height
        guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                                 space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let data = { ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h)); return ctx.data }() else { return 0 }
        let px = data.bindMemory(to: UInt8.self, capacity: w * h)
        func dark(_ row: Int) -> Bool {
            var sum = 0, peak = 0
            for x in 0 ..< w { let v = Int(px[row * w + x]); sum += v; peak = max(peak, v) }
            return sum / w < 18 && peak < 48
        }
        var top = 0
        while top < h / 3, dark(top) { top += 1 }
        var bottom = 0
        while bottom < h / 3, dark(h - 1 - bottom) { bottom += 1 }
        return CGFloat(min(top, bottom)) / CGFloat(h)
    }
}
