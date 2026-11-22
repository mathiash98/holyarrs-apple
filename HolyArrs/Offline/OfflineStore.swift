#if !os(tvOS)
import AVFoundation
import Foundation
import Observation
import UIKit

/// What is downloaded to this device, and the background downloads that fetch it.
///
/// Downloads are HLS streams from Jellyfin saved with `AVAssetDownloadURLSession` as .movpkg packages (with their
/// subtitle renditions), in a background session that keeps going while the app is closed. They run one at a time
/// so the server runs a single transcode, and every finished, failed, paused or removed download ends its transcode.
/// The catalogue (names, numbers, overview, artwork, watch positions) is JSON in Application Support, so the
/// Offline page works with no server at all.
@Observable
final class OfflineStore {
    static let shared = OfflineStore()

    private(set) var items: [OfflineItem] = []
    private(set) var shows: [String: OfflineShow] = [:]
    private(set) var freeSpace: Int64?

    @ObservationIgnored weak var app: AppModel?
    @ObservationIgnored private var session: AVAssetDownloadURLSession?
    @ObservationIgnored private let delegate = OfflineSessionDelegate()
    @ObservationIgnored private var tasks: [String: AVAssetDownloadTask] = [:]
    /// The item whose PlaybackInfo is being asked for (counts as the running download).
    @ObservationIgnored private var preparing: String?
    /// Packages of downloads removed while their task was still running; deleted when the task ends.
    @ObservationIgnored private var orphans: [Int: URL] = [:]
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var activated = false
    @ObservationIgnored private var demo = false
    /// Set when Jellyfin could not be reached to start a download; the queue waits until the app is online again.
    @ObservationIgnored private var holdUntilOnline = false
    /// The system's background-events handler is given back once the next download has been started.
    @ObservationIgnored private var backgroundEventsPending = false
    @ObservationIgnored private var savedClient: JellyfinClient?

    /// The app's Jellyfin client, or one from the saved login when the system woke the app in the background.
    private var client: JellyfinClient? {
        if let c = app?.jellyfinClient { return c }
        if savedClient == nil, let login = JellyfinStore.load() { savedClient = JellyfinClient(login: login) }
        return savedClient
    }

    private init() {}

    // MARK: Lifecycle

    /// Loads the catalogue and reconnects to the background session. Safe to call more than once.
    func activate() {
        guard !activated else { return }
        activated = true
        OfflinePaths.prepare()
        load()
        #if DEBUG
        if ProcessInfo.processInfo.environment["HOLYARRS_OFFLINE_DEMO"] == "1" {
            seedDemo()
            return
        }
        #endif
        let config = URLSessionConfiguration.background(withIdentifier: (Bundle.main.bundleIdentifier ?? "holyarrs") + ".offline")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        session = AVAssetDownloadURLSession(configuration: config, assetDownloadDelegate: delegate, delegateQueue: .main)
        refreshFreeSpace()
        Task { await reattach() }
    }

    /// After a relaunch: picks up the tasks the system kept, and restarts the ones it lost.
    private func reattach() async {
        guard let session else { return }
        for t in await session.allTasks {
            guard let t = t as? AVAssetDownloadTask, t.state != .completed else { continue }
            guard let i = match(t.taskDescription), items[i].state != .done else {
                t.cancel()
                continue
            }
            tasks[items[i].id] = t
            items[i].state = t.state == .suspended ? .paused : .downloading
        }
        for i in items.indices where items[i].state == .downloading && tasks[items[i].id] == nil {
            // No task: it either finished while the app was not running (its event may still arrive and is matched
            // by the attempt id), or the system dropped it (the app was closed from the app switcher).
            if let loc = items[i].location, AVURLAsset(url: OfflinePaths.resolve(loc)).assetCache?.isPlayableOffline == true {
                items[i].state = .done
                items[i].progress = 1
                items[i].finishedAt = items[i].finishedAt ?? .now
                measure(items[i].id, OfflinePaths.resolve(loc))
            } else {
                // Kept, not deleted: Resume starts it over.
                items[i].state = .paused
            }
        }
        save()
        startNext()
        startTicker()
    }

