import AVFoundation
import SwiftUI
import UIKit

/// A trailer preview behind a billboard. Starts after a short pause so scrolling past does not start streams,
/// plays each trailer once (then fades back to the picture; it does not start again this session), pauses while
/// `paused` is set, and only uses trailers HolyArrs already resolved.
struct TrailerPreview: View {
    @Environment(AppModel.self) private var app
    @AppStorage("autoplayPreviews") private var autoplay = true
    let kind: String?
    let tmdb: String?
    @Binding var muted: Bool
    @Binding var playing: Bool
    /// Set while the billboard is scrolled away (the page moved on to other rows).
    var paused = false

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
                .animation(.easeInOut(duration: 0.8), value: playing)
            }
        }
        .allowsHitTesting(false)
        .task(id: "\(key)/\(autoplay)") { await start() }
        .onDisappear { stop() }
        .onChange(of: muted) { _, m in player?.isMuted = m }
        .onChange(of: paused) { _, p in
            guard let player, !TrailerPlayers.shared.hasPlayed(key) else { return }
            if p { player.pause() } else { player.play() }
        }
    }

    private func start() async {
        stop()
        guard autoplay, let kind, let tmdb, kind == "movie" || kind == "show", let c = app.client else { return }
        // Each trailer plays once per session; afterwards the picture stays.
        guard !TrailerPlayers.shared.hasPlayed(key) else { return }
        // The same title is already playing (for example Home's billboard before opening the title): carry on
        // from where it is, with its sound setting, instead of starting the trailer again.
        if let shared = TrailerPlayers.shared.player(for: key) {
            TrailerPlayers.shared.hold()
            holding = true
            muted = shared.isMuted
            box = TrailerPlayers.shared.letterbox
            player = shared
            if !paused { shared.play() }
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { playing = true }
            await follow(shared, measure: box == nil)
            return
        }
        try? await Task.sleep(for: .seconds(1.5))
        if Task.isCancelled { return }
        guard let t: TrailerStream = try? await c.get("/trailer/\(kind)/\(tmdb.q)"), let s = t.url, let url = URL(string: s) else { return }
        if Task.isCancelled { return }
        let q = AVQueuePlayer(items: [AVPlayerItem(url: url)])
        q.isMuted = muted
        q.actionAtItemEnd = .pause
        TrailerPlayers.shared.adopt(key, player: q)
        TrailerPlayers.shared.hold()
        holding = true
        player = q
        if !paused { q.play() }
        // Wait for the first frames before fading in.
        for _ in 0 ..< 40 {
            if Task.isCancelled { return }
            if q.timeControlStatus == .playing && q.currentTime().seconds > 0.3 { playing = true; break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        await follow(q, measure: true)
    }

    /// Measures the black bars and waits for the end; then fades back to the picture and marks it played.
    private func follow(_ q: AVQueuePlayer, measure: Bool) async {
        guard let item = q.currentItem else { return }
        await withTaskGroup(of: Bool.self) { g in
            if measure { g.addTask { await measureBars(q); return false } }
            g.addTask {
                for await _ in NotificationCenter.default.notifications(named: AVPlayerItem.didPlayToEndTimeNotification, object: item) { break }
                return true
            }
            // The end of the trailer is what counts; measuring stops with it.
            while let ended = await g.next() {
                if ended { g.cancelAll(); break }
            }
        }
        if Task.isCancelled { return }
        TrailerPlayers.shared.markPlayed(key)
        playing = false
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
    private var holders = 0
    private var pauseTask: Task<Void, Never>?
    private(set) var letterbox: Letterbox?
    /// Trailers that played to the end this session (they are not started again).
    private var played: Set<String> = []

    func setLetterbox(_ l: Letterbox?, for key: String) { if self.key == key { letterbox = l } }
    func hasPlayed(_ key: String) -> Bool { played.contains(key) }
    func markPlayed(_ key: String) {
        played.insert(key)
        if self.key == key { current?.pause() }
    }
    /// A trailer is on screen and still running (the slider waits for it before moving on).
    func isRunning(_ key: String) -> Bool {
        self.key == key && !played.contains(key) && holders > 0 && current?.timeControlStatus != .paused
    }

    func player(for key: String) -> AVQueuePlayer? { self.key == key ? current : nil }

    /// Takes over a new trailer; the previous one is stopped for good.
    func adopt(_ key: String, player: AVQueuePlayer) {
        if let old = current, old !== player {
            old.pause()
            old.removeAllItems()
        }
        self.key = key
        current = player
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
