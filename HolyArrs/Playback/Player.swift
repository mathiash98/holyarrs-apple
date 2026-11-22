import AVKit
import SwiftUI
import UIKit

/// Presents AVPlayerViewController from UIKit: full-window on visionOS (with docking in environments) and the
/// standard player on tvOS. Jellyfin sessions report start, progress and stop so resume works across apps, and
/// episodes roll on to the next one when they end (Settings › Autoplay next episode).
enum Player {
    #if DEBUG
    /// Simulator screenshots: close the player after this many seconds.
    static var debugAutoClose: Double = 0
    #endif

    /// Plays a plain URL (trailers).
    static func play(url: URL, title: String, subtitle: String? = nil) {
        let item = AVPlayerItem(url: url)
        item.externalMetadata = metadata(title: title, subtitle: subtitle)
        let vc = PlayerViewController()
        vc.player = AVPlayer(playerItem: item)
        present(vc)
    }

    /// Plays a Jellyfin item, starting at `from` seconds.
    static func play(_ item: JFItem, client: JellyfinClient, from start: Double?) async throws {
        let (avItem, info) = try await makeItem(item, client: client)
        let player = AVPlayer(playerItem: avItem)
        if let start, start > 5 {
            await player.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: CMTime(seconds: 2, preferredTimescale: 600))
        }
        let vc = PlayerViewController()
        vc.player = player
        vc.client = client
        vc.attach(item: item, avItem: avItem, info: info)
        present(vc)
    }

    typealias StreamInfo = (url: URL, mediaSourceID: String, playSessionID: String, method: String)

    static func makeItem(_ item: JFItem, client: JellyfinClient) async throws -> (AVPlayerItem, StreamInfo) {
        let p = try await client.playbackURL(itemID: item.Id)
        let avItem = AVPlayerItem(url: p.url)
        avItem.externalMetadata = metadata(title: item.isEpisode ? (item.SeriesName ?? item.Name ?? "") : (item.Name ?? ""),
                                           subtitle: item.isEpisode ? item.displayTitle : item.ProductionYear.map(String.init))
        return (avItem, p)
    }

    static func metadata(title: String, subtitle: String?) -> [AVMetadataItem] {
        func m(_ id: AVMetadataIdentifier, _ v: String) -> AVMetadataItem {
            let i = AVMutableMetadataItem()
            i.identifier = id
            i.value = v as NSString
            i.extendedLanguageTag = "und"
            return i
        }
        var out = [m(.commonIdentifierTitle, title)]
        if let subtitle, !subtitle.isEmpty { out.append(m(.iTunesMetadataTrackSubTitle, subtitle)) }
        return out
    }

    private static func present(_ vc: PlayerViewController) {
        #if os(visionOS)
        vc.modalPresentationStyle = .fullScreen
        #endif
        guard let top = topViewController() else { return }
        top.present(vc, animated: true) {
            vc.player?.play()
            vc.session?.started()
            #if DEBUG
            if debugAutoClose > 0 {
                let secs = debugAutoClose
                debugAutoClose = 0
                DispatchQueue.main.asyncAfter(deadline: .now() + secs) { vc.dismiss(animated: true) }
            }
            #endif
        }
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var vc = scene?.keyWindow?.rootViewController ?? scene?.windows.first?.rootViewController
        while let p = vc?.presentedViewController { vc = p }
        return vc
    }
}

/// The player screen. Owns the Jellyfin session and moves on to the next episode when one ends.
final class PlayerViewController: AVPlayerViewController {
    var session: JellyfinPlayback?
    var client: JellyfinClient?
    private var current: JFItem?
    private var endObserver: NSObjectProtocol?

    func attach(item: JFItem, avItem: AVPlayerItem, info: Player.StreamInfo) {
        guard let client, let player else { return }
        current = item
        session = JellyfinPlayback(client: client, itemID: item.Id, mediaSourceID: info.mediaSourceID, playSessionID: info.playSessionID, method: info.method, player: player)
        if let o = endObserver { NotificationCenter.default.removeObserver(o) }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: avItem, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.playNext() }
        }
    }

    /// Autoplay: the episode ended, so start the next one in the same player.
    private func playNext() async {
        guard let client, let current, current.isEpisode,
              UserDefaults.standard.object(forKey: "autoplayNext") as? Bool ?? true,
              let next = await client.nextEpisode(after: current) else { return }
        session?.stop()
        session = nil
        do {
            let (avItem, info) = try await Player.makeItem(next, client: client)
            player?.replaceCurrentItem(with: avItem)
            attach(item: next, avItem: avItem, info: info)
            player?.play()
            session?.started()
        } catch {
            dismiss(animated: true)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || presentingViewController == nil {
            if let o = endObserver { NotificationCenter.default.removeObserver(o) }
            endObserver = nil
            // Report the stop (with the position) first, then detach the stream so AVPlayer cannot
            // ask for the HLS playlist again and restart a transcode after the session ended.
            session?.stop()
            session = nil
            player?.pause()
            player?.replaceCurrentItem(with: nil)
        }
    }
}

/// Reports a Jellyfin play session: start, progress every 10 seconds and on pause, and stop.
final class JellyfinPlayback {
    let client: JellyfinClient
    let itemID: String
    let mediaSourceID: String
    let playSessionID: String
    let method: String
    weak var player: AVPlayer?
    private var timer: Timer?
    private var rateObserver: NSKeyValueObservation?
    private var stopped = false

    init(client: JellyfinClient, itemID: String, mediaSourceID: String, playSessionID: String, method: String, player: AVPlayer) {
        self.client = client
        self.itemID = itemID
        self.mediaSourceID = mediaSourceID
        self.playSessionID = playSessionID
        self.method = method
        self.player = player
    }

    private func report() -> PlaybackReport {
        let secs = player?.currentTime().seconds ?? 0
        return PlaybackReport(ItemId: itemID, MediaSourceId: mediaSourceID, PlaySessionId: playSessionID,
                              PositionTicks: Int64((secs.isFinite ? secs : 0) * 10_000_000),
                              IsPaused: (player?.rate ?? 0) == 0, PlayMethod: method)
    }

    func started() {
        let r = report()
        let c = client
        Task { await c.reportStart(r) }
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.progress() }
        }
        rateObserver = player?.observe(\.rate, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.progress() }
        }
    }

    func progress() {
        guard !stopped else { return }
        let r = report()
        let c = client
        Task { await c.reportProgress(r) }
    }

    func stop() {
        guard !stopped else { return }
        let r = report()
        stopped = true
        timer?.invalidate()
        rateObserver = nil
        let c = client
        Task { await c.reportStopped(r) }
    }
}