    /// The app reached HolyArrs: sends watch positions made offline to Jellyfin, reads newer ones, and resumes the queue.
    func cameOnline() async {
        activate()
        holdUntilOnline = false
        await syncPending()
        await refreshFromServer()
        startNext()
    }

    // MARK: Lookup

    func item(_ id: String) -> OfflineItem? { items.first { $0.id == id } }
    private func index(_ id: String) -> Int? { items.firstIndex { $0.id == id } }

    /// The record a task belongs to, from its "<id>|<attempt>" description.
    private func match(_ description: String?) -> Int? {
        guard let parts = description?.split(separator: "|", maxSplits: 1).map(String.init), parts.count == 2 else { return nil }
        return items.firstIndex { $0.id == parts[0] && $0.attempt == parts[1] }
    }

    /// The playable package of a finished download.
    func localURL(_ id: String) -> URL? {
        guard let it = item(id), it.state == .done, let loc = it.location else { return nil }
        let url = OfflinePaths.resolve(loc)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var usedBytes: Int64 { items.reduce(0) { $0 + ($1.bytes ?? 0) } }

    func refreshFreeSpace() { freeSpace = OfflinePaths.freeSpace }

    /// The next downloaded episode of the same show, for autoplay.
    func nextEpisode(after rec: OfflineItem) -> OfflineItem? {
        guard rec.isEpisode, let sid = rec.seriesID else { return nil }
        let key = { (r: OfflineItem) in (r.season ?? 0) * 10_000 + (r.episode ?? 0) }
        return items.filter { $0.seriesID == sid && $0.state == .done && key($0) > key(rec) }.min { key($0) < key($1) }
    }

    // MARK: Downloading

    /// Adds movies or episodes to the queue (already known ones are skipped) and saves their artwork.
    func download(_ list: [JFItem], series: JFItem? = nil, client: JellyfinClient, quality: OfflineQuality = .preferred) async {
        activate()
        let fresh = list.filter { index($0.Id) == nil }
        guard !fresh.isEmpty else { return }
        for it in fresh {
            var rec = OfflineItem(id: it.Id, isEpisode: it.isEpisode, name: it.Name ?? "", overview: it.Overview,
                                  year: it.ProductionYear, runtimeTicks: it.RunTimeTicks, seriesID: it.SeriesId,
                                  seriesName: it.SeriesName, season: it.ParentIndexNumber, episode: it.IndexNumber,
                                  userID: client.login.userID, server: client.base.absoluteString, quality: quality,
                                  state: .queued, addedAt: .now)
            rec.position = it.resumeSeconds ?? 0
            rec.played = it.UserData?.Played == true
            items.append(rec)
        }
        save()
        await saveArtwork(for: fresh, series: series, client: client)
        startNext()
    }

    func pause(_ id: String) {
        guard let i = index(id) else { return }
        switch items[i].state {
        case .downloading:
            tasks[id]?.suspend()
            items[i].state = .paused
            stopTranscode(items[i].playSessionID)
        case .queued:
            items[i].state = .paused
        default:
            return
        }
        save()
        startNext()
    }

    /// Resumes a paused download, or starts a failed one again. It waits its turn behind a running download.
    func resume(_ id: String) {
        guard let i = index(id) else { return }
        switch items[i].state {
        case .paused:
            items[i].state = .queued
            items[i].error = nil
        case .failed:
            removePackage(of: items[i])
            items[i].location = nil
            items[i].progress = 0
            items[i].bytes = nil
            items[i].error = nil
            items[i].state = .queued
        default:
            return
        }
        holdUntilOnline = false
        save()
        startNext()
    }

    /// Starts the first queued download when nothing else is running.
    func startNext() {
        defer { finishBackgroundEventsIfIdle() }
        guard !demo, !holdUntilOnline, session != nil, preparing == nil, !items.contains(where: { $0.state == .downloading }) else { return }
        guard let next = items.first(where: { $0.state == .queued }) else { return }
        if let t = tasks[next.id] {
            update(next.id) { $0.state = .downloading }
            t.resume()
            save()
            startTicker()
            return
        }
        guard let client, client.login.userID == next.userID else { return }
        // A paused download whose task was lost (relaunch) starts over: drop what it had saved.
        removePackage(of: next)
        update(next.id) {
            $0.location = nil
            $0.progress = 0
            $0.bytes = nil
        }
        preparing = next.id
        startTicker()
        Task { await begin(next, client: client) }
    }

    private func begin(_ rec: OfflineItem, client: JellyfinClient) async {
        // Enough time to start it when the system woke the app for the previous download's completion.
        let bg = UIApplication.shared.beginBackgroundTask(withName: "Start offline download", expirationHandler: nil)
        defer {
            preparing = nil
            startNext()
            UIApplication.shared.endBackgroundTask(bg)
        }
        do {
            let stream = try await OfflineStream.request(itemID: rec.id, quality: rec.quality, client: client)
            guard let session, let i = index(rec.id), items[i].state == .queued else {
                // Paused or removed while Jellyfin answered.
                await OfflineStream.stop(client, playSessionID: stream.playSessionID)
                return
            }
            let asset = AVURLAsset(url: stream.url)
            let config = AVAssetDownloadConfiguration(asset: asset, title: rec.isEpisode ? "\(rec.seriesName ?? "") \(rec.title)" : rec.name)
            // Every rendition (the text subtitles come as WebVTT renditions), not only the default one.
            if let all = try? await asset.load(.allMediaSelections), !all.isEmpty {
                config.primaryContentConfiguration.mediaSelections = all
            }
            if let art = rec.poster ?? rec.thumb {
                config.artworkData = try? Data(contentsOf: OfflinePaths.artwork.appendingPathComponent(art))
            }
            guard let j = index(rec.id), items[j].state == .queued else {
                await OfflineStream.stop(client, playSessionID: stream.playSessionID)
                return
            }
            let task = session.makeAssetDownloadTask(downloadConfiguration: config)
            let attempt = UUID().uuidString
            task.taskDescription = "\(rec.id)|\(attempt)"
            tasks[rec.id] = task
            items[j].attempt = attempt
            items[j].state = .downloading
            items[j].error = nil
            items[j].progress = 0
            items[j].mediaSourceID = stream.mediaSourceID
            items[j].playSessionID = stream.playSessionID
            task.resume()
            save()
        } catch let e as URLError {
            // Jellyfin is out of reach: keep it queued and wait for the app to be online again.
            holdUntilOnline = true
            update(rec.id) { $0.error = "Waiting for Jellyfin (\(e.localizedDescription))" }
            save()
        } catch {
            update(rec.id) {
                $0.state = .failed
                $0.error = error.localizedDescription
            }
            save()
        }
    }

    /// The system finished delivering background session events.
    func backgroundEventsFinished() {
        backgroundEventsPending = true
        finishBackgroundEventsIfIdle()
    }

    private func finishBackgroundEventsIfIdle() {
        guard backgroundEventsPending, preparing == nil else { return }
        backgroundEventsPending = false
        OfflineAppDelegate.finishBackgroundEvents()
    }

    // MARK: Session events (from OfflineSessionDelegate, on the main queue)

    func willDownload(description: String?, task: Int, to location: URL) {
        guard let i = match(description) else {
            orphans[task] = location
            return
        }
        items[i].location = OfflinePaths.relative(location)
        save()
    }

    func didComplete(description: String?, task: Int, failure: OfflineFailure?) {
        if let orphan = orphans.removeValue(forKey: task) {
            try? FileManager.default.removeItem(at: orphan)
        }
        guard let i = match(description) else {
            startNext()
            return
        }
        let id = items[i].id
        if tasks[id]?.taskIdentifier == task { tasks[id] = nil }
        let sessionID = items[i].playSessionID
        let url = items[i].location.map(OfflinePaths.resolve)
        if failure == nil, let url {
            items[i].state = .done
            items[i].progress = 1
            items[i].finishedAt = .now
            items[i].error = nil
            measure(id, url)
        } else {
            removePackage(of: items[i])
            items[i].location = nil
            items[i].progress = 0
            items[i].bytes = nil
            items[i].state = .failed
            items[i].error = failure.map { $0.cancelled ? "The download was stopped. Try again to start it over." : $0.message }
                ?? "The download did not finish."
        }
        save()
        stopTranscode(sessionID)
        refreshFreeSpace()
        startNext()
    }

    // MARK: Removing

    func remove(_ ids: [String]) {
        for id in ids {
            guard let i = index(id) else { continue }
            let rec = items.remove(at: i)
            if id == preparing { continue }
            if let t = tasks.removeValue(forKey: id) {
                if let loc = rec.location { orphans[t.taskIdentifier] = OfflinePaths.resolve(loc) }
                t.cancel()
                stopTranscode(rec.playSessionID)
            } else {
                removePackage(of: rec)
            }
        }
        pruneArtwork()
        save()
        refreshFreeSpace()
        startNext()
    }

    func removeSeason(series: String, season: Int?) {
        remove(items.filter { $0.seriesID == series && $0.season == season }.map(\.id))
    }

    func removeShow(_ series: String) { remove(items.filter { $0.seriesID == series }.map(\.id)) }

    var watchedIDs: [String] { items.filter { $0.played && $0.state == .done }.map(\.id) }

    func removeWatched() { remove(watchedIDs) }

    func removeAll() { remove(items.map(\.id)) }

    private func removePackage(of rec: OfflineItem) {
        guard let loc = rec.location else { return }
        try? FileManager.default.removeItem(at: OfflinePaths.resolve(loc))
    }

    // MARK: Watch positions

    /// Saves a position from the offline player. It reaches Jellyfin on the next sync.
    func record(_ id: String, position: Double, ended: Bool) {
        guard let i = index(id) else { return }
        if ended {
            items[i].played = true
            items[i].position = 0
        } else {
            guard abs(items[i].position - position) >= 1 else { return }
            items[i].position = position
            // Like Jellyfin: past 90% counts as watched.
            if let r = items[i].runtimeSeconds, r > 0, position / r > 0.9 {
                items[i].played = true
                items[i].position = 0
            }
        }
        items[i].needsSync = true
        items[i].positionUpdatedAt = .now
        save()
    }

    /// Takes the server's position for a download that has nothing waiting to be sent.
    func adopt(serverItem it: JFItem) {
        guard let i = index(it.Id), !items[i].needsSync else { return }
        items[i].position = it.resumeSeconds ?? 0
        items[i].played = it.UserData?.Played == true
        save()
    }

    /// Sends positions changed offline as a stopped play session (Jellyfin then sets the resume point, or marks
    /// the item watched when the position is past 90%).
    func syncPending() async {
        guard let app, !app.readOnly, app.phase == .signedIn, let client = app.jellyfinClient else { return }
        for rec in items where rec.needsSync && rec.userID == client.login.userID {
            let ticks: Int64 = rec.played ? (rec.runtimeTicks ?? Int64(rec.position * 10_000_000)) : Int64(rec.position * 10_000_000)
            let report = PlaybackReport(ItemId: rec.id, MediaSourceId: rec.mediaSourceID ?? rec.id,
                                        PlaySessionId: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
                                        PositionTicks: ticks, IsPaused: true, PlayMethod: "DirectPlay")
            do {
                try await client.post("/Sessions/Playing/Stopped", report)
            } catch {
                return
            }
            if let i = index(rec.id), items[i].positionUpdatedAt == rec.positionUpdatedAt { items[i].needsSync = false }
        }
        save()
    }

    /// Reads watch state from Jellyfin for downloads with nothing waiting to be sent (read only).
    func refreshFromServer() async {
        guard let app, app.phase == .signedIn, let client = app.jellyfinClient else { return }
        let ids = items.filter { !$0.needsSync && $0.userID == client.login.userID }.map(\.id)
        for chunk in stride(from: 0, to: ids.count, by: 80).map({ Array(ids[$0 ..< min($0 + 80, ids.count)]) }) {
            guard let a: JFItemsAnswer = try? await client.get("/Users/\(client.login.userID)/Items?Ids=\(chunk.joined(separator: ","))&EnableImages=false") else { return }
            for it in a.Items ?? [] {
                guard let i = index(it.Id), !items[i].needsSync else { continue }
                items[i].position = it.resumeSeconds ?? 0
                items[i].played = it.UserData?.Played == true
            }
        }
        save()
    }

    // MARK: Progress

    private func startTicker() {
        guard ticker == nil, !demo else { return }
        ticker = Task { [weak self] in
            var n = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                n += 1
                if !self.tick(measuring: n % 5 == 0, persist: n % 20 == 0) {
                    self.ticker = nil
                    self.save()
                    return
                }
            }
        }
    }

