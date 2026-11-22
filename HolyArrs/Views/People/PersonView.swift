import SwiftUI

/// A person (`/people/{id}`): biography, known for, what is in the library, filmography and frequent co-stars.
struct PersonView: View {
    @Environment(AppModel.self) private var app
    let id: String
    @State private var state: Loadable<PersonAnswer> = .loading
    @State private var movies: [MediaItem] = []
    @State private var page = 1
    @State private var totalPages = 1

    var body: some View {
        LoadView(state: state, retry: load) { p in
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                    header(p)
                    MediaShelf(title: "Known for", items: p.known_for ?? [], defaultKind: "movie")
                    MediaShelf(title: "In your library", items: p.library ?? [], defaultKind: "movie")
                    MediaShelf(title: "Coming soon", items: p.coming_soon ?? [], defaultKind: "movie")
                    if !movies.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            SectionTitle(text: "Movies", subtitle: p.stats.map { "\($0.films ?? 0) films · \($0.shows ?? 0) shows" })
                            PosterGrid(items: movies, defaultKind: "movie")
                            if page < totalPages {
                                Button {
                                    Task { await loadPage(page + 1) }
                                } label: {
                                    Label("More movies", systemImage: "chevron.down").frame(maxWidth: .infinity).padding()
                                }
                                .rowButton()
                                .padding(.horizontal, Metrics.gutter)
                            }
                        }
                    }
                    PeopleShelf(title: "Often with", people: p.often_with ?? [])
                }
                .padding(.vertical, 20)
            }
        }
        #if os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { if state.value == nil { await load() } }
    }

    private func header(_ p: PersonAnswer) -> some View {
        HStack(alignment: .top, spacing: 32) {
            RemoteImage(path: p.person?.profile)
                .frame(width: 220, height: 220)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 10) {
                Text(p.person?.name ?? "").font(.largeTitle.bold())
                Text(detailLine(p)).font(.headline).foregroundStyle(.secondary)
                if let bio = p.person?.biography, !bio.isEmpty {
                    Text(bio).font(.callout).lineLimit(8).frame(maxWidth: 1000, alignment: .leading)
                }
            }
        }
        .panel(corner: 32, padding: 28)
        .padding(.horizontal, Metrics.gutter)
    }

    private func detailLine(_ p: PersonAnswer) -> String {
        var out: [String] = []
        if let d = p.person?.department { out.append(d) }
        if let b = p.person?.birthday, let date = HADate.parse(b) { out.append("Born \(date.formatted(date: .long, time: .omitted))") }
        if let place = p.person?.birthplace { out.append(place) }
        if let s = p.stats, let a = s.first_year, let b = s.last_year { out.append("\(a)–\(b)") }
        return out.joined(separator: " · ")
    }

    private func load() async {
        guard let c = app.client else { return }
        do {
            let p: PersonAnswer = try await c.get("/people/\(id.q)")
            state = .loaded(p)
            movies = p.movies ?? []
            page = p.page ?? 1
            totalPages = p.total_pages ?? 1
        } catch is CancellationError {
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func loadPage(_ n: Int) async {
        guard let c = app.client else { return }
        if let p: PersonAnswer = try? await c.get("/people/\(id.q)?page=\(n)") {
            let have = Set(movies.map(\.id))
            movies += (p.movies ?? []).filter { !have.contains($0.id) }
            page = n
            totalPages = p.total_pages ?? totalPages
        }
    }
}
