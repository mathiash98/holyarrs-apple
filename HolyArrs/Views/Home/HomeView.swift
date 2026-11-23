import SwiftUI

/// The landing page: a big featured billboard, then rows of landscape tiles.
struct HomeView: View {
    @Environment(AppModel.self) private var app

    struct Data {
        var home: HomeAnswer
        /// The top slider: titles in the library mixed with new recommendations from Explore.
        var slides: [HeroSlide]
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
            PageScrollView {
                VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                    billboard(d)
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
                                .font(.xHeadline)
                                .padding(.horizontal, 24).padding(.vertical, 14)
                        }
                        .rowButton()
                        .padding(.horizontal, Metrics.gutter)
                    }
                    if let lib = d.home.library { libraryPanel(lib) }
                }
                .padding(.bottom, 60)
            }
            #if os(tvOS)
            // Immersive: the hero runs to the top edge, under the floating tab bar.
            .ignoresSafeArea(edges: .top)
            #endif
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
        BillboardCarousel(slides: d.slides) { s in
            if s.inLibrary {
                LibraryPlayButton(kind: s.kind, tmdb: s.tmdb, titleID: s.titleID)
            }
            TrailerButton(kind: s.kind, tmdb: s.tmdb, name: s.name)
            if let r = s.route {
                NavigationLink(value: r) { Label("More info", systemImage: "info.circle") }
                    .secondaryAction()
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
                            Text(k == "movie" ? "Movies" : k == "show" ? "Shows" : "Music").font(.xHeadline)
                            Text("\(c.titles ?? 0)").font(.system(size: 44, weight: .bold, design: .rounded))
                            Text("\(c.on_disk ?? 0) on disk · \(c.missing ?? 0) missing").font(.xCaption).foregroundStyle(.secondary)
                            if (c.downloading ?? 0) > 0 { Text("\(c.downloading ?? 0) downloading").font(.xCaption).foregroundStyle(.tint) }
                            Text(Fmt.bytes(c.size)).font(.xCaption).foregroundStyle(.secondary)
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
            async let explore: ExploreHead? = try? c.get("/explore/head?type=all&tz=\(TimeZone.current.identifier.q)")
            var waiting: [Ask] = []
            if app.me?.can("approve") == true {
                waiting = (try? await c.get("/asks?state=asked&limit=30", as: AsksAnswer.self))?.asks ?? []
            }
            let h = try await home
            let slides = await heroSlides(home: h, explore: await explore, client: c)
            let m = await mine
            state = .loaded(Data(home: h, slides: slides, waiting: waiting,
                                 mine: (m?.asks ?? []).filter { $0.state != "available" },
                                 trending: await trending, messages: await messages))
        } catch is CancellationError {
        } catch {
            if state.value == nil { state = .failed(error.localizedDescription) }
        }
    }

    /// Up to four recent arrivals (with art and a logo, shuffled each visit) alternating with up to four
    /// recommendations from Explore that are not in the library yet.
    private func heroSlides(home h: HomeAnswer, explore: ExploreHead?, client c: APIClient) async -> [HeroSlide] {
        var picks = Array((h.arrived ?? []).prefix(12).filter { $0.backdrop != nil && $0.logo != nil }.shuffled().prefix(4))
        if picks.isEmpty, let f = h.arrived?.first ?? h.soon?.first { picks = [f] }
        var titles: [Int: LibraryTitle] = [:]
        await withTaskGroup(of: (Int, LibraryTitle?).self) { g in
            for p in picks { if let id = p.title_id { g.addTask { (id, try? await c.get("/titles/\(id)", as: LibraryTitle.self)) } } }
            for await (id, t) in g { if let t { titles[id] = t } }
        }
        let library: [HeroSlide] = picks.map { f in
            let t = f.title_id.flatMap { titles[$0] }
            let tmdb = app.tmdbKey(titleID: f.title_id)?.tmdb ?? t?.ids?.tmdb?.value
            return HeroSlide(id: "lib:\(f.id)", content: BillboardContent(
                kind: f.kind, tmdb: tmdb, titleID: f.title_id, name: f.name ?? "",
                logo: f.logo ?? t?.logo, backdrop: f.backdrop ?? t?.backdrop,
                headline: f.line, rating: t?.rating,
                meta: [f.year.map(String.init), Fmt.runtime(t?.runtime_minutes), (t?.genres?.names ?? []).prefix(2).joined(separator: " · ")]
                    .compactMap { $0 }.filter { !$0.isEmpty },
                overview: t?.overview, route: f.route),
                inLibrary: true, kind: f.kind, tmdb: tmdb, titleID: f.title_id, name: f.name ?? "", route: f.route)
        }
        let fresh: [HeroSlide] = (explore?.hero ?? [])
            .filter { $0.in_library != true && $0.title_id == nil && $0.card_logo != nil && ($0.backdrop ?? $0.card_art) != nil }
            .filter { !HeroSlide.looksLikeSpam($0.displayName) }
            .prefix(4)
            .map { HeroSlide(item: $0) }
        // Alternate: library, new, library, new…
        var out: [HeroSlide] = []
        for i in 0 ..< max(library.count, fresh.count) {
            if i < library.count { out.append(library[i]) }
            if i < fresh.count { out.append(fresh[i]) }
        }
        return out
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
