import SwiftUI

/// Search: the library (`/search`), TMDB movies and shows (`/titles/lookup`, `/shows/lookup`) and people (`/people/search`).
struct SearchView: View {
    @Environment(AppModel.self) private var app
    @State private var query = ""

    struct Results {
        var library: [MediaItem] = []
        var movies: [MediaItem] = []
        var shows: [MediaItem] = []
        var people: [PersonSummary] = []
        var isEmpty: Bool { library.isEmpty && movies.isEmpty && shows.isEmpty && people.isEmpty }
    }

    @State private var results = Results()
    @State private var searching = false
    @State private var popularPeople: [PersonSummary] = []

    var body: some View {
        PageScrollView {
            VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    if !popularPeople.isEmpty {
                        PeopleShelf(title: "Popular people", people: popularPeople)
                    }
                    EmptyNote(title: "Search movies, shows and people", systemImage: "magnifyingglass", detail: "Results from your library come first.")
                } else if searching && results.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 300)
                } else if results.isEmpty {
                    EmptyNote(title: "No results for “\(query)”", systemImage: "magnifyingglass")
                } else {
                    MediaShelf(title: "In your library", items: results.library)
                    MediaShelf(title: "Movies", items: results.movies, defaultKind: "movie")
                    MediaShelf(title: "Shows", items: results.shows, defaultKind: "show")
                    PeopleShelf(title: "People", people: results.people)
                }
            }
            .padding(.vertical, 20)
        }
        .searchable(text: $query, prompt: "Movies, shows, people")
        .task(id: query) { await search() }
        .task { await loadPopularPeople() }
        .onAppear {
            if let q = app.debugQuery, !q.isEmpty { app.debugQuery = nil; query = q }
        }
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, let c = app.client else { results = Results(); return }
        // Debounce typing.
        try? await Task.sleep(for: .milliseconds(350))
        if Task.isCancelled { return }
        searching = true
        defer { searching = false }
        async let lib: LibrarySearchAnswer? = try? c.get("/search?q=\(q.q)")
        async let movies: MovieLookup? = try? c.get("/titles/lookup?term=\(q.q)")
        async let shows: ShowLookup? = try? c.get("/shows/lookup?term=\(q.q)")
        async let people: PeopleAnswer? = try? c.get("/people/search?q=\(q.q)")
        let libItems = ((await lib)?.titles ?? []).filter { $0.kind == "movie" || $0.kind == "show" }.map { t in
            MediaItem(ids: t.ids, kind: t.kind, name: t.name, year: t.year, poster: t.poster, backdrop: t.backdrop, in_library: true, title_id: t.id)
        }
        let libTMDB = Set(libItems.compactMap(\.tmdbID))
        if Task.isCancelled { return }
        results = Results(
            library: libItems,
            movies: ((await movies)?.movies ?? []).filter { !libTMDB.contains($0.tmdbID ?? "") },
            shows: ((await shows)?.shows ?? []).filter { !libTMDB.contains($0.tmdbID ?? "") },
            people: Array(((await people)?.people ?? []).prefix(20))
        )
    }

    private func loadPopularPeople() async {
        guard popularPeople.isEmpty, let c = app.client else { return }
        popularPeople = (try? await c.get("/people/popular", as: PeopleAnswer.self))?.people ?? []
    }
}

struct PeopleShelf: View {
    let title: String
    let people: [PersonSummary]
    var body: some View {
        Shelf(title: title, items: people) { p in
            PersonCard(name: p.name ?? "", detail: p.department, image: p.profile, id: p.id.value)
        }
    }
}
