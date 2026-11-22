import SwiftUI

enum TitleSource: Hashable {
    case tmdb(kind: String, id: String)
    case library(Int)
}

/// One movie or show, whether it is in the library or not (the web's /title/[kind]/[tmdb]).
struct TitleDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    let source: TitleSource

    struct Model {
        var kind: String
        var tmdb: String?
        var meta: TitleMeta?
        var lib: LibraryTitle?
        var swiftfin: URL?
        /// The Jellyfin movie or series, the show's next episode, and its episodes (for playback).
        var jf: JFItem?
        var nextUp: JFItem?
        var jfEpisodes: [JFItem] = []

        /// What Play starts: the movie, or the show's next episode.
        var playTarget: JFItem? { kind == "movie" ? jf : (nextUp ?? jfEpisodes.first) }

        var name: String { meta?.name ?? lib?.name ?? "Untitled" }
        var titleID: Int? { lib?.id ?? meta?.title_id }
        var inLibrary: Bool { lib != nil || meta?.in_library == true }
        var ask: AskBrief? { meta?.ask }
    }

    @State private var state: Loadable<Model> = .loading
    @State private var showAsk = false
    @State private var actionError: String?
    @State private var notice: String?
    @State private var showConnect = false
    @State private var starting = false

    var body: some View {
        LoadView(state: state, retry: load) { m in
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                    header(m)
                    ActionErrorBanner(message: $actionError)
                    if let notice {
                        Label(notice, systemImage: "checkmark.circle.fill").foregroundStyle(.green).padding(.horizontal, Metrics.gutter)
                    }
                    statusPanel(m)
                    if m.kind == "show", let tmdb = m.tmdb {
                        SeasonsSection(tmdb: tmdb, seasons: seasons(m), library: m.lib?.show?.seasons ?? [], jfEpisodes: m.jfEpisodes, series: m.jf) { ep in
                            Task { await play(ep, resume: true) }
                        }
                    }
                    let cast = (m.meta?.people ?? []).filter { $0.name != nil }
                    if !cast.isEmpty {
                        Shelf(title: "Cast & crew", items: cast.map { IdentifiedPerson(p: $0) }) { ip in
                            PersonCard(name: ip.p.name ?? "", detail: ip.p.character ?? ip.p.job ?? ip.p.role, image: ip.p.profile, id: ip.p.id?.value)
                        }
                    }
                    if let col = m.meta?.collection, let parts = col.parts, parts.count > 1 {
                        MediaShelf(title: col.name ?? "Collection", items: parts, defaultKind: m.kind)
                    }
                    MediaShelf(title: "More like this", items: m.meta?.similar ?? [], defaultKind: m.kind)
                }
                .padding(.bottom, 60)
            }
            .sheet(isPresented: $showConnect) {
                JellyfinConnectSheet {
                    showConnect = false
                    Task { await load() }
                }
            }
            .sheet(isPresented: $showAsk) {
                AskSheet(kind: m.kind, tmdb: m.tmdb ?? "", name: m.name, year: m.meta?.year ?? m.lib?.year, poster: m.meta?.poster ?? m.lib?.poster, seasons: seasons(m)) { ok in
                    showAsk = false
                    if ok {
                        notice = "Asked for \(m.name)."
                        Task { await load() }
                    }
                }
            }
        }
        // No bar title: the header already shows the name, and a bar title floats over the content while scrolling.
        #if os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { if state.value == nil { await load() } }
    }

    private func seasons(_ m: Model) -> [TitleMeta.Season] {
        if let s = m.meta?.seasons, !s.isEmpty { return s.filter { $0.number > 0 } }
        return (m.lib?.show?.seasons ?? []).filter { $0.number > 0 }.map { TitleMeta.Season(number: $0.number, episode_count: $0.episodes, year: nil, name: $0.name) }
    }

    // MARK: Header

    @ViewBuilder
    private func header(_ m: Model) -> some View {
        Billboard(content: BillboardContent(kind: m.kind, tmdb: m.tmdb, titleID: m.titleID, name: m.name,
                                            logo: m.meta?.logo ?? m.lib?.logo, backdrop: m.meta?.backdrop ?? m.lib?.backdrop,
                                            tagline: m.meta?.tagline, meta: [metaLine(m)],
                                            overview: m.meta?.overview ?? m.lib?.overview),
                  height: BillboardMetrics.height + 60, overviewLines: 6) {
            actions(m)
        }
        .ignoresSafeArea(edges: .top)
        .padding(.bottom, -70)
    }

    private func metaLine(_ m: Model) -> String {
        var p: [String] = []
        if let y = m.meta?.year ?? m.lib?.year { p.append(String(y)) }
        p.append(m.kind == "show" ? "TV show" : "Movie")
        if let r = Fmt.runtime(m.meta?.runtime_minutes ?? m.meta?.episode_runtime ?? m.lib?.runtime_minutes) { p.append(r) }
        if let r = m.meta?.rating ?? m.lib?.rating, !r.isEmpty { p.append(r) }
        if let s = m.meta?.score ?? m.lib?.score, s > 0 { p.append(String(format: "★ %.1f", s)) }
        p += Array((m.meta?.genres?.names ?? m.lib?.genres?.names ?? []).prefix(3))
        return p.joined(separator: " · ")
    }

    @ViewBuilder
    private func actions(_ m: Model) -> some View {
        HStack(spacing: 18) {
            if let target = m.playTarget {
                Button {
                    Task { await play(target, resume: true) }
                } label: {
                    Label(playLabel(target, m), systemImage: "play.fill")
                }
                .primaryAction()
                .disabled(starting)
                if target.resumeSeconds != nil {
                    Button {
                        Task { await play(target, resume: false) }
                    } label: {
                        Label("From start", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(starting)
                }
            }
            OfflineDownloadButton(item: m.kind == "movie" ? m.jf : nil)
            if m.playTarget == nil, m.lib?.hasFiles == true, app.jellyfin == nil {
                Button {
                    showConnect = true
                } label: {
                    Label("Connect Jellyfin to play", systemImage: "play.circle")
                }
                .buttonStyle(.bordered)
            }
            if let url = m.swiftfin {
                Button {
                    openURL(url) { ok in if !ok { actionError = "Could not open Swiftfin. Is it installed and signed in to this Jellyfin user?" } }
                } label: {
                    Label("Swiftfin", systemImage: "play.fill")
                }
                .buttonStyle(.bordered)
            }
            if canAsk(m) {
                Button {
                    showAsk = true
                } label: {
                    Label(m.inLibrary ? "Ask for more" : "Ask", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.bordered)
                .disabled(app.me?.can("ask") != true && app.me?.isOwner != true)
            }
            if let key = m.meta?.trailerKey {
                Button {
                    Task { await playTrailer(m, key: key) }
                } label: {
                    Label("Trailer", systemImage: "play.rectangle")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func canAsk(_ m: Model) -> Bool {
        guard m.tmdb != nil, m.meta?.never_add != true else { return false }
        if let a = m.ask, a.mine == true, a.state == "asked" || a.state == "approved" { return m.kind == "show" }
        if m.kind == "movie" { return !m.inLibrary }
        return true
    }

    private func playLabel(_ t: JFItem, _ m: Model) -> String {
        let verb = t.resumeSeconds != nil ? "Resume" : "Play"
        var label = verb
        if t.isEpisode, let s = t.ParentIndexNumber, let e = t.IndexNumber { label += " S\(s)E\(e)" }
        if let r = t.resumeSeconds { label += " · \(Fmt.clock(r))" }
        return label
    }

    /// Plays a Jellyfin item in the built-in player; `resume` starts at the saved position.
    private func play(_ it: JFItem, resume: Bool) async {
        guard let j = app.jellyfinClient else { showConnect = true; return }
        starting = true
        defer { starting = false }
        do {
            // Re-read the item so the resume point is current (it may have changed in another app).
            let fresh = (try? await j.item(it.Id)) ?? it
            if await OfflineHooks.playIfDownloaded(fresh, resume: resume) { return }
            try await Player.play(fresh, client: j, from: resume ? fresh.resumeSeconds : nil)
        } catch {
            actionError = "Could not start playback: \(error.localizedDescription)"
        }
    }

    /// Plays the trailer HolyArrs already resolved (native player); otherwise opens it on YouTube.
    private func playTrailer(_ m: Model, key: String) async {
        if let c = app.client, let tmdb = m.tmdb,
           let t: TrailerStream = try? await c.get("/trailer/\(m.kind)/\(tmdb.q)"),
           let s = t.url, let u = URL(string: s) {
            Player.play(url: u, title: m.name, subtitle: "Trailer")
            return
        }
        openTrailerExternally(key)
    }

    private func openTrailerExternally(_ key: String) {
        #if os(tvOS)
        // The YouTube app on tvOS answers youtube://watch/<id>; there is no web browser.
        guard let app = URL(string: "youtube://watch/\(key)") else { return }
        openURL(app) { ok in
            if !ok { actionError = "Install the YouTube app to watch trailers (video \(key))." }
        }
        #else
        guard let web = URL(string: "https://www.youtube.com/watch?v=\(key)") else { return }
        openURL(web) { ok in if !ok { actionError = "Could not open the trailer." } }
        #endif
    }

    // MARK: Status

    @ViewBuilder
    private func statusPanel(_ m: Model) -> some View {
        let items = statusItems(m)
        if !items.isEmpty {
            HStack(spacing: 16) {
                ForEach(items, id: \.text) { s in
                    Label(s.text, systemImage: s.icon).foregroundStyle(s.tint)
                }
                Spacer()
            }
            .font(.headline)
            .panel(corner: 22, padding: 18)
            .padding(.horizontal, Metrics.gutter)
        }
    }

    private struct StatusItem { let text: String; let icon: String; let tint: Color }

    private func statusItems(_ m: Model) -> [StatusItem] {
        var out: [StatusItem] = []
        if let lib = m.lib {
            out.append(StatusItem(text: lib.statusSummary, icon: lib.hasFiles ? "checkmark.circle.fill" : "tray", tint: lib.hasFiles ? .green : .secondary))
            if lib.isDownloading, !lib.statusSummary.contains("downloading") {
                out.append(StatusItem(text: "Downloading", icon: "arrow.down.circle.fill", tint: .blue))
            }
        } else if m.inLibrary {
            out.append(StatusItem(text: "In library", icon: "checkmark.circle.fill", tint: .green))
        }
        if let fq = m.lib?.fileQuality {
            out.append(StatusItem(text: [fq.label, fq.detail].filter { !$0.isEmpty }.joined(separator: " · "), icon: "sparkles.tv", tint: .yellow))
        } else if let q = app.quality(kind: m.kind, tmdb: m.tmdb, titleID: m.titleID) {
            out.append(StatusItem(text: q, icon: "sparkles.tv", tint: .yellow))
        }
        if m.kind == "movie", let p = m.jf?.progress {
            out.append(StatusItem(text: "\(Int(p * 100))% watched", icon: "play.circle", tint: .secondary))
        }
        if let a = m.ask, let label = a.state_label ?? a.state {
            var t = "Asked: \(label)"
            if let s = a.seasons, !s.isEmpty { t += " (season\(s.count == 1 ? "" : "s") \(s.map(String.init).joined(separator: ", ")))" }
            out.append(StatusItem(text: t, icon: "hand.raised.fill", tint: StateBadge.tint(forAskState: a.state)))
        }
        return out
    }

    // MARK: Load

    private func load() async {
        guard let c = app.client else { return }
        do {
            var kind: String
            var tmdb: String?
            var lib: LibraryTitle?
            switch source {
            case let .tmdb(k, id):
                kind = k
                tmdb = id
            case let .library(id):
                let t: LibraryTitle = try await c.get("/titles/\(id)")
                lib = t
                kind = t.kind ?? "movie"
                tmdb = t.ids?.tmdb?.value
            }
            var meta: TitleMeta?
            if let tmdb {
                do {
                    meta = try await c.get("/metadata/\(kind)/\(tmdb.q)")
                } catch let e as APIError where e.status == 404 {
                    meta = nil
                }
            }
            if lib == nil, let id = meta?.title_id {
                lib = try? await c.get("/titles/\(id)")
            }
            var model = Model(kind: kind, tmdb: tmdb, meta: meta, lib: lib)
            state = .loaded(model)
            if app.debugOpenAsk { app.debugOpenAsk = false; showAsk = true }
            if let j = app.jellyfinClient,
               let id = await j.itemID(kind: kind, tmdb: tmdb, tvdb: lib?.ids?.tvdb?.value) {
                model.jf = try? await j.item(id)
                if kind == "show" {
                    model.nextUp = (try? await j.nextUp(series: id, limit: 1))?.first
                    model.jfEpisodes = (try? await j.episodes(series: id)) ?? []
                }
                state = .loaded(model)
            }
            #if DEBUG
            if app.debugAutoPlay > 0, let t = model.playTarget {
                Player.debugAutoClose = app.debugAutoPlay
                app.debugAutoPlay = 0
                Task { await play(t, resume: true) }
            }
            #endif
            if let lib, lib.hasFiles {
                model.swiftfin = await swiftfinURL(titleID: lib.id)
                state = .loaded(model)
            }
        } catch is CancellationError {
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// A Swiftfin deep link when the title is on Jellyfin and we know the Jellyfin user (from our own Jellyfin
    /// login, or for owners from `/users/media-accounts`). Both HolyArrs routes need manage_library or owner.
    private func swiftfinURL(titleID: Int) async -> URL? {
        guard let c = app.client, app.me?.can("manage_library") == true else { return nil }
        guard let links: WatchLinks = try? await c.get("/media-servers/watch-links?title=\(titleID)") else { return nil }
        guard let link = links.links?.first(where: { $0.kind == "jellyfin" }), let u = link.url,
              let ids = SwiftfinLink.ids(fromWatchURL: u) else { return nil }
        var userID = app.jellyfin?.userID
        if userID == nil, app.me?.isOwner == true, let me = app.me,
           let accts: MediaAccounts = try? await c.get("/users/media-accounts") {
            userID = accts.servers?.filter { $0.kind == "jellyfin" }
                .flatMap { $0.accounts ?? [] }
                .first { $0.taken_by == me.id }?.id
        }
        guard let userID else { return nil }
        return SwiftfinLink.url(server: ids.server, user: userID, item: ids.item)
    }
}

private struct IdentifiedPerson: Identifiable {
    let p: TitleMeta.Person
    var id: String { p.identity }
}

/// Seasons of a show with library counts, and the chosen season's episodes.
struct SeasonsSection: View {
    @Environment(AppModel.self) private var app
    let tmdb: String
    let seasons: [TitleMeta.Season]
    let library: [LibraryTitle.ShowInfo.Season]
    var jfEpisodes: [JFItem] = []
    /// The Jellyfin series (saved with downloaded episodes).
    var series: JFItem? = nil
    var play: ((JFItem) -> Void)? = nil
    @State private var selected: Int?
    @State private var episodes: [SeasonEpisodes.Episode] = []
    @State private var loading = false

    var body: some View {
        if !seasons.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                SectionTitle(text: "Seasons")
                ScrollView(.horizontal) {
                    HStack(spacing: Metrics.cardSpacing / 2) {
                        ForEach(seasons) { s in
                            Button {
                                selected = s.number
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(s.name ?? "Season \(s.number)").font(.headline)
                                    Text(seasonLine(s)).font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 20).padding(.vertical, 14)
                                .background(selected == s.number ? Color.accentColor.opacity(0.35) : .clear, in: RoundedRectangle(cornerRadius: 14))
                            }
                            .rowButton()
                        }
                    }
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
                #if os(tvOS)
                .scrollClipDisabled()
                #endif

                OfflineSeasonButton(episodes: jfEpisodes.filter { $0.ParentIndexNumber == selected }, series: series)
                if loading {
                    ProgressView().frame(maxWidth: .infinity)
                } else if !episodes.isEmpty {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(episodes) { e in
                            let jf = jfEpisodes.first { $0.ParentIndexNumber == selected && $0.IndexNumber == e.number }
                            HStack(spacing: 12) {
                                EpisodeRow(e: e, jf: jf, play: play)
                                OfflineEpisodeButton(item: jf, series: series)
                            }
                        }
                    }
                    .padding(.horizontal, Metrics.gutter)
                }
            }
            .task(id: selected) { await loadEpisodes() }
            .onAppear { if selected == nil { selected = seasons.first?.number } }
        }
    }

    private func seasonLine(_ s: TitleMeta.Season) -> String {
        if let l = library.first(where: { $0.number == s.number }) {
            var p = ["\(l.in_library ?? 0)/\(l.episodes ?? s.episode_count ?? 0) in library"]
            if let d = l.downloading, d > 0 { p.append("\(d) downloading") }
            if l.keep_up_to_date == false { p.append("not wanted") }
            return p.joined(separator: " · ")
        }
        var p: [String] = []
        if let n = s.episode_count { p.append("\(n) episodes") }
        if let y = s.year { p.append(String(y)) }
        return p.joined(separator: " · ")
    }

    private func loadEpisodes() async {
        guard let n = selected, let c = app.client else { return }
        loading = true
        defer { loading = false }
        episodes = (try? await c.get("/metadata/show/\(tmdb.q)/seasons/\(n)", as: SeasonEpisodes.self))?.episodes ?? []
    }
}

struct EpisodeRow: View {
    let e: SeasonEpisodes.Episode
    var jf: JFItem? = nil
    var play: ((JFItem) -> Void)? = nil

    var body: some View {
        if let jf, let play {
            Button { play(jf) } label: { content.padding(14) }
                .rowButton(corner: 18)
                #if os(visionOS)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                #endif
        } else {
            content
                .panel(corner: 18, padding: 14)
                #if os(tvOS)
                .focusable()
                #endif
        }
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 20) {
            ZStack(alignment: .bottomLeading) {
                RemoteImage(path: e.still)
                if jf != nil {
                    Image(systemName: "play.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if let p = jf?.progress {
                    GeometryReader { g in
                        Capsule().fill(.white.opacity(0.3)).frame(height: 5)
                            .overlay(alignment: .leading) { Capsule().fill(Color.accentColor).frame(width: g.size.width * p, height: 5) }
                    }
                    .frame(height: 5)
                    .padding(8)
                }
            }
            .frame(width: Metrics.isPhone ? 130 : 220, height: Metrics.isPhone ? 73 : 124)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("\(e.number). \(e.name ?? "Episode \(e.number)")").font(.headline)
                    if jf?.UserData?.Played == true { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                }
                Text([e.air_day.flatMap { HADate.parse($0) }?.formatted(date: .abbreviated, time: .omitted), Fmt.runtime(e.runtime), jf == nil ? nil : "On Jellyfin"].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                if let o = e.overview { Text(o).font(.callout).lineLimit(3).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
