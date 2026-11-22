import SwiftUI

/// The media browser: Continue watching and Next up from Jellyfin (they play right away), then the HolyArrs library.
struct LibraryView: View {
    @Environment(AppModel.self) private var app

    enum Kind: String, CaseIterable, Identifiable {
        case movies, shows
        var id: String { rawValue }
        var label: String { self == .movies ? "Movies" : "Shows" }
    }
    enum Sort: String, CaseIterable, Identifiable {
        case added = "Recently added", name = "Name", year = "Year"
        var id: String { rawValue }
    }

    @State private var kind: Kind = .movies
    @State private var sort: Sort = .added
    @State private var filter = ""
    @State private var titles: Loadable<[LibraryTitle]> = .loading
    @State private var resume: [JFItem] = []
    @State private var nextUp: [JFItem] = []
    @State private var showConnect = false
    @State private var actionError: String?

    var body: some View {
        PageScrollView {
            VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                ActionErrorBanner(message: $actionError)
                OfflineLibraryLink()
                if let j = app.jellyfinClient {
                    PlayShelf(title: "Continue watching", items: resume, client: j) { await play($0, resume: true) }
                    PlayShelf(title: "Next up", items: nextUp, client: j) { await play($0, resume: true) }
                } else {
                    HStack(spacing: 16) {
                        Image(systemName: "play.circle").font(.title)
                        VStack(alignment: .leading) {
                            Text("Play your library here").font(.headline)
                            Text("Connect your Jellyfin account to watch, resume and see Next up.").font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Connect Jellyfin") { showConnect = true }.buttonStyle(.borderedProminent)
                    }
                    .panel(corner: 22, padding: 20)
                    .padding(.horizontal, Metrics.gutter)
                }

                controls

                switch titles {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity, minHeight: 300)
                case let .failed(m):
                    ErrorView(message: m) { await loadTitles() }.frame(minHeight: 300)
                case let .loaded(all):
                    let shown = visible(all)
                    Text("\(shown.count) \(kind.label.lowercased())").font(.caption).foregroundStyle(.secondary).padding(.horizontal, Metrics.gutter)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: Metrics.posterWidth), spacing: Metrics.cardSpacing, alignment: .top)], spacing: Metrics.cardSpacing) {
                        ForEach(shown) { t in
                            PosterCard(title: t.name ?? "", subtitle: subtitle(t), image: t.poster ?? app.posterFallback(kind: t.kind, tmdb: t.ids?.tmdb?.value, titleID: t.id) ?? t.backdrop, route: .libraryTitle(t.id),
                                       kind: t.kind, tmdb: t.ids?.tmdb?.value, titleID: t.id, backdrop: t.backdrop)
                        }
                    }
                    .padding(.horizontal, Metrics.gutter)
                }
            }
            .padding(.vertical, 20)
        }
        .task { await loadTitles() }
        .task(id: app.jellyfin?.userID) { await loadJellyfin() }
        .refreshable {
            await loadTitles()
            await loadJellyfin()
        }
        .sheet(isPresented: $showConnect) {
            JellyfinConnectSheet {
                showConnect = false
                Task { await loadJellyfin() }
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 20) {
                Picker("Kind", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)
                Picker("Sort", selection: $sort) {
                    ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                }
                #if os(visionOS)
                .pickerStyle(.menu)
                #endif
                .fixedSize()
                Spacer()
            }
            TextField("Filter by name", text: $filter)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(maxWidth: 520)
        }
        .padding(.horizontal, Metrics.gutter)
    }

    private func visible(_ all: [LibraryTitle]) -> [LibraryTitle] {
        let k = kind == .movies ? "movie" : "show"
        let f = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let list = all.filter { $0.kind == k && (f.isEmpty || ($0.name ?? "").lowercased().contains(f)) }
        switch sort {
        case .added: return list.sorted { ($0.added_at ?? "") > ($1.added_at ?? "") }
        case .name: return list.sorted { ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending }
        case .year: return list.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        }
    }

    private func subtitle(_ t: LibraryTitle) -> String? {
        if t.kind == "show", let s = t.show {
            if let i = s.in_library, let e = s.episodes { return "\(i)/\(e) episodes" }
        }
        return t.year.map(String.init)
    }

    private func loadTitles() async {
        guard let c = app.client else { return }
        struct Answer: Decodable { var titles: [LibraryTitle]? }
        do {
            let a: Answer = try await c.get("/titles")
            titles = .loaded(a.titles ?? [])
        } catch is CancellationError {
        } catch {
            if titles.value == nil { titles = .failed(error.localizedDescription) }
        }
    }

    private func loadJellyfin() async {
        guard let j = app.jellyfinClient else { resume = []; nextUp = []; return }
        async let r = try? j.resume()
        async let n = try? j.nextUp()
        resume = await r ?? []
        nextUp = await n ?? []
    }

    private func play(_ it: JFItem, resume: Bool) async {
        guard let j = app.jellyfinClient else { return }
        do {
            let fresh = (try? await j.item(it.Id)) ?? it
            if await OfflineHooks.playIfDownloaded(fresh, resume: resume) { return }
            try await Player.play(fresh, client: j, from: resume ? fresh.resumeSeconds : nil)
        } catch {
            actionError = "Could not start playback: \(error.localizedDescription)"
        }
    }
}

/// A row of wide Jellyfin cards that start playback when chosen.
struct PlayShelf: View {
    let title: String
    let items: [JFItem]
    let client: JellyfinClient
    let play: (JFItem) async -> Void

    var body: some View {
        Shelf(title: title, items: items) { it in
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    Task { await play(it) }
                } label: {
                    ZStack(alignment: .bottomLeading) {
                        RemoteImage(path: client.wideImage(it))
                        LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                        Image(systemName: "play.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        if let p = it.progress {
                            GeometryReader { g in
                                Capsule().fill(.white.opacity(0.3))
                                    .overlay(alignment: .leading) { Capsule().fill(Color.accentColor).frame(width: g.size.width * p) }
                            }
                            .frame(height: 5)
                            .padding(12)
                        }
                    }
                    .frame(width: Metrics.wideWidth, height: Metrics.wideHeight)
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous))
                }
                .cardButton()
                VStack(alignment: .leading, spacing: 2) {
                    Text(it.isEpisode ? (it.SeriesName ?? "") : (it.Name ?? "")).font(.callout.weight(.medium)).lineLimit(1)
                    Text(it.isEpisode ? it.displayTitle : (it.ProductionYear.map(String.init) ?? "")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(width: Metrics.wideWidth, alignment: .leading)
            }
        }
    }
}
