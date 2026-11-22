import Foundation

nonisolated struct Who: Codable, Hashable {
    var id: Int?
    var name: String?
}

/// One request ("ask") in Requests.
nonisolated struct Ask: Codable, Hashable, Identifiable {
    var id: Int
    var kind: String?
    var tmdb_id: FlexID?
    var ref: String?
    var name: String?
    var year: Int?
    var poster: String?
    var state: String?
    var state_label: String?
    var season_words: String?
    var seasons: [Int]?
    var future_only: Bool?
    var four_k: Bool?
    var quality: String?
    var asked_by: Who?
    var asked_at: String?
    var decided_by: Who?
    var decided_at: String?
    var people: [Who]?
    var note: String?
    var mine: Bool?
    var auto_approved: Bool?
    var title_id: Int?

    var route: Route? {
        if let t = tmdb_id?.value, !t.isEmpty, let k = kind, k == "movie" || k == "show" { return .title(kind: k, tmdb: t) }
        if let id = title_id { return .libraryTitle(id) }
        return nil
    }
}

nonisolated struct AsksAnswer: Codable {
    var asks: [Ask]?
    var counts: [String: Int]?
    var total: Int?
}

nonisolated struct AskAnswer: Codable {
    var ask: Ask?
    var already: Bool?
    var joined: Bool?
}

nonisolated struct AskBody: Encodable {
    var id: String
    var kind: String
    var seasons: [Int]?
    var future_only: Bool?
}

nonisolated struct TurnDownBody: Encodable { var note: String? }
nonisolated struct RemoveAsksBody: Encodable { var ids: [Int] }

/// A row on the Downloads screen (`/downloads/view`).
nonisolated struct DownloadRow: Codable, Hashable, Identifiable {
    var live_key: String?
    var downloadID: Int?
    var state: String?
    var label: String?
    var text: String?
    var progress: Double?
    var speed: Int64?
    var up_speed: Int64?
    var seeds: Int?
    var peers: Int?
    var active: Bool?
    var seeding: Bool?
    var phase: String?
    var name: String?
    var title: String?
    var year: Int?
    var kind: String?
    var version: String?
    var downloader: String?
    var protocolName: String?
    var size: Int64?
    var started_at: String?
    var finished_at: String?
    var can_act: Bool?
    var outside: Bool?
    var title_id: Int?
    var covers: String?
    var requested_by: String?
    var downloader_id: Int?
    var hash: String?

    enum CodingKeys: String, CodingKey {
        case downloader_id, hash, live_key, state, label, text, progress, speed, up_speed, seeds, peers, active, seeding, phase, name, title, year, kind, version, downloader, size, started_at, finished_at, can_act, outside, title_id, covers, requested_by
        case downloadID = "id"
        case protocolName = "protocol"
    }

    var id: String { live_key ?? "\(downloadID ?? 0)|\(name ?? "")" }

    /// Seconds left at the current speed.
    var eta: Double? {
        guard let p = progress, let s = speed, s > 0, let size, p < 1 else { return nil }
        return Double(size) * (1 - p) / Double(s)
    }

    var isDone: Bool { phase == "done" || (progress ?? 0) >= 1 }

    var displayTitle: String {
        if let t = title, !t.isEmpty { return year.map { "\(t) (\($0))" } ?? t }
        return name ?? "Download"
    }
}

nonisolated struct DownloadsAnswer: Codable {
    nonisolated struct Totals: Codable { var speed: Int64?; var up_speed: Int64? }
    nonisolated struct Client: Codable, Hashable, Identifiable { var id: Int; var name: String?; var health: String? }
    var downloads: [DownloadRow]?
    var totals: Totals?
    var clients: [Client]?
}

/// `/needs-decision`: things HolyArrs wants a person to decide.
nonisolated struct Decision: Codable, Hashable, Identifiable {
    var slot_id: Int
    var title_id: Int?
    var title: String?
    var year: Int?
    var version: String?
    var why: String?
    var reason: String?
    var release_name: String?
    var has_copy: Bool?
    var since: String?
    var kind: String?
    var artwork: String?
    var album: String?
    var id: Int { slot_id }
}

