import Foundation

/// A Jellyfin item (movie, series or episode) with the fields playback and browsing need.
nonisolated struct JFItem: Codable, Hashable, Identifiable {
    nonisolated struct JFUserData: Codable, Hashable {
        var PlaybackPositionTicks: Int64?
        var Played: Bool?
        var PlayedPercentage: Double?
    }
    var Id: String
    var Name: String?
    var `Type`: String?
    var SeriesName: String?
    var SeriesId: String?
    var SeasonId: String?
    var ParentIndexNumber: Int?
    var IndexNumber: Int?
    var ProductionYear: Int?
    var RunTimeTicks: Int64?
    var Overview: String?
    var UserData: JFUserData?
    var ProviderIds: [String: String]?
    var ImageTags: [String: String]?
    var BackdropImageTags: [String]?
    var ParentBackdropItemId: String?
    var ParentThumbItemId: String?
    var ParentLogoItemId: String?
    var SeriesPrimaryImageTag: String?
    var Width: Int?
    var Height: Int?

    var id: String { Id }
    var isEpisode: Bool { Type == "Episode" }

    /// Where to resume, in seconds; nil when there is nothing to resume.
    var resumeSeconds: Double? {
        guard let t = UserData?.PlaybackPositionTicks, t > 0, UserData?.Played != true else { return nil }
        return Double(t) / 10_000_000
    }

    var progress: Double? {
        guard let p = resumeSeconds, let r = RunTimeTicks, r > 0 else { return nil }
        return min(1, p / (Double(r) / 10_000_000))
    }

    var displayTitle: String {
        if isEpisode, let s = ParentIndexNumber, let e = IndexNumber { return "S\(s)E\(e) · \(Name ?? "")" }
        return Name ?? ""
    }
}

nonisolated struct JFItemsAnswer: Codable { var Items: [JFItem]?; var TotalRecordCount: Int? }

/// The parts of PlaybackInfo the player uses.
nonisolated struct JFPlaybackInfo: Codable {
    nonisolated struct Source: Codable {
        var Id: String?
        var Container: String?
        var SupportsDirectPlay: Bool?
        var SupportsDirectStream: Bool?
        var TranscodingUrl: String?
        var ETag: String?
    }
    var MediaSources: [Source]?
    var PlaySessionId: String?
}

/// A small Jellyfin REST client on the token from "Sign in with Jellyfin" (or Settings › Connect Jellyfin).
final class JellyfinClient {
    let login: JellyfinLogin
    let base: URL
    private let session: URLSession
    private var index: [String: String]?

    init?(login: JellyfinLogin) {
        guard let u = URL(string: login.server.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) else { return nil }
        self.login = login
        self.base = u
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 30
        session = URLSession(configuration: c)
    }

    private func request(_ method: String, _ path: String, body: Data? = nil) async throws -> Data {
        guard let url = URL(string: base.absoluteString + path) else { throw APIError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(JellyfinAuth.authHeader(token: login.accessToken), forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.transport("No answer from Jellyfin.") }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw APIError.http(status: http.statusCode, message: http.statusCode == 401 ? "Jellyfin no longer accepts the saved sign-in. Connect Jellyfin again in Settings." : "Jellyfin answered \(http.statusCode).")
        }
        return data
    }

    func get<T: Decodable>(_ path: String) async throws -> T {
        try JSONDecoder().decode(T.self, from: try await request("GET", path))
    }

    func post<B: Encodable>(_ path: String, _ body: B) async throws {
        _ = try await request("POST", path, body: try JSONEncoder().encode(body))
    }

    // MARK: Browsing

    /// Maps TMDB (and TVDB) ids to Jellyfin item ids. Jellyfin 12 ignores AnyProviderIdEquals, so one list is read and cached.
    func itemID(kind: String, tmdb: String?, tvdb: String? = nil) async -> String? {
        if index == nil {
            let a: JFItemsAnswer? = try? await get("/Users/\(login.userID)/Items?Recursive=true&IncludeItemTypes=Movie,Series&Fields=ProviderIds&EnableImages=false&EnableUserData=false")
            var m: [String: String] = [:]
            for it in a?.Items ?? [] {
                let k = it.Type == "Series" ? "show" : "movie"
                if let t = it.ProviderIds?["Tmdb"] { m["\(k):tmdb:\(t)"] = it.Id }
                if let t = it.ProviderIds?["Tvdb"] { m["\(k):tvdb:\(t)"] = it.Id }
            }
            index = m
        }
        if let tmdb, let id = index?["\(kind):tmdb:\(tmdb)"] { return id }
        if let tvdb, let id = index?["\(kind):tvdb:\(tvdb)"] { return id }
        return nil
    }