    /// Reads task progress; returns false when nothing is running.
    private func tick(measuring: Bool, persist: Bool) -> Bool {
        var running = preparing != nil
        for (id, t) in tasks {
            guard let i = index(id), items[i].state == .downloading else { continue }
            running = true
            let f = t.progress.fractionCompleted
            if f.isFinite, f > items[i].progress { items[i].progress = min(f, 0.999) }
            if measuring, let loc = items[i].location { measure(id, OfflinePaths.resolve(loc)) }
        }
        if measuring { refreshFreeSpace() }
        if persist { save() }
        return running
    }

    private func measure(_ id: String, _ url: URL) {
        Task {
            let bytes = await Task.detached(priority: .utility) { OfflinePaths.size(of: url) }.value
            update(id) { $0.bytes = bytes }
        }
    }

    private func stopTranscode(_ playSessionID: String?) {
        guard let s = playSessionID, let c = client else { return }
        Task { await OfflineStream.stop(c, playSessionID: s) }
    }

    private func update(_ id: String, _ change: (inout OfflineItem) -> Void) {
        guard let i = index(id) else { return }
        change(&items[i])
    }

    // MARK: Artwork

    private func saveArtwork(for list: [JFItem], series: JFItem?, client: JellyfinClient) async {
        let base = client.base.absoluteString
        for it in list {
            if it.isEpisode, let sid = it.SeriesId {
                if shows[sid] == nil {
                    let s: JFItem? = series?.Id == sid ? series : try? await client.item(sid)
                    let poster = await fetch(client.posterURL(itemID: sid), "\(sid)-poster.jpg", client)
                    let backdrop = await fetch(base + "/Items/\(sid)/Images/Backdrop?maxWidth=1280", "\(sid)-backdrop.jpg", client)
                    shows[sid] = OfflineShow(id: sid, name: s?.Name ?? it.SeriesName ?? "", overview: s?.Overview,
                                             year: s?.ProductionYear, poster: poster, backdrop: backdrop)
                }
                let thumb = await fetch(client.wideImage(it), "\(it.Id)-wide.jpg", client)
                update(it.Id) {
                    $0.thumb = thumb
                    $0.poster = self.shows[sid]?.poster
                }
            } else {
                let poster = await fetch(client.posterURL(itemID: it.Id), "\(it.Id)-poster.jpg", client)
                let thumb = await fetch(client.wideImage(it), "\(it.Id)-wide.jpg", client)
                update(it.Id) {
                    $0.poster = poster
                    $0.thumb = thumb
                }
            }
        }
        save()
    }

