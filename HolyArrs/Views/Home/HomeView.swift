import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var app

    struct Data {
        var home: HomeAnswer
        var waiting: [Ask]
        var mine: [Ask]
        var trending: DiscoverAnswer?
        var messages: MessagesAnswer?
    }

    @State private var state: Loadable<Data> = .loading

    var body: some View {
        LoadView(state: state, retry: load) { d in
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                    hero(d.home)
                        .ignoresSafeArea(edges: .top)
                        .padding(.bottom, -90)
                    if let m = d.messages, (m.unread ?? 0) > 0 {
                        NavigationLink(value: Route.messages) {
                            Label("\(m.unread ?? 0) unread message\((m.unread ?? 0) == 1 ? "" : "s")", systemImage: "bell.badge")
                                .font(.headline)
                                .padding(.horizontal, 24).padding(.vertical, 14)
                        }
                        .rowButton()
                        .padding(.horizontal, Metrics.gutter)
                    }
                    homeShelf("Just arrived", d.home.arrived, wide: true)
                    if !d.waiting.isEmpty {
                        Shelf(title: "Waiting for approval", subtitle: "Requests you can approve", items: d.waiting) { a in
                            PosterCard(title: a.name ?? "Untitled", subtitle: a.season_words ?? a.asked_by?.name, image: a.poster, badge: a.state_label, route: a.route)
                        }
                    }
                    if !d.mine.isEmpty {
                        Shelf(title: "Your requests", items: d.mine) { a in
                            PosterCard(title: a.name ?? "Untitled", subtitle: a.season_words ?? a.year.map(String.init), image: a.poster, badge: a.state_label, route: a.route)
                        }
                    }
                    homeShelf("New seasons", d.home.new_seasons, wide: false)
                    homeShelf("Following", d.home.following, wide: false)
                    homeShelf("Coming soon", d.home.soon, wide: true)
                    if let t = d.trending, let items = t.items, !items.isEmpty {
                        MediaShelf(title: t.title ?? "Trending", items: items)
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
    }

    @ViewBuilder
    private func hero(_ h: HomeAnswer) -> some View {
        if let first = h.arrived?.first ?? h.soon?.first {
            let key = app.tmdbKey(titleID: first.title_id)
            Billboard(content: BillboardContent(kind: first.kind, tmdb: key?.tmdb, titleID: first.title_id, name: first.name ?? "",
                                                logo: first.logo, backdrop: first.backdrop,
                                                meta: [first.line, first.year.map(String.init)].compactMap { $0 },
                                                route: first.route)) {
                LibraryPlayButton(kind: first.kind, tmdb: key?.tmdb, titleID: first.title_id)
                if let r = first.route {
                    NavigationLink(value: r) { Label("More info", systemImage: "info.circle") }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    @ViewBuilder
    private func homeShelf(_ title: String, _ cards: [HomeCard]?, wide: Bool) -> some View {
        let items = cards ?? []
        if wide {
            Shelf(title: title, items: items) { c in
                WideCard(title: c.name ?? "", subtitle: c.line ?? c.year.map(String.init), image: c.backdrop, route: c.route, kind: c.kind, titleID: c.title_id)
            }
        } else {
            Shelf(title: title, items: items) { c in
                PosterCard(title: c.name ?? "", subtitle: c.line ?? c.year.map(String.init), image: c.poster ?? c.backdrop, route: c.route, kind: c.kind, titleID: c.title_id)
            }
        }
    }

    private func libraryPanel(_ lib: [String: LibraryCount]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(text: "Library")
            HStack(spacing: 24) {
                ForEach(["movie", "show", "artist"], id: \.self) { k in
                    if let c = lib[k], (c.titles ?? 0) > 0 {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(k == "movie" ? "Movies" : k == "show" ? "Shows" : "Music").font(.headline)
                            Text("\(c.titles ?? 0)").font(.system(size: 44, weight: .bold, design: .rounded))
                            Text("\(c.on_disk ?? 0) on disk · \(c.missing ?? 0) missing").font(.caption).foregroundStyle(.secondary)
                            if (c.downloading ?? 0) > 0 { Text("\(c.downloading ?? 0) downloading").font(.caption).foregroundStyle(.blue) }
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
            let m = await mine
            state = .loaded(Data(home: h, waiting: waiting, mine: (m?.asks ?? []).filter { $0.state != "available" }, trending: await trending, messages: await messages))
        } catch is CancellationError {
        } catch {
            if state.value == nil { state = .failed(error.localizedDescription) }
        }
    }
}