    /// Quality labels ("4K", "FHD", "HD", "SD") keyed "movie:<tmdb>" and "show:<tmdb>"; a show takes its best episode.
    /// Also returns Jellyfin item ids keyed the same way (for posters).
    func qualityIndex() async -> (quality: [String: String], ids: [String: String]) {
        guard let a: JFItemsAnswer = try? await get("/Users/\(login.userID)/Items?Recursive=true&IncludeItemTypes=Movie,Series,Episode&Fields=ProviderIds,Width,Height&EnableImages=false&EnableUserData=false") else { return ([:], [:]) }
        var seriesTMDB: [String: String] = [:]
        var best: [String: Int] = [:]
        var ids: [String: String] = [:]
        for it in a.Items ?? [] where it.Type == "Series" || it.Type == "Movie" {
            guard let t = it.ProviderIds?["Tmdb"] else { continue }
            if it.Type == "Series" { seriesTMDB[it.Id] = t }
            ids["\(it.Type == "Series" ? "show" : "movie"):\(t)"] = it.Id
        }
        for it in a.Items ?? [] {
            guard let w = it.Width, w > 0 else { continue }
            let key: String?
            switch it.Type {
            case "Movie": key = it.ProviderIds?["Tmdb"].map { "movie:\($0)" }
            case "Episode": key = it.SeriesId.flatMap { seriesTMDB[$0] }.map { "show:\($0)" }
            default: key = nil
            }
            if let key { best[key] = max(best[key] ?? 0, w) }
        }
        return (best.mapValues(Quality.label(width:)), ids)
    }

    /// The title's logo (the series' for an episode), only when Jellyfin has one.
    func logoImage(_ it: JFItem) -> String? {
        if !it.isEpisode, let t = it.ImageTags?["Logo"] { return base.absoluteString + "/Items/\(it.Id)/Images/Logo?maxWidth=500&tag=\(t)" }
        if let p = it.ParentLogoItemId { return base.absoluteString + "/Items/\(p)/Images/Logo?maxWidth=500" }
        return nil
    }

    func posterURL(itemID: String, width: Int = 500) -> String {
        base.absoluteString + "/Items/\(itemID)/Images/Primary?maxWidth=\(width)"
    }

    /// The episode after this one (next in the series' order), for autoplay.
    func nextEpisode(after ep: JFItem) async -> JFItem? {
        guard let series = ep.SeriesId else { return nil }
        let a: JFItemsAnswer? = try? await get("/Shows/\(series)/Episodes?UserId=\(login.userID)&StartItemId=\(ep.Id)&Limit=2")
        return a?.Items?.dropFirst().first
    }

    func item(_ id: String) async throws -> JFItem {
        try await get("/Users/\(login.userID)/Items/\(id)")
    }

    func episodes(series: String) async throws -> [JFItem] {
        let a: JFItemsAnswer = try await get("/Shows/\(series)/Episodes?UserId=\(login.userID)&Fields=Overview")
        return a.Items ?? []
    }

    func nextUp(series: String? = nil, limit: Int = 20) async throws -> [JFItem] {
        var p = "/Shows/NextUp?UserId=\(login.userID)&Limit=\(limit)&Fields=Overview"
        if let series { p += "&SeriesId=\(series)" }
        let a: JFItemsAnswer = try await get(p)
        return a.Items ?? []
    }

    func resume(limit: Int = 20) async throws -> [JFItem] {
        let a: JFItemsAnswer = try await get("/Users/\(login.userID)/Items/Resume?Limit=\(limit)&MediaTypes=Video&Fields=Overview")
        return a.Items ?? []
    }

    /// A landscape picture for an item: its own thumb/backdrop, or the series' for an episode.
    func wideImage(_ it: JFItem) -> String {
        if it.isEpisode, let p = it.ImageTags?["Primary"] { return base.absoluteString + "/Items/\(it.Id)/Images/Primary?maxWidth=800&tag=\(p)" }
        if !(it.BackdropImageTags ?? []).isEmpty { return base.absoluteString + "/Items/\(it.Id)/Images/Backdrop?maxWidth=800" }
        if let b = it.ParentBackdropItemId { return base.absoluteString + "/Items/\(b)/Images/Backdrop?maxWidth=800" }
        return base.absoluteString + "/Items/\(it.Id)/Images/Primary?maxWidth=800"
    }

    // MARK: Playback

