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
            if box == nil { await measureBars(shared) }
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
        TrailerPlayers.shared.adopt(key, player: q, looper: looper, url: url)
        TrailerPlayers.shared.hold()
        holding = true
        player = q
        q.play()
        // Wait for the first frames before fading in.
        for _ in 0 ..< 40 {
            if Task.isCancelled { return }
            if q.timeControlStatus == .playing && q.currentTime().seconds > 0.3 { playing = true; break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        await measureBars(q)
    }

    /// Reads frames as they play (the trailers are HLS streams, which cannot be opened a second time for
    /// stills) and zooms past the black bars once a few frames agree. Part of this view's task.
    private func measureBars(_ q: AVQueuePlayer) async {
        guard let item = q.currentItem else { return }
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        item.add(output)
        defer { item.remove(output) }
        var bars: [CGFloat] = []
        for _ in 0 ..< 12 {
            try? await Task.sleep(for: .seconds(1.5))
            if Task.isCancelled { return }
            let t = output.itemTime(forHostTime: CACurrentMediaTime())
            guard let buf = output.copyPixelBuffer(forItemTime: t, itemTimeForDisplay: nil),
                  let b = Letterbox.barFraction(buf) else { continue }
            bars.append(b)
            // The second largest reading: a full-frame shot or logo reads 0, one dark scene cannot inflate it.
            if bars.count >= 3 {
                let sorted = bars.sorted()
                let found = Letterbox(size: item.presentationSize, bar: sorted[sorted.count - 2])
                if found != box {
                    withAnimation(.easeInOut(duration: 0.4)) { box = found }
                    TrailerPlayers.shared.setLetterbox(found, for: key)
                }
            }
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
    private(set) var url: URL?

    func adopt(_ key: String, player: AVQueuePlayer, looper: AVPlayerLooper, url: URL) {
        if let old = current, old !== player {
            old.pause()
            old.removeAllItems()
        }
        self.key = key
        current = player
        self.looper = looper
        self.url = url
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

    /// The share of rows at the top and bottom that are (nearly) black in one BGRA frame; the smaller side
    /// counts. Nil when the whole frame is dark (a fade), which says nothing about bars.
    static func barFraction(_ buf: CVPixelBuffer) -> CGFloat? {
        CVPixelBufferLockBaseAddress(buf, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buf, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buf) else { return nil }
        let w = CVPixelBufferGetWidth(buf), h = CVPixelBufferGetHeight(buf), stride = CVPixelBufferGetBytesPerRow(buf)
        guard w > 0, h > 0 else { return nil }
        let px = base.assumingMemoryBound(to: UInt8.self)
        func dark(_ row: Int) -> Bool {
            var sum = 0, peak = 0, n = 0
            var x = 0
            while x < w {
                let p = row * stride + x * 4
                let y = (Int(px[p + 2]) * 3 + Int(px[p + 1]) * 6 + Int(px[p])) / 10
                sum += y; peak = max(peak, y); n += 1
                x += 8
            }
            // Video black is often 16 (limited range) plus compression noise.
            return sum / max(n, 1) < 30 && peak < 60
        }
        var top = 0
        while top < h / 3, dark(top) { top += 1 }
        var bottom = 0
        while bottom < h / 3, dark(h - 1 - bottom) { bottom += 1 }
        if top >= h / 3 && bottom >= h / 3 { return nil }
        return CGFloat(min(top, bottom)) / CGFloat(h)
    }
}