    /// Saves one picture into the artwork folder and returns its file name (nil when Jellyfin has none).
    private func fetch(_ path: String, _ file: String, _ client: JellyfinClient) async -> String? {
        let dest = OfflinePaths.artwork.appendingPathComponent(file)
        if FileManager.default.fileExists(atPath: dest.path) { return file }
        guard let url = URL(string: path) else { return nil }
        var req = URLRequest(url: url)
        req.setValue(JellyfinAuth.authHeader(token: client.login.accessToken), forHTTPHeaderField: "Authorization")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { return nil }
        do {
            try data.write(to: dest, options: .atomic)
            return file
        } catch {
            return nil
        }
    }

    private func pruneArtwork() {
        let seriesLeft = Set(items.compactMap(\.seriesID))
        shows = shows.filter { seriesLeft.contains($0.key) }
        var keep = Set(items.flatMap { [$0.poster, $0.thumb].compactMap { $0 } })
        for s in shows.values { keep.formUnion([s.poster, s.backdrop].compactMap { $0 }) }
        let fm = FileManager.default
        for f in (try? fm.contentsOfDirectory(atPath: OfflinePaths.artwork.path)) ?? [] where !keep.contains(f) {
            try? fm.removeItem(at: OfflinePaths.artwork.appendingPathComponent(f))
        }
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: OfflinePaths.catalogue),
              let c = try? JSONDecoder().decode(OfflineCatalogue.self, from: data) else { return }
        items = c.items
        shows = c.shows
    }

    private func save() {
        guard !demo else { return }
        let c = OfflineCatalogue(items: items, shows: shows)
        guard let data = try? JSONEncoder().encode(c) else { return }
        try? data.write(to: OfflinePaths.catalogue, options: .atomic)
    }

    #if DEBUG
    /// Simulator screenshots (HOLYARRS_OFFLINE_DEMO=1): sample entries in memory only, never saved, no files.
    private func seedDemo() {
        demo = true
        func rec(_ id: String, _ name: String, ep: (String, Int, Int)? = nil, state: OfflineItem.State, progress: Double = 1, gb: Double, pos: Double = 0, played: Bool = false) -> OfflineItem {
            var r = OfflineItem(id: id, isEpisode: ep != nil, name: name, overview: nil, year: ep == nil ? 2019 : nil,
                                runtimeTicks: 6_000 * 10_000_000, seriesID: ep.map { "s-" + $0.0 }, seriesName: ep?.0,
                                season: ep?.1, episode: ep?.2, userID: "demo", server: "", quality: .high, state: state,
                                addedAt: .now)
            r.progress = progress
            r.bytes = Int64(gb * 1_000_000_000)
            r.position = pos
            r.played = played
            return r
        }
        items = [
            rec("m1", "Sample Movie", state: .done, gb: 4.2, pos: 1800),
            rec("m2", "Another Movie", state: .done, gb: 3.1, played: true),
            rec("e1", "Pilot", ep: ("Sample Show", 1, 1), state: .done, gb: 1.4, played: true),
            rec("e2", "The Second One", ep: ("Sample Show", 1, 2), state: .done, gb: 1.5, pos: 600),
            rec("e3", "Third Time", ep: ("Sample Show", 1, 3), state: .downloading, progress: 0.42, gb: 0.6),
            rec("e4", "Fourth", ep: ("Sample Show", 1, 4), state: .queued, progress: 0, gb: 0),
        ]
        shows = ["s-Sample Show": OfflineShow(id: "s-Sample Show", name: "Sample Show", overview: nil, year: 2021)]
        refreshFreeSpace()
    }
    #endif
}

/// Why a download task ended early.
nonisolated struct OfflineFailure: Sendable {
    var cancelled: Bool
    var message: String
}
#endif
