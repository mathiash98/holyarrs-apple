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
    /// Active downloads for this title, refreshed while any are running.
    @State private var downloads: [DownloadRow] = []
    @State private var starting = false
    /// A movie ask or its removal is being sent (one click asks, a second click takes the ask back).
    @State private var asking = false

    var body: some View {
        LoadView(state: state, retry: load) { m in
            PageScrollView {
                VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                    header(m)
                    ActionErrorBanner(message: $actionError)
                    if let notice {
                        Label(notice, systemImage: "checkmark.circle.fill").foregroundStyle(.green).padding(.horizontal, Metrics.gutter)
                    }
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
            #if os(tvOS)
            // Start the page at the very top of the screen (no room kept for the hidden tab bar).
            .ignoresSafeArea(edges: .top)
            #endif
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
        #if os(tvOS)
        // Netflix-style: the picture or trailer fills the screen, so the tab bar is hidden on title pages.
        .toolbar(.hidden, for: .tabBar)
        #endif
        .task { if state.value == nil { await load() } }
        .task(id: state.value?.titleID) { await watchDownloads() }
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
                                            tagline: m.meta?.tagline, meta: [metaLine(m)], pills: pills(m), downloads: myMovieAsk(m) == nil ? downloads : [],
                                            overview: m.meta?.overview ?? m.lib?.overview),
                  height: headerHeight, overviewLines: overviewLines) {
            actions(m)
        }
        #if os(tvOS)
        .ignoresSafeArea()
        #else
        .ignoresSafeArea(edges: .top)
        #endif
        .padding(.bottom, -70)
    }

    /// Full screen on Apple TV (the trailer plays behind the text, like Netflix); a tall hero elsewhere.
    private var headerHeight: CGFloat {
        #if os(tvOS)
        BillboardMetrics.fullScreen
        #else
        BillboardMetrics.height + 60
        #endif
    }

    private var overviewLines: Int {
        #if os(tvOS)
        4
        #else
        6
        #endif
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
        Group {
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
                    .secondaryAction()
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
                .secondaryAction()
            }
            if let url = m.swiftfin {
                Button {
                    openURL(url) { ok in if !ok { actionError = "Could not open Swiftfin. Is it installed and signed in to this Jellyfin user?" } }
                } label: {
                    Label("Swiftfin", systemImage: "play.fill")
                }
                .secondaryAction()
            }
            if let mine = myMovieAsk(m) {
                // Like Netflix's My List: a check mark with the ask's status; one click takes the ask back.
                Button {
                    Task { await removeAsk(mine) }
                } label: {
                    AskedLabel(text: askedLabel(mine), progress: downloads.first?.progress)
                }
                .secondaryAction()
                .disabled(asking)
            } else if canAsk(m) {
                // One click asks for the movie, or for every season of a show.
                Button {
                    Task { await askTitle(m) }
                } label: {
                    Label("Ask", systemImage: "plus")
                }
                .secondaryAction()
                .disabled(asking || !mayAsk)
            }
            if m.kind == "show", m.tmdb != nil, m.meta?.never_add != true {
                Button {
                    showAsk = true
                } label: {
                    Label("Choose seasons", systemImage: "checklist")
                }
                .secondaryAction()
                .disabled(asking || !mayAsk)
            }
            if let key = m.meta?.trailerKey {
                Button {
                    Task { await playTrailer(m, key: key) }
                } label: {
                    Label("Trailer", systemImage: "play.rectangle")
                }
                .secondaryAction()
            }
        }
    }

    private var mayAsk: Bool { app.me?.can("ask") == true || app.me?.isOwner == true }

    /// My own waiting or approved ask (shown as a toggled "Asked" button): a movie not on disk yet, or a show.
    private func myMovieAsk(_ m: Model) -> AskBrief? {
        guard m.kind == "show" || m.lib?.hasFiles != true, let a = m.ask, a.mine == true, a.id != nil,
              a.state == "asked" || a.state == "approved" else { return nil }
        return a
    }

    /// Asks straight away: the movie, or every season of a show (Choose seasons is the other way).
    private func askTitle(_ m: Model) async {
        guard let c = app.client, let tmdb = m.tmdb else { return }
        asking = true
        defer { asking = false }
        do {
            let _: AskAnswer = try await c.post("/asks", body: AskBody(id: "tmdb:\(tmdb)", kind: m.kind))
            await load()
        } catch {
            actionError = "Could not ask for \(m.name): \(error.localizedDescription)"
        }
    }

    /// Takes my ask back, the same way as the Requests page: a waiting ask through /asks/remove, any other by id.
    private func removeAsk(_ a: AskBrief) async {
        guard let c = app.client, let id = a.id else { return }
        asking = true
        defer { asking = false }
        do {
            if a.state == "asked" {
                try await c.post("/asks/remove", body: RemoveAsksBody(ids: [id]))
            } else {
                try await c.delete("/asks/\(id)")
            }
            await load()
        } catch {
            actionError = "Could not take the ask back: \(error.localizedDescription)"
        }
    }

    /// "Asked", plus where the ask is: waiting for approval, approved, downloading.
    private func askedLabel(_ a: AskBrief) -> String {
        if let d = downloads.first {
            var p = ["Downloading", String(format: "%.0f%%", (d.progress ?? 0) * 100)]
            if let eta = d.eta { p.append("\(Fmt.duration(eta)) left") }
            if d.state != "downloading" { p[0] = d.label ?? "Waiting" }
            return p.joined(separator: " · ")
        }
        let s = a.state_label ?? a.state?.capitalized ?? ""
        return s.isEmpty ? "Asked" : "Asked · \(s)"
    }

    private func canAsk(_ m: Model) -> Bool {
        guard m.tmdb != nil, m.meta?.never_add != true else { return false }
        if let a = m.ask, a.mine == true, a.state == "asked" || a.state == "approved" { return false }
        // A movie can be asked for until it is on disk (also when it is wanted in the library without an ask).
        if m.kind == "movie" { return m.lib?.hasFiles != true }
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

    /// Status as short pills in the billboard: what is on disk, the file's traits, downloads, asks and progress.
    private func pills(_ m: Model) -> [String] {
        var out: [String] = []
        if let lib = m.lib {
            if lib.kind == "show", let sh = lib.show, let i = sh.in_library, let e = sh.episodes {
                out.append(i == 0 ? "Not downloaded yet" : i >= e ? "All \(e) episodes" : "\(i) of \(e) episodes")
            } else if lib.hasFiles {
                out.append("In library")
            } else if downloads.isEmpty {
                out.append(lib.slots?.first?.state_label ?? "Wanted")
            }
            if lib.isDownloading && downloads.isEmpty { out.append("Downloading") }
        } else if m.inLibrary {
            out.append("In library")
        }
        if let fq = m.lib?.fileQuality {
            if app.quality(kind: m.kind, tmdb: m.tmdb, titleID: m.titleID) == nil { out.insert(fq.label, at: 0) }
            out += fq.detail.split(separator: "·").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        // My own movie ask already shows on the Asked button.
        if let a = m.ask, let label = a.state_label ?? a.state, m.lib?.hasFiles != true, myMovieAsk(m) == nil {
            out.append("Asked · \(label)")
        }
        if m.kind == "movie", let p = m.jf?.progress {
            out.append("\(Int(p * 100))% watched")
        }
        return out
    }

    /// Polls the Downloads list for this title: every 4 seconds while something downloads, once otherwise.
    private func watchDownloads() async {
        guard let c = app.client else { return }
        while !Task.isCancelled {
            guard let m = state.value, let lib = m.lib, !(lib.kind == "movie" && lib.hasFiles) || lib.isDownloading else {
                downloads = []
                return
            }
            let had = !downloads.isEmpty
            if let a: DownloadsAnswer = try? await c.get("/downloads/view?limit=200") {
                downloads = (a.downloads ?? []).filter { $0.title_id == lib.id && !$0.isDone }
            }
            if had && downloads.isEmpty {
                // Finished: reload so Play shows up.
                await load()
                return
            }
            if downloads.isEmpty {
                // My ask is waiting for a download to start: look again now and then.
                guard myMovieAsk(m) != nil else { return }
                try? await Task.sleep(for: .seconds(15))
                continue
            }
            try? await Task.sleep(for: .seconds(4))
        }
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
                PageScrollView(.horizontal) {
                    HStack(spacing: Metrics.cardSpacing / 2) {
                        ForEach(seasons) { s in
                            Button {
                                selected = s.number
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(s.name ?? "Season \(s.number)").font(.xHeadline)
                                    Text(seasonLine(s)).font(.xCaption).foregroundStyle(.secondary)
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
                        .font(.xLargeTitle)
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
                    Text("\(e.number). \(e.name ?? "Episode \(e.number)")").font(.xHeadline)
                    if jf?.UserData?.Played == true { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                }
                Text([e.air_day.flatMap { HADate.parse($0) }?.formatted(date: .abbreviated, time: .omitted), Fmt.runtime(e.runtime), jf == nil ? nil : "On Jellyfin"].compactMap { $0 }.joined(separator: " · "))
                    .font(.xCaption).foregroundStyle(.secondary)
                if let o = e.overview { Text(o).font(.xCallout).lineLimit(3).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The Asked button's label: a check mark and the ask's status, with a thin progress bar while it downloads.
private struct AskedLabel: View {
    let text: String
    let progress: Double?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark")
            VStack(alignment: .leading, spacing: 6) {
                Text(text).lineLimit(1)
                if let progress {
                    ProgressView(value: min(max(progress, 0), 1))
                        .tint(.green)
                        .frame(width: 220)
                }
            }
        }
    }
}
