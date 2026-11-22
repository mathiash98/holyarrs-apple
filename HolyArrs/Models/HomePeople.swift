import Foundation

nonisolated struct HomeCard: Codable, Hashable, Identifiable {
    var key: String?
    var kind: String?
    var title_id: Int?
    var name: String?
    var year: Int?
    var line: String?
    var backdrop: String?
    var poster: String?
    var logo: String?
    var at: String?
    var id: String { key ?? "\(kind ?? "")\(title_id ?? 0)\(name ?? "")" }
    var route: Route? { title_id.map { .libraryTitle($0) } }
}

nonisolated struct LibraryCount: Codable, Hashable {
    var titles: Int?
    var items: Int?
    var on_disk: Int?
    var missing: Int?
    var downloading: Int?
    var size: Int64?
}

nonisolated struct HomeAnswer: Codable {
    var rows: [String]?
    var owner: Bool?
    var arrived: [HomeCard]?
    var following: [HomeCard]?
    var soon: [HomeCard]?
    var new_seasons: [HomeCard]?
    var library: [String: LibraryCount]?
}

nonisolated struct PersonSummary: Codable, Hashable, Identifiable {
    var id: FlexID
    var name: String?
    var department: String?
    var profile: String?
    var known_for: [MediaItem]?
}

nonisolated struct PeopleAnswer: Codable {
    var people: [PersonSummary]?
    var page: Int?
    var total_pages: Int?
}

nonisolated struct PersonAnswer: Codable {
    nonisolated struct Person: Codable {
        var id: FlexID?
        var name: String?
        var department: String?
        var biography: String?
        var birthday: String?
        var deathday: String?
        var birthplace: String?
        var profile: String?
    }
    nonisolated struct Stats: Codable {
        var first_year: Int?
        var last_year: Int?
        var films: Int?
        var shows: Int?
        var titles: Int?
    }
    var person: Person?
    var known_for: [MediaItem]?
    var library: [MediaItem]?
    var movies: [MediaItem]?
    var coming_soon: [MediaItem]?
    var asked: [MediaItem]?
    var often_with: [PersonSummary]?
    var stats: Stats?
    var page: Int?
    var total_pages: Int?
}

nonisolated struct SearchSuggest: Codable {
    nonisolated struct Item: Codable, Hashable {
        var kind: String?
        var name: String?
        var sub: String?
        var state: String?
        var title_id: Int?
        var tmdb: FlexID?
    }
    var items: [Item]?
}

// MARK: Auth

nonisolated struct AuthState: Codable {
    var needs_setup: Bool?
    var ways: [String]?
    var host_refused: String?
    var safe_mode: Bool?
}

nonisolated struct Me: Codable, Equatable {
    var id: Int
    var name: String?
    var role: String?
    var perms: [String]?
    var csrf: String?
    var via: String?
    var auth_method: String?
    var two_factor: Bool?

    var isOwner: Bool { role == "owner" }
    func can(_ p: String) -> Bool { isOwner || (perms ?? []).contains(p) }
}

nonisolated struct LoginBody: Encodable { var name: String; var password: String }
nonisolated struct TwoFactorBody: Encodable { var ticket: String; var code: String }
nonisolated struct LoginAnswer: Codable {
    var name: String?
    var csrf: String?
    var two_factor: Bool?
    var ticket: String?
}

nonisolated struct AboutAnswer: Codable {
    var version: String?
    var os: String?
    var docker: Bool?
    var uptime_s: Int?
}
