import Foundation

/// How big a download is. Jellyfin enforces the cap when it builds the HLS stream; "Original" copies the
/// file's own video when Apple's player can play it, so it is about the size of the file on the server.
nonisolated enum OfflineQuality: String, Codable, CaseIterable, Identifiable, Sendable {
    case original, high, medium

    var id: String { rawValue }

    var label: String {
        switch self {
        case .original: "Original"
        case .high: "High (1080p)"
        case .medium: "Medium (720p)"
        }
    }

    var detail: String {
        switch self {
        case .original: "The file's own quality when it can be kept. Largest."
        case .high: "1080p at up to 10 Mbit/s, about 4.5 GB an hour."
        case .medium: "720p at up to 4 Mbit/s, about 1.8 GB an hour."
        }
    }

    /// Bits per second, passed to Jellyfin as MaxStreamingBitrate.
    var maxBitrate: Int {
        switch self {
        case .original: 120_000_000
        case .high: 10_000_000
        case .medium: 4_000_000
        }
    }

    var maxSize: (width: Int, height: Int)? {
        switch self {
        case .original: nil
        case .high: (1920, 1080)
        case .medium: (1280, 720)
        }
    }

    /// A size estimate for `seconds` of video, or nil when it depends on the source file.
    func estimate(seconds: Double?) -> Int64? {
        guard self != .original, let seconds, seconds > 0 else { return nil }
        return Int64(Double(maxBitrate) * seconds / 8)
    }

    static let storageKey = "offlineQuality"
    static var preferred: OfflineQuality {
        UserDefaults.standard.string(forKey: storageKey).flatMap(OfflineQuality.init(rawValue:)) ?? .high
    }
}

/// One downloaded (or downloading) movie or episode, with everything needed to show and play it without a server.
nonisolated struct OfflineItem: Codable, Identifiable, Hashable, Sendable {
    enum State: String, Codable, Sendable {
        /// Waiting for its turn (downloads run one at a time, so the server runs one transcode).
        case queued
        case downloading
        case paused
        case done
        case failed
    }

    /// The Jellyfin item id.
    var id: String
    var isEpisode: Bool
    var name: String
    var overview: String?
    var year: Int?
    var runtimeTicks: Int64?
    var seriesID: String?
    var seriesName: String?
    var season: Int?
    var episode: Int?

    /// The Jellyfin user and server it was downloaded for (watch positions are only sent back to them).
    var userID: String
    var server: String

    var quality: OfflineQuality
    var state: State
    var progress: Double = 0
    var bytes: Int64?
    var error: String?
    /// The .movpkg, relative to the home directory (the absolute path changes between launches).
    var location: String?
    var mediaSourceID: String?
    var playSessionID: String?
    var addedAt: Date
    var finishedAt: Date?

    /// Local watch state. `needsSync` is set when it changed here and has not reached Jellyfin yet.
    var position: Double = 0
    var played = false
    var needsSync = false
    var positionUpdatedAt: Date?

    /// Artwork file names in the offline artwork folder.
    var poster: String?
    var thumb: String?

    var runtimeSeconds: Double? { runtimeTicks.map { Double($0) / 10_000_000 } }

    var title: String {
        if isEpisode, let s = season, let e = episode { return "S\(s)E\(e) · \(name)" }
        return name
    }

    var isActive: Bool { state == .queued || state == .downloading || state == .paused }

    /// Watched share for the progress bar (nil when nothing to show).
    var watched: Double? {
        guard !played, position > 0, let r = runtimeSeconds, r > 0 else { return nil }
        return min(1, position / r)
    }

    var resumeSeconds: Double? { !played && position > 5 ? position : nil }
}

/// A show's own metadata, shared by its downloaded episodes.
nonisolated struct OfflineShow: Codable, Hashable, Sendable {
    var id: String
    var name: String
    var overview: String?
    var year: Int?
    var poster: String?
    var backdrop: String?
}

nonisolated struct OfflineCatalogue: Codable, Sendable {
    var version = 1
    var items: [OfflineItem] = []
    var shows: [String: OfflineShow] = [:]
}

/// Where offline data lives: Application Support/Offline (catalogue and artwork; excluded from backups).
/// The videos themselves are .movpkg packages that AVFoundation places and manages.
nonisolated enum OfflinePaths {
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Offline", isDirectory: true)
    }

    static var catalogue: URL { root.appendingPathComponent("catalogue.json") }
    static var artwork: URL { root.appendingPathComponent("Artwork", isDirectory: true) }

    static func prepare() {
        let fm = FileManager.default
        try? fm.createDirectory(at: artwork, withIntermediateDirectories: true)
        var r = root
        var v = URLResourceValues()
        v.isExcludedFromBackup = true
        try? r.setResourceValues(v)
    }

    static var home: URL { URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true) }

    /// Stores a package location relative to the home directory when it is inside it.
    static func relative(_ url: URL) -> String {
        let home = self.home.standardizedFileURL.resolvingSymlinksInPath().path
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        if path.hasPrefix(home + "/") { return String(path.dropFirst(home.count + 1)) }
        return path
    }

    static func resolve(_ stored: String) -> URL {
        stored.hasPrefix("/") ? URL(fileURLWithPath: stored) : home.appendingPathComponent(stored)
    }

    /// Bytes on disk for a file or package.
    static func size(of url: URL) -> Int64 {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        guard let e = fm.enumerator(at: url, includingPropertiesForKeys: keys) else {
            return Int64((try? url.resourceValues(forKeys: Set(keys)))?.totalFileAllocatedSize ?? 0)
        }
        var total: Int64 = 0
        for case let f as URL in e {
            guard let v = try? f.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return total
    }

    static var freeSpace: Int64? {
        #if os(tvOS)
        return nil
        #else
        let v = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return v?.volumeAvailableCapacityForImportantUsage
        #endif
    }
}