nonisolated struct DecisionsAnswer: Codable {
    var items: [Decision]?
    var count: Int?
}

nonisolated struct DecideBody: Encodable { var action: String }

/// `/downloads/matches`: downloads HolyArrs could not match to a title for sure.
nonisolated struct DownloadMatch: Codable, Hashable, Identifiable {
    nonisolated struct Candidate: Codable, Hashable, Identifiable {
        var id: String
        var kind: String?
        var name: String?
        var year: Int?
        var poster: String?
        var score: Double?
    }
    var id: Int
    var name: String?
    var state: String?
    var how: String?
    var candidates: [Candidate]?
    var matched_at: String?
}

nonisolated struct MatchesAnswer: Codable {
    var matches: [DownloadMatch]?
    var counts: [String: Int]?
    var pending: Int?
}

nonisolated struct PickBody: Encodable {
    var candidate: String?
    var not_media: Bool?
    var skip: Bool?
}

/// One History event (`/events`). The server writes these fields in PascalCase.
nonisolated struct HistoryEvent: Codable, Hashable, Identifiable {
    var id: Int
    var at: String?
    var kind: String?
    var summary: String?
    var titleID: Int?
    var actorName: String?

    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case at = "At"
        case kind = "Kind"
        case summary = "Summary"
        case titleID = "TitleID"
        case actorName = "actor_name"
    }
}

nonisolated struct EventsAnswer: Codable {
    var events: [HistoryEvent]?
    var total: Int?
    var offset: Int?
    var limit: Int?
}

/// A turned-down release (`/turned-down`).
nonisolated struct ReleaseRow: Codable, Hashable, Identifiable {
    var id: Int
    var name: String?
    var title_id: Int?
    var title_name: String?
    var episode: String?
    var version: String?
    var source_name: String?
    var size: Int64?
    var created_at: String?
    var turned_down_for: String?
    var protocolName: String?
    enum CodingKeys: String, CodingKey {
        case id, name, title_id, title_name, episode, version, source_name, size, created_at, turned_down_for
        case protocolName = "protocol"
    }
}

nonisolated struct ReleasePage: Codable {
    var releases: [ReleaseRow]?
    var total: Int?
}

/// `/calendar` dates.
nonisolated struct CalendarEntry: Codable, Hashable, Identifiable {
    var title_id: Int?
    var item_id: Int?
    var kind: String?
    var name: String?
    var year: Int?
    var date: String?
    var air_day: String?
    var timed: Bool?
    var season: Int?
    var episode: Int?
    var episode_name: String?
    var network: String?
    var poster: String?
    var backdrop: String?
    var banner: String?
    var still: String?
    var logo: String?
    var state: String?
    var runtime: Int?
    var tmdb: FlexID?
    var following: Bool?
    var album: String?

    var id: String { "\(kind ?? "")|\(title_id ?? 0)|\(item_id ?? 0)|\(date ?? "")|\(season ?? 0)x\(episode ?? 0)|\(album ?? "")" }
    var when: Date? { HADate.parse(date) ?? HADate.parse(air_day) }
    var dayKey: String {
        if let a = air_day, a.count == 10 { return a }
        if let d = when { return HADate.ymd(d) }
        return String((date ?? "").prefix(10))
    }

    var route: Route? {
        if let t = tmdb?.value, !t.isEmpty, let k = kind, k == "movie" || k == "show" { return .title(kind: k, tmdb: t) }
        if let id = title_id { return .libraryTitle(id) }
        return nil
    }
}

nonisolated struct CalendarAnswer: Codable {
    var dates: [CalendarEntry]?
    var from: String?
    var to: String?
}

nonisolated struct Message: Codable, Hashable, Identifiable {
    var id: Int
    var created_at: String?
    var kind: String?
    var text: String?
    var ask_id: Int?
    var title_id: Int?
    var read_at: String?
}

nonisolated struct MessagesAnswer: Codable {
    var messages: [Message]?
    var unread: Int?
    var waiting: Int?
}