    /// Asks Jellyfin how to play an item on AVPlayer and returns a URL AVPlayer can open.
    func playbackURL(itemID: String) async throws -> (url: URL, mediaSourceID: String, playSessionID: String, method: String) {
        let body = PlaybackInfoBody(UserId: login.userID, DeviceProfile: .avPlayer)
        let data = try await request("POST", "/Items/\(itemID)/PlaybackInfo?UserId=\(login.userID)", body: try JSONEncoder().encode(body))
        let info = try JSONDecoder().decode(JFPlaybackInfo.self, from: data)
        guard let src = info.MediaSources?.first, let srcID = src.Id else { throw APIError.transport("Jellyfin has no playable file for this item.") }
        let session = info.PlaySessionId ?? UUID().uuidString
        if src.SupportsDirectPlay == true,
           let u = URL(string: base.absoluteString + "/Videos/\(itemID)/stream?static=true&MediaSourceId=\(srcID)&PlaySessionId=\(session)&api_key=\(login.accessToken)") {
            return (u, srcID, session, "DirectPlay")
        }
        if let t = src.TranscodingUrl, let u = URL(string: base.absoluteString + t) {
            return (u, srcID, session, t.contains("static=true") ? "DirectStream" : "Transcode")
        }
        throw APIError.transport("Jellyfin could not offer a stream Apple's player can play.")
    }

    func reportStart(_ r: PlaybackReport) async { try? await post("/Sessions/Playing", r) }
    func reportProgress(_ r: PlaybackReport) async { try? await post("/Sessions/Playing/Progress", r) }
    func reportStopped(_ r: PlaybackReport) async {
        try? await post("/Sessions/Playing/Stopped", r)
        // Ends the transcode on the server right away, and once more shortly after: AVPlayer can still have a
        // playlist request in flight while the player closes, which would start a new transcode for the session.
        let path = "/Videos/ActiveEncodings?DeviceId=\(JellyfinAuth.deviceID)&PlaySessionId=\(r.PlaySessionId)"
        _ = try? await request("DELETE", path)
        try? await Task.sleep(for: .seconds(4))
        _ = try? await request("DELETE", path)
    }
}

nonisolated struct PlaybackReport: Encodable {
    var ItemId: String
    var MediaSourceId: String
    var PlaySessionId: String
    var PositionTicks: Int64
    var IsPaused: Bool
    var PlayMethod: String
    var CanSeek = true
}

nonisolated struct PlaybackInfoBody: Encodable {
    var UserId: String
    var MaxStreamingBitrate = 120_000_000
    var AutoOpenLiveStream = false
    var EnableDirectPlay = true
    var EnableDirectStream = true
    var EnableTranscoding = true
    var AllowVideoStreamCopy = true
    var AllowAudioStreamCopy = true
    var DeviceProfile: DeviceProfile
}

/// What AVPlayer plays: MP4/MOV with H.264/HEVC directly, everything else as fMP4 HLS (video copied when it can be),
/// text subtitles as WebVTT HLS renditions, picture subtitles burned in.
nonisolated struct DeviceProfile: Encodable {
    struct DirectPlay: Encodable { var Container: String; var `Type`: String; var VideoCodec: String; var AudioCodec: String }
    struct Transcoding: Encodable {
        var Container: String; var `Type`: String; var `Protocol`: String; var Context: String
        var VideoCodec: String; var AudioCodec: String; var MaxAudioChannels: String; var MinSegments: Int; var BreakOnNonKeyFrames: Bool
    }
    struct Subtitle: Encodable { var Format: String; var Method: String }

    var Name = "HolyArrs AVPlayer"
    var MaxStreamingBitrate = 120_000_000
    var MaxStaticBitrate = 120_000_000
    var DirectPlayProfiles: [DirectPlay]
    var TranscodingProfiles: [Transcoding]
    var SubtitleProfiles: [Subtitle]
    var CodecProfiles: [String] = []
    var ContainerProfiles: [String] = []

    static let avPlayer = DeviceProfile(
        DirectPlayProfiles: [DirectPlay(Container: "mp4,m4v,mov", Type: "Video", VideoCodec: "h264,hevc", AudioCodec: "aac,ac3,eac3,alac,flac,mp3")],
        TranscodingProfiles: [Transcoding(Container: "mp4", Type: "Video", Protocol: "hls", Context: "Streaming", VideoCodec: "hevc,h264", AudioCodec: "aac,ac3,eac3", MaxAudioChannels: "6", MinSegments: 2, BreakOnNonKeyFrames: true)],
        SubtitleProfiles: ["vtt", "srt", "subrip", "ass", "ssa", "mov_text"].map { Subtitle(Format: $0, Method: "Hls") }
            + ["pgssub", "dvdsub", "dvbsub"].map { Subtitle(Format: $0, Method: "Encode") }
    )
}

enum Quality {
    /// By width, so letterboxed or cropped files still count as their class.
    nonisolated static func label(width w: Int) -> String {
        w >= 3200 ? "4K" : w >= 1800 ? "FHD" : w >= 1200 ? "HD" : "SD"
    }
    nonisolated static func label(height h: Int) -> String {
        h >= 1600 ? "4K" : h >= 900 ? "FHD" : h >= 700 ? "HD" : "SD"
    }
}
