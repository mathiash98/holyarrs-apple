import Foundation

/// A short ask summary attached to cards and details (`ask` on metadata, explore and lookups).
nonisolated struct AskBrief: Codable, Hashable {
    var id: Int?
    var state: String?
    var state_label: String?
    var mine: Bool?
    var people: Int?
    var seasons: [Int]?
}

nonisolated struct Labelled: Codable, Hashable {
    var kind: String?
    var text: String?
    var name: String?
}

/// One movie or show card from Explore, Discover, New & Popular, lookups, person pages and "similar".
nonisolated struct MediaItem: Codable, Hashable, Identifiable {
    var tmdb_id: FlexID?
    var tmdb: FlexID?
    var ids: IDs?
    var kind: String?
    var name: String?
    var title: String?
    var year: Int?
    var poster: String?
    var backdrop: String?
    var overview: String?
    var in_library: Bool?
    var title_id: Int?
    var ask: AskBrief?
    var trailer_key: String?
    var card_art: String?
    var card_logo: String?
    var fresh: Labelled?
    var streaming: Labelled?
    var what: String?
    var characters: [String]?
    var roles: [String]?
    var score: Double?

    var tmdbID: String? { (tmdb_id ?? tmdb ?? ids?.tmdb)?.value }
    var displayName: String { name ?? title ?? "Untitled" }
    var id: String { "\(kind ?? "?"):\(tmdbID ?? "")\(title_id.map { ":\($0)" } ?? ""):\(displayName)" }

    func withKind(_ k: String) -> MediaItem {
        var c = self
        if c.kind == nil { c.kind = k }
        return c
    }

    /// Where a tap on this card goes.
    var route: Route? {
        if let t = tmdbID, let k = kind, k == "movie" || k == "show" { return .title(kind: k, tmdb: t) }
        if let id = title_id { return .libraryTitle(id) }
        return nil
    }

    /// A one-word status for badges.
    var badge: String? {
        if in_library == true || title_id != nil { return "In library" }
        if let a = ask?.state_label ?? ask?.state { return a }
        return nil
    }
}

nonisolated struct ExploreRow: Codable, Hashable, Identifiable {
    var id: String
    var type: String?
    var title: String?
    var subtitle: String?
    var items: [MediaItem]?
}

nonisolated struct ExploreHead: Codable {
    var building: Bool?
    var hero: [MediaItem]?
    var head: [ExploreRow]?
    var tail_rows: Int?
}

nonisolated struct ExploreTail: Codable {
    var page: Int?
    var more: Bool?
    var rows: [ExploreRow]?
}

nonisolated struct BrowseSection: Codable, Hashable, Identifiable {
    var id: String
    var title: String?
}

nonisolated struct BrowseTile: Codable, Hashable, Identifiable {
    var kind: String?
    var genre: Int?
    var genre_name: String?
    var mood: String?
    var name: String?
    var backdrop: String?
    var category: String?
    var section: String?
    var count: Int?
    var both: Bool?
    var id: String { "\(category ?? "")|\(kind ?? "")|\(genre ?? 0)|\(name ?? "")" }
}

nonisolated struct BrowseAnswer: Codable {
    var type: String?
    var sections: [BrowseSection]?
    var tiles: [BrowseTile]?
}

nonisolated struct BrowseSectionAnswer: Codable {
    var section: String?
    var tiles: [BrowseTile]?
}

nonisolated struct CategoryAnswer: Codable {
    var name: String?
    var items: [MediaItem]?
}

nonisolated struct GenreAnswer: Codable {
    nonisolated struct Genre: Codable { var id: Int?; var kind: String?; var name: String? }
    var genre: Genre?
    var hero: [MediaItem]?
    var rows: [ExploreRow]?
}

nonisolated struct NewAnswer: Codable {
    nonisolated struct RailDay: Codable, Hashable, Identifiable {
        var day: String
        var items: [MediaItem]?
        var id: String { day }
    }
    var hero: [MediaItem]?
    var rows: [ExploreRow]?
    var rail: [RailDay]?
    var more: Bool?
    var page: Int?
}

nonisolated struct DiscoverAnswer: Codable {
    var row: String?
    var title: String?
    var items: [MediaItem]?
}
