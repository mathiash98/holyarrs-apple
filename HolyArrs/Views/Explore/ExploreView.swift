import SwiftUI

/// Explore: the personal rows from `/explore/head` and `/explore/tail`, Browse genres and categories, and New & Popular.
struct ExploreView: View {
    @Environment(AppModel.self) private var app

    enum Kind: String, CaseIterable, Identifiable {
        case all, movies, shows
        var id: String { rawValue }
        var label: String { self == .all ? "All" : self == .movies ? "Movies" : "Shows" }
    }

    @State private var kind: Kind = .all
    @State private var head: Loadable<ExploreHead> = .loading
    @State private var tail: [ExploreRow] = []
    @State private var tailPage = 0
    @State private var tailMore = true
    @State private var loadingTail = false
    @State private var browse: BrowseAnswer?
    @State private var sectionTiles: [String: [BrowseTile]] = [:]

    var body: some View {
        PageScrollView {
            VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                if let first = head.value?.hero?.first {
                    Billboard(content: BillboardContent(kind: first.kind, tmdb: first.tmdbID, titleID: first.title_id, name: first.displayName,
                                                        logo: first.card_logo, backdrop: first.backdrop ?? first.card_art,
                                                        meta: [first.year.map(String.init), first.kind == "show" ? "Series" : "Movie", first.fresh?.text].compactMap { $0 },
                                                        overview: first.overview, route: first.route)) {
                        if first.in_library == true || first.title_id != nil {
                            LibraryPlayButton(kind: first.kind, tmdb: first.tmdbID, titleID: first.title_id)
                        }
                        TrailerButton(kind: first.kind, tmdb: first.tmdbID, name: first.displayName)
                        if let r = first.route {
                            NavigationLink(value: r) { Label("More info", systemImage: "info.circle") }
                                .secondaryAction()
                        }
                    }
                    .ignoresSafeArea(edges: .top)
                    .padding(.bottom, -90)
                }
                HStack(spacing: 20) {
                    Picker("Type", selection: $kind) {
                        ForEach(Kind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 520)
                    Spacer()
                    NavigationLink(value: Route.popular) {
                        Label("New & Popular", systemImage: "flame").lineLimit(1).fixedSize().padding(.horizontal, 18).padding(.vertical, 10)
                    }
                    .rowButton()
                }
                .padding(.horizontal, Metrics.gutter)

                switch head {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity, minHeight: 300)
                case let .failed(m):
                    ErrorView(message: m) { await loadHead() }.frame(minHeight: 300)
                case let .loaded(h):
                    if let hero = h.hero, hero.count > 1 { MediaShelf(title: "Featured", items: Array(hero.dropFirst())) }
                    ForEach(h.head ?? []) { row in
                        if let items = row.items, !items.isEmpty {
                            MediaShelf(title: row.title ?? "", subtitle: row.subtitle, items: items)
                        }
                    }
                }

                browseGrid

                ForEach(tail) { row in
                    MediaShelf(title: row.title ?? "", subtitle: row.subtitle, items: row.items ?? [])
                }
                if tailMore, head.value != nil {
                    Button {
                        Task { await loadTail() }
                    } label: {
                        Label(loadingTail ? "Loading…" : "Show more rows", systemImage: "chevron.down").frame(maxWidth: .infinity).padding()
                    }
                    .rowButton()
                    .padding(.horizontal, Metrics.gutter)
                    .disabled(loadingTail)
                }
            }
            .padding(.vertical, 20)
        }
        #if os(tvOS)
        .ignoresSafeArea(edges: .top)
        #endif
        .task(id: kind) { await loadAll() }
    }

    @ViewBuilder
    private var browseGrid: some View {
        if let b = browse {
            let genres = b.tiles ?? []
            if !genres.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    SectionTitle(text: "Browse by genre")
                    TileGrid(tiles: genres, type: kind.rawValue)
                }
            }
            ForEach(b.sections ?? []) { s in
                if s.id != "genres", let tiles = sectionTiles[s.id], !tiles.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionTitle(text: s.title ?? s.id)
                        TileGrid(tiles: tiles, type: kind.rawValue)
                    }
                }
            }
        }
    }

    private func loadAll() async {
        tail = []
        tailPage = 0
        tailMore = true
        head = .loading
        async let h: () = loadHead()
        async let b: () = loadBrowse()
        _ = await (h, b)
    }

    private func loadHead() async {
        guard let c = app.client else { return }
        let tz = TimeZone.current.identifier.q
        do {
            head = .loaded(try await c.get("/explore/head?type=\(kind.rawValue)&tz=\(tz)"))
        } catch is CancellationError {
        } catch {
            head = .failed(error.localizedDescription)
        }
    }

    private func loadTail() async {
        guard let c = app.client, !loadingTail else { return }
        loadingTail = true
        defer { loadingTail = false }
        let next = tailPage + 1
        let tz = TimeZone.current.identifier.q
        if let t: ExploreTail = try? await c.get("/explore/tail?type=\(kind.rawValue)&tz=\(tz)&page=\(next)") {
            let seen = Set(tail.map(\.id) + (head.value?.head ?? []).map(\.id))
            tail += (t.rows ?? []).filter { !seen.contains($0.id) && !($0.items ?? []).isEmpty }
            tailPage = next
            tailMore = t.more ?? false
        } else {
            tailMore = false
        }
    }

    private func loadBrowse() async {
        guard let c = app.client else { return }
        guard let b: BrowseAnswer = try? await c.get("/explore/browse?type=\(kind.rawValue)") else { return }
        browse = b
        var found: [String: [BrowseTile]] = [:]
        for s in b.sections ?? [] where s.id != "genres" {
            if let a: BrowseSectionAnswer = try? await c.get("/explore/browse/section?type=\(kind.rawValue)&section=\(s.id.q)") {
                found[s.id] = a.tiles ?? []
            }
        }
        sectionTiles = found
    }
}

