#if !os(tvOS)
import AVKit
import UIKit

/// Plays downloaded packages. The position is saved on the device every 10 seconds and when the player closes,
/// then sent to Jellyfin when HolyArrs is reachable.
enum OfflinePlayback {
    /// Plays the downloaded copy of a Jellyfin item when there is one (saves the network and works on a bad
    /// connection). `item` is fresh from the server, so its resume point is used unless one made offline is waiting.
    static func playIfDownloaded(_ item: JFItem, resume: Bool) async -> Bool {
        let store = OfflineStore.shared
        guard var rec = store.item(item.Id), store.localURL(item.Id) != nil else { return false }
        store.adopt(serverItem: item)
        rec = store.item(item.Id) ?? rec
        return play(rec, from: resume ? rec.resumeSeconds : nil) == nil
    }

    /// Starts a download in the player. Returns an error message when it cannot.
    @discardableResult
    static func play(_ rec: OfflineItem, from start: Double?) -> String? {
        guard let url = OfflineStore.shared.localURL(rec.id) else { return "This download is not on the device any more." }
        let vc = OfflinePlayerViewController()
        vc.load(rec, url: url, from: start)
        #if os(visionOS)
        vc.modalPresentationStyle = .fullScreen
        #endif
        guard topViewController() != nil else { return "Could not open the player." }
        Task {
            await Player.prepare?()
            topViewController()?.present(vc, animated: true) { vc.player?.play() }
        }
        return nil
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var vc = scene?.keyWindow?.rootViewController ?? scene?.windows.first?.rootViewController
        while let p = vc?.presentedViewController { vc = p }
        return vc
    }
}

final class OfflinePlayerViewController: AVPlayerViewController {
    private var current: OfflineItem?
    private var timer: Timer?
    private var endObserver: NSObjectProtocol?

    func load(_ rec: OfflineItem, url: URL, from start: Double?) {
        let item = AVPlayerItem(asset: AVURLAsset(url: url))
        item.externalMetadata = Player.metadata(title: rec.isEpisode ? (rec.seriesName ?? rec.name) : rec.name,
                                                subtitle: rec.isEpisode ? rec.title : rec.year.map(String.init))
        if let player {
            player.replaceCurrentItem(with: item)
        } else {
            player = AVPlayer(playerItem: item)
        }
        if let start, start > 5 {
            player?.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: CMTime(seconds: 2, preferredTimescale: 600))
        }
        current = rec
        if let o = endObserver { NotificationCenter.default.removeObserver(o) }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.ended() }
        }
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.savePosition() }
            }
        }
    }

    private func savePosition() {
        guard let current, let secs = player?.currentTime().seconds, secs.isFinite, secs > 0 else { return }
        OfflineStore.shared.record(current.id, position: secs, ended: false)
    }

    /// Marks the item watched and rolls on to the next downloaded episode (Settings › Autoplay next episode).
    private func ended() {
        guard let rec = current else { return }
        OfflineStore.shared.record(rec.id, position: 0, ended: true)
        current = nil
        if UserDefaults.standard.object(forKey: "autoplayNext") as? Bool ?? true,
           let next = OfflineStore.shared.nextEpisode(after: rec),
           let url = OfflineStore.shared.localURL(next.id) {
            load(next, url: url, from: next.resumeSeconds)
            player?.play()
        } else {
            dismiss(animated: true)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || presentingViewController == nil else { return }
        savePosition()
        current = nil
        timer?.invalidate()
        timer = nil
        if let o = endObserver { NotificationCenter.default.removeObserver(o) }
        endObserver = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        Task { await Player.cleanup?() }
        Task { await OfflineStore.shared.syncPending() }
    }
}
#endif

/// The calls the rest of the app makes into offline mode. They do nothing on tvOS.
enum OfflineHooks {
    /// Connects the store to the app model (for the Jellyfin client and sign-in state).
    static func attach(_ app: AppModel) {
        #if !os(tvOS)
        OfflineStore.shared.app = app
        OfflineStore.shared.activate()
        #endif
    }

    /// HolyArrs answered: sync watch positions and resume queued downloads.
    static func cameOnline() {
        #if !os(tvOS)
        Task { await OfflineStore.shared.cameOnline() }
        #endif
    }

    /// Plays the downloaded copy when there is one; false means stream it as usual.
    static func playIfDownloaded(_ item: JFItem, resume: Bool) async -> Bool {
        #if os(tvOS)
        false
        #else
        await OfflinePlayback.playIfDownloaded(item, resume: resume)
        #endif
    }
}
