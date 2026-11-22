import Foundation

/// `/metadata/{kind}/{tmdb}`: the details page data from TMDB, plus HolyArrs' own library and ask state.
nonisolated struct TitleMeta: Codable {
    nonisolated struct Person: Codable, Hashable, Identifiable {
        var name: String?
        var role: String?
        var character: String?
        var profile: String?
        var id: FlexID?
        var job: String?
        var identity: String { "\(id?.value ?? "")|\(name ?? "")|\(character ?? job ?? "")" }
        var id_: String { identity }
    }
    nonisolated struct Season: Codable, Hashable, Identifiable {
        var number: Int
        var episode_count: Int?
        var year: Int?
        var name: String?
        var id: Int { number }
    }
    nonisolated struct Video: Codable, Hashable {
        var key: String?
        var name: String?
        var type: String?
        var site: String?
        var official: Bool?
    }
    nonisolated struct Collection: Codable, Hashable {
        var id: FlexID?
        var name: String?
        var parts: [MediaItem]?
    }

    var tmdb_id: FlexID?
    var kind: String?
    var name: String?
    var year: Int?
    var poster: String?
    var backdrop: String?
    var logo: String?
    var overview: String?
    var tagline: String?
    var genres: NameList?
    var runtime_minutes: Int?
    var episode_runtime: Int?
    var rating: String?
    var score: Double?
    var votes: Int?
    var status: String?
    var network: String?
    var studios: NameList?
    var people: [Person]?
    var seasons: [Season]?
    var videos: [Video]?
    var similar: [MediaItem]?
    var collection: Collection?
    var in_library: Bool?
    var title_id: Int?
    var ask: AskBrief?
    var never_add: Bool?

    /// The best trailer: an official "Trailer" first, then any trailer, then a teaser.
    var trailerKey: String? {
        let v = videos ?? []
        let yt = v.filter { ($0.site ?? "YouTube").lowercased() == "youtube" && ($0.key?.isEmpty == false) }
        return (yt.first { $0.type == "Trailer" && $0.official == true }
            ?? yt.first { $0.type == "Trailer" }
            ?? yt.first { $0.type == "Teaser" }
            ?? yt.first)?.key
    }
}

nonisolated struct SeasonEpisodes: Codable {
    nonisolated struct Episode: Codable, Hashable, Identifiable {
        var number: Int
        var name: String?
        var overview: String?
        var runtime: Int?
        var still: String?
        var air_day: String?
        var id: Int { number }
    }
    var season: Int?
    var episodes: [Episode]?
}

/// `/titles/{id}` and `/search` results: a title in the HolyArrs library.
nonisolated struct LibraryTitle: Codable, Identifiable, Hashable {
    nonisolated struct Slot: Codable, Hashable {
        nonisolated struct File: Codable, Hashable {
            nonisolated struct Q: Codable, Hashable { var resolution: Int?; var source: String?; var codec: String?; var hdr: [String]? }
            var Quality: Q?
        }
        var id: Int?
        var version: String?
        var state: String?
        var state_label: String?
        var reason: String?
        var file: File?
    }
    nonisolated struct ShowInfo: Codable, Hashable {
        nonisolated struct Season: Codable, Hashable, Identifiable {
            var number: Int
            var name: String?
            var keep_up_to_date: Bool?
            var episodes: Int?
            var aired: Int?
            var in_library: Int?
            var missing: Int?
            var downloading: Int?
            var not_out_yet: Int?
            var failed: Int?
            var id: Int { number }
        }
        var status: String?
        var network: String?
        var seasons: [Season]?
        var episodes: Int?
        var missing: Int?
        var in_library: Int?
        var downloading: Int?
    }

    var id: Int
    var kind: String?
    var name: String?
    var year: Int?
    var overview: String?
    var ids: IDs?
    var backdrop: String?
    var logo: String?
    var artwork: [String]?
    var genres: NameList?
    var runtime_minutes: Int?
    var rating: String?
    var score: Double?
    var stage: String?
    var size_bytes: Int64?
    var added_at: String?
    var slots: [Slot]?
    var asks: [Ask]?
    var show: ShowInfo?

    var poster: String? { artwork?.first }

    /// The best file's quality, such as "4K · HDR10 · HEVC" (movies).
    var fileQuality: (label: String, detail: String)? {
        let qs = (slots ?? []).compactMap { $0.file?.Quality }.filter { ($0.resolution ?? 0) > 0 }
        guard let q = qs.max(by: { ($0.resolution ?? 0) < ($1.resolution ?? 0) }), let r = q.resolution else { return nil }
        var d: [String] = []
        if let h = q.hdr, !h.isEmpty { d.append(h.map { $0.uppercased() }.joined(separator: "/")) }
        if let c = q.codec { d.append(c == "h265" ? "HEVC" : c == "h264" ? "H.264" : c.uppercased()) }
        if let s = q.source { d.append(s.replacingOccurrences(of: "_", with: "-").uppercased()) }
        return (Quality.label(height: r), d.joined(separator: " · "))
    }

    /// A plain status line for the title page.
    var statusSummary: String {
        if kind == "show", let s = show {
            var parts: [String] = []
            if let i = s.in_library, let e = s.episodes { parts.append("\(i) of \(e) episodes in library") }
            if let d = s.downloading, d > 0 { parts.append("\(d) downloading") }
            if let m = s.missing, m > 0 { parts.append("\(m) missing") }
            return parts.isEmpty ? "In library" : parts.joined(separator: " · ")
        }
        let states = (slots ?? []).compactMap { $0.state_label ?? $0.state }
        return states.first ?? "In library"
    }

    var isDownloading: Bool {
        if (show?.downloading ?? 0) > 0 { return true }
        return (slots ?? []).contains { ($0.state ?? "").contains("download") }
    }

    var hasFiles: Bool {
        if kind == "show" { return (show?.in_library ?? 0) > 0 }
        return (slots ?? []).contains { $0.state == "in_library" }
    }
}

nonisolated struct LibrarySearchAnswer: Codable {
    var titles: [LibraryTitle]?
}

nonisolated struct MovieLookup: Codable { var movies: [MediaItem]? }
nonisolated struct ShowLookup: Codable { var shows: [MediaItem]? }

nonisolated struct WatchLinks: Codable {
    nonisolated struct Link: Codable, Hashable { var server: String?; var kind: String?; var url: String? }
    var links: [Link]?
}

nonisolated struct MediaAccounts: Codable {
    nonisolated struct Server: Codable {
        nonisolated struct Account: Codable { var id: String?; var name: String?; var taken_by: Int? }
        var id: Int?
        var name: String?
        var kind: String?
        var accounts: [Account]?
    }
    var servers: [Server]?
}

/// `/trailer/{kind}/{tmdb}`: a trailer stream HolyArrs already resolved (YouTube HLS or MP4).
nonisolated struct TrailerStream: Codable {
    var type: String?
    var url: String?
    var proxy_url: String?
    var key: String?
}