/// Big backdrop cards at the top of Explore.
struct HeroCarousel: View {
    let items: [MediaItem]
    var body: some View {
        PageScrollView(.horizontal) {
            LazyHStack(spacing: Metrics.cardSpacing) {
                ForEach(items) { it in
                    NavigationLink(value: it.route ?? .popular) {
                        ZStack(alignment: .bottomLeading) {
                            RemoteImage(path: it.backdrop ?? it.card_art)
                            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                            VStack(alignment: .leading, spacing: 8) {
                                if let logo = it.card_logo {
                                    RemoteImage(path: logo, contentMode: .fit).frame(maxWidth: 340, maxHeight: 100, alignment: .leading)
                                } else {
                                    Text(it.displayName).font(.xTitle.bold())
                                }
                                if let o = it.overview { Text(o).font(.xCallout).lineLimit(2).foregroundStyle(.white.opacity(0.85)) }
                            }
                            .padding(28)
                            .foregroundStyle(.white)
                        }
                        .frame(width: width, height: width * 9 / 16)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    }
                    .cardButton(corner: 28)
                    .disabled(it.route == nil)
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 20)
        }
        .scrollIndicators(.hidden)
        #if os(tvOS)
        .scrollClipDisabled()
        #endif
    }

    private var width: CGFloat {
        #if os(tvOS)
        880
        #else
        Metrics.isPhone ? 320 : 720
        #endif
    }
}

/// A grid of browse tiles (genres or categories).
struct TileGrid: View {
    let tiles: [BrowseTile]
    let type: String

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: tileWidth), spacing: Metrics.cardSpacing)], spacing: Metrics.cardSpacing) {
            ForEach(tiles) { t in
                NavigationLink(value: route(t)) {
                    ZStack(alignment: .bottomLeading) {
                        RemoteImage(path: t.backdrop)
                        LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                        Text(t.name ?? t.genre_name ?? "").font(.xTitle3.bold()).foregroundStyle(.white).padding(16)
                    }
                    .frame(height: tileWidth * 9 / 16)
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous))
                }
                .cardButton()
            }
        }
        .padding(.horizontal, Metrics.gutter)
    }

    private var tileWidth: CGFloat {
        #if os(tvOS)
        340
        #else
        Metrics.isPhone ? 160 : 260
        #endif
    }

    private func route(_ t: BrowseTile) -> Route {
        if let c = t.category { return .category(type: type, id: c, name: t.name ?? "") }
        let gtype = t.both == true ? "all" : (type == "all" ? (t.kind == "show" ? "shows" : "movies") : type)
        return .genre(type: gtype, genre: t.genre ?? 0, name: t.name ?? t.genre_name ?? "")
    }
}

/// One genre: its hero and rows from `/explore/genre`.
struct GenreView: View {
    @Environment(AppModel.self) private var app
    let type: String
    let genre: Int
    let name: String
    @State private var state: Loadable<GenreAnswer> = .loading

    var body: some View {
        LoadView(state: state, retry: load) { g in
            PageScrollView {
                VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                    PageHeading(text: g.genre?.name ?? name)
                    if let hero = g.hero, !hero.isEmpty { HeroCarousel(items: hero) }
                    ForEach(g.rows ?? []) { r in
                        MediaShelf(title: r.title ?? "", subtitle: r.subtitle, items: r.items ?? [])
                    }
                }
                .padding(.vertical, 20)
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard let c = app.client else { return }
        do { state = .loaded(try await c.get("/explore/genre?type=\(type)&genre=\(genre)")) }
        catch is CancellationError {}
        catch { state = .failed(error.localizedDescription) }
    }
}

/// One Browse category (`/explore/browse/category`).
struct CategoryView: View {
    @Environment(AppModel.self) private var app
    let type: String
    let id: String
    let name: String
    @State private var state: Loadable<CategoryAnswer> = .loading

    var body: some View {
        LoadView(state: state, retry: load) { c in
            PageScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PageHeading(text: c.name ?? name)
                    PosterGrid(items: c.items ?? [])
                }
                .padding(.vertical, 20)
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard let c = app.client else { return }
        do { state = .loaded(try await c.get("/explore/browse/category?type=\(type)&id=\(id.q)")) }
        catch is CancellationError {}
        catch { state = .failed(error.localizedDescription) }
    }
}

/// An adaptive grid of posters.
struct PosterGrid: View {
    let items: [MediaItem]
    var defaultKind: String? = nil
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: Metrics.posterWidth), spacing: Metrics.cardSpacing, alignment: .top)], spacing: Metrics.cardSpacing) {
            ForEach(items) { raw in
                let it = defaultKind.map { raw.withKind($0) } ?? raw
                PosterCard(title: it.displayName, subtitle: it.year.map(String.init), image: it.poster ?? it.card_art, badge: it.badge, route: it.route, kind: it.kind, tmdb: it.tmdbID, titleID: it.title_id, backdrop: it.backdrop ?? it.card_art)
            }
        }
        .padding(.horizontal, Metrics.gutter)
    }
}
