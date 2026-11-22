import SwiftUI

/// Every pushed page. Each tab owns a NavigationStack that understands all of them.
enum Route: Hashable {
    case title(kind: String, tmdb: String)
    case libraryTitle(Int)
    case person(String)
    case genre(type: String, genre: Int, name: String)
    case category(type: String, id: String, name: String)
    case popular
    case messages
    case decide
    case history
    case turnedDown

    #if DEBUG
    /// Parses debug hooks such as `title/movie/350`, `library/187`, `person/31`, `popular`.
    init?(debugString s: String) {
        let p = s.split(separator: "/").map(String.init)
        switch p.first {
        case "title" where p.count == 3: self = .title(kind: p[1], tmdb: p[2])
        case "library" where p.count == 2: guard let i = Int(p[1]) else { return nil }; self = .libraryTitle(i)
        case "person" where p.count == 2: self = .person(p[1])
        case "genre" where p.count == 3: guard let g = Int(p[2]) else { return nil }; self = .genre(type: p[1], genre: g, name: "Genre")
        case "popular": self = .popular
        case "messages": self = .messages
        case "decide": self = .decide
        case "history": self = .history
        case "turned-down": self = .turnedDown
        default: return nil
        }
    }
    #endif
}

struct RouteDestinations: ViewModifier {
    func body(content: Content) -> some View {
        content.navigationDestination(for: Route.self) { route in
            switch route {
            case let .title(kind, tmdb): TitleDetailView(source: .tmdb(kind: kind, id: tmdb))
            case let .libraryTitle(id): TitleDetailView(source: .library(id))
            case let .person(id): PersonView(id: id)
            case let .genre(type, genre, name): GenreView(type: type, genre: genre, name: name)
            case let .category(type, id, name): CategoryView(type: type, id: id, name: name)
            case .popular: PopularView()
            case .messages: MessagesView()
            case .decide: DecideView()
            case .history: HistoryView()
            case .turnedDown: TurnedDownView()
            }
        }
    }
}

extension View {
    func withRoutes() -> some View { modifier(RouteDestinations()) }
}
