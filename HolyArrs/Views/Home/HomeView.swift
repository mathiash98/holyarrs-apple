import SwiftUI

/// The landing page, Netflix style: a big featured billboard, then rows of landscape tiles.
struct HomeView: View {
    @Environment(AppModel.self) private var app

    struct Data {
        var home: HomeAnswer
        var featured: HomeCard?
        var featuredTitle: LibraryTitle?
        var waiting: [Ask]
        var mine: [Ask]
        var trending: DiscoverAnswer?
        var messages: MessagesAnswer?
    }

    @State private var state: Loadable<Data> = .loading
    @State private var resume: [JFItem] = []
    @State private var nextUp: [JFItem] = []
    @State private var actionError: String?

    var body: some View {
        LoadView(state: state, retry: load) { d in
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                    billboard(d)
                        .ignoresSafeArea(edges: .top)
                        .padding(.bottom, -90)
                    ActionErrorBanner(message: $actionError)
                    if let j = app.jellyfinClient {
                        jellyfinRow("Continue Watching", resume, client: j)
                        jellyfinRow("Next Up", nextUp, client: j)
                    }
                    homeTiles("New in your library", d.home.arrived)
                    if let t = d.trending, let items = t.items, !items.isEmpty {
                        MediaShelf(title: "Trending Now", items: items, style: .tiles)
                    }
                    homeTiles("New seasons", d.home.new_seasons)
                    homeTiles("Following", d.home.following)
                    homeTiles("Coming soon", d.home.soon)
                    if !d.waiting.isEmpty {
                        Shelf(title: "Waiting for your approval", items: d.waiting) { a in
                            PosterCard(title: a.name ?? "Untitled", subtitle: a.season_words ?? a.asked_by?.name, image: a.poster, badge: a.state_label, route: a.route)
                        }
                    }
                    if !d.mine.isEmpty {
                        Shelf(title: "Your requests", items: d.mine) { a in
                            PosterCard(title: a.name ?? "Untitled", subtitle: a.season_words ?? a.year.map(String.init), image: a.poster, badge: a.state_label, route: a.route)
                        }
                    }
                    if let m = d.messages, (m.unread ?? 0) > 0 {
                        NavigationLink(value: Route.messages) {
                            Label("\(m.unread ?? 0) unread message\((m.unread ?? 0) == 1 ? "" : "s")", systemImage: "bell.badge")
                                .font(.headline)
                                .padding(.horizontal, 24).padding(.vertical, 14)
                        }
                        .rowButton()
                        .padding(.horizontal, Metrics.gutter)
                    }
                    if let lib = d.home.library { libraryPanel(lib) }
                }
                .padding(.bottom, 60)
            }
            .refreshable { await load() }
        }
        #if os(visionOS)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: Route.messages) { Label("Messages", systemImage: "bell") }
            }
        }
        #endif
        .task { if state.value == nil { await load() } }
        .task(id: app.jellyfin?.userID) { await loadJellyfin() }
    }

    // MARK: Billboard

    @ViewBuilder
    private func billboard(_ d: Data) -> some View {
        if let f = d.featured {
            let key = app.tmdbKey(titleID: f.title_id)
            let t = d.featuredTitle
            Billboard(content: BillboardContent(
                kind: f.kind, tmdb: key?.tmdb ?? t?.ids?.tmdb?.value, titleID: f.title_id, name: f.name ?? "",
                logo: f.logo ?? t?.logo, backdrop: f.backdrop ?? t?.backdrop,
                headline: f.line,
                rating: t?.rating,
                meta: [f.year.map(String.init), Fmt.runtime(t?.runtime_minutes), (t?.genres?.names ?? []).prefix(2).joined(separator: " · ")]
                    .compactMap { $0 }.filter { !$0.isEmpty },
                overview: t?.overview, route: f.route)) {
                LibraryPlayButton(kind: f.kind, tmdb: key?.tmdb ?? t?.ids?.tmdb?.value, titleID: f.title_id)
                TrailerButton(kind: f.kind, tmdb: key?.tmdb ?? t?.ids?.tmdb?.value, name: f.name ?? "")
                if let r = f.route {
                    NavigationLink(value: r) { Label("More info", systemImage: "info.circle") }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func homeTiles(_ title: String, _ cards: [HomeCard]?) -> some View {
        Shelf(title: title, items: cards ?? []) { c in
            let key = app.tmdbKey(titleID: c.title_id)
            TileCard(title: c.name ?? "", line: [c.line, c.year.map(String.init)].compactMap { $0 }.joined(separator: " · "),
                     art: c.backdrop ?? c.poster, logo: c.logo, route: c.route,
                     kind: c.kind, tmdb: key?.tmdb, titleID: c.title_id)
        }
    }

    @ViewBuilder
    private func jellyfinRow(_ title: String, _ items: [JFItem], client: JellyfinClient) -> some View {
        Shelf(title: title, items: items) { it in
            TileCard(title: it.isEpisode ? (it.SeriesName ?? "") : (it.Name ?? ""),
                     line: it.isEpisode ? it.displayTitle : it.ProductionYear.map(String.init),
                     art: client.wideImage(it), logo: client.logoImage(it), progress: it.progress,
                     action: { Task { await play(it) } })
        }
    }

    private func libraryPanel(_ lib: [String: LibraryCount]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(text: "Your library")
            HStack(spacing: 24) {
                ForEach(["movie", "show", "artist"], id: \.self) { k in
                    if let c = lib[k], (c.titles ?? 0) > 0 {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(k == "movie" ? "Movies" : k == "show" ? "Shows" : "Music").font(.headline)
                            Text("\(c.titles ?? 0)").font(.system(size: 44, weight: .bold, design: .rounded))
                            Text("\(c.on_disk ?? 0) on disk · \(c.missing ?? 0) missing").font(.caption).foregroundStyle(.secondary)
                            if (c.downloading ?? 0) > 0 { Text("\(c.downloading ?? 0) downloading").font(.caption).foregroundStyle(.tint) }
                            Text(Fmt.bytes(c.size)).font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .panel(corner: 22, padding: 22)
                    }
                }
            }
            .padding(.horizontal, Metrics.gutter)
        }
    }

    // MARK: Load

    private func load() async {
        guard let c = app.client else { return }
        do {
            async let home: HomeAnswer = c.get("/home")
            async let mine: AsksAnswer? = try? c.get("/asks?mine=1&limit=20")
            async let trending: DiscoverAnswer? = try? c.get("/discover?row=trending")
            async let messages: MessagesAnswer? = try? c.get("/messages?limit=20")
            var waiting: [Ask] = []
            if app.me?.can("approve") == true {
                waiting = (try? await c.get("/asks?state=asked&limit=30", as: AsksAnswer.self))?.asks ?? []
            }
            let h = try await home
            // Feature a recent arrival that has art and a logo; a different one on each visit.
            let candidates = (h.arrived ?? []).prefix(8).filter { $0.backdrop != nil && $0.logo != nil }
            let featured = candidates.randomElement() ?? h.arrived?.first ?? h.soon?.first
            var featuredTitle: LibraryTitle?
            if let id = featured?.title_id { featuredTitle = try? await c.get("/titles/\(id)") }
            let m = await mine
            state = .loaded(Data(home: h, featured: featured, featuredTitle: featuredTitle, waiting: waiting,
                                 mine: (m?.asks ?? []).filter { $0.state != "available" },
                                 trending: await trending, messages: await messages))
        } catch is CancellationError {
        } catch {
            if state.value == nil { state = .failed(error.localizedDescription) }
        }
    }

    private func loadJellyfin() async {
        guard let j = app.jellyfinClient else { resume = []; nextUp = []; return }
        async let r = try? j.resume()
        async let n = try? j.nextUp()
        resume = await r ?? []
        nextUp = await n ?? []
    }

    private func play(_ it: JFItem) async {
        guard let j = app.jellyfinClient else { return }
        do {
            let fresh = (try? await j.item(it.Id)) ?? it
            try await Player.play(fresh, client: j, from: fresh.resumeSeconds)
        } catch {
            actionError = "Could not start playback: \(error.localizedDescription)"
        }
    }
}
