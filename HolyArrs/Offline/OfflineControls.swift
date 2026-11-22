import SwiftUI

// Download controls placed on title pages and in the Library. Each is an EmptyView on tvOS, so the call sites
// in shared views need no platform checks.

/// Download for a movie, next to Play on its title page.
struct OfflineDownloadButton: View {
    let item: JFItem?

    var body: some View {
        #if !os(tvOS)
        if let item { OfflineItemControl(item: item) }
        #endif
    }
}

/// Download for the selected season of a show.
struct OfflineSeasonButton: View {
    let episodes: [JFItem]
    var series: JFItem?

    var body: some View {
        #if !os(tvOS)
        if !episodes.isEmpty { OfflineSeasonControl(episodes: episodes, series: series) }
        #endif
    }
}

/// A round download button beside an episode row.
struct OfflineEpisodeButton: View {
    let item: JFItem?
    var series: JFItem?

    var body: some View {
        #if !os(tvOS)
        if let item { OfflineItemControl(item: item, series: series, compact: true) }
        #endif
    }
}

/// The way into the Offline page from the Library.
struct OfflineLibraryLink: View {
    var body: some View {
        #if !os(tvOS)
        OfflineLibraryLinkCard()
        #endif
    }
}

#if !os(tvOS)
private struct OfflineLibraryLinkCard: View {
    private var store: OfflineStore { .shared }

    var body: some View {
        NavigationLink {
            OfflineLibraryView()
        } label: {
            HStack(spacing: 16) {
                Image(systemName: "arrow.down.circle").font(.title)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Offline").font(.headline)
                    Text(summary).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .rowButton(corner: 22)
        .padding(.horizontal, Metrics.gutter)
    }

    private var summary: String {
        let done = store.items.filter { $0.state == .done }
        let running = store.items.filter(\.isActive).count
        guard !store.items.isEmpty else { return "Download movies and episodes to watch without a connection." }
        let movies = done.filter { !$0.isEpisode }.count
        let eps = done.count - movies
        var parts: [String] = []
        if movies > 0 { parts.append("\(movies) movie\(movies == 1 ? "" : "s")") }
        if eps > 0 { parts.append("\(eps) episode\(eps == 1 ? "" : "s")") }
        if store.usedBytes > 0 { parts.append(Fmt.bytes(store.usedBytes)) }
        if running > 0 { parts.append("\(running) downloading") }
        return parts.joined(separator: " · ")
    }
}

/// Download, progress, pause, resume, cancel and delete for one movie or episode.
struct OfflineItemControl: View {
    @Environment(AppModel.self) private var app
    let item: JFItem
    var series: JFItem?
    var compact = false
    @State private var error: String?

    private var store: OfflineStore { .shared }

    var body: some View {
        let rec = store.item(item.Id)
        Group {
            switch rec?.state {
            case nil:
                Menu {
                    Section("Download quality") {
                        ForEach(OfflineQuality.allCases) { q in
                            Button { start(q) } label: { Text(qualityLine(q)) }
                        }
                    }
                } label: {
                    label("Download", "arrow.down.circle", rec)
                } primaryAction: {
                    start(.preferred)
                }
            case .queued?, .downloading?:
                Menu {
                    Button { store.pause(item.Id) } label: { Label("Pause", systemImage: "pause.fill") }
                    Button(role: .destructive) { store.remove([item.Id]) } label: { Label("Cancel download", systemImage: "xmark") }
                } label: {
                    label(rec?.state == .queued ? "Waiting" : "\(Int((rec?.progress ?? 0) * 100))%", "arrow.down.circle.dotted", rec)
                }
            case .paused?:
                Menu {
                    Button { store.resume(item.Id) } label: { Label("Resume", systemImage: "play.fill") }
                    Button(role: .destructive) { store.remove([item.Id]) } label: { Label("Cancel download", systemImage: "xmark") }
                } label: {
                    label("Paused \(Int((rec?.progress ?? 0) * 100))%", "pause.circle", rec)
                }
            case .failed?:
                Menu {
                    Button { store.resume(item.Id) } label: { Label("Try again", systemImage: "arrow.clockwise") }
                    Button(role: .destructive) { store.remove([item.Id]) } label: { Label("Remove", systemImage: "xmark") }
                } label: {
                    label("Download failed", "exclamationmark.circle", rec)
                }
            case .done?:
                Menu {
                    Button(role: .destructive) { store.remove([item.Id]) } label: { Label("Delete download", systemImage: "trash") }
                } label: {
                    label(rec?.bytes.map { "Downloaded · \(Fmt.bytes($0))" } ?? "Downloaded", "checkmark.circle.fill", rec)
                }
            }
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .modifier(CompactShape(compact: compact))
        .disabled(app.jellyfinClient == nil && rec == nil)
        .alert("Could not download", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    @ViewBuilder
    private func label(_ text: String, _ icon: String, _ rec: OfflineItem?) -> some View {
        if compact {
            ZStack {
                if let rec, rec.state == .downloading || rec.state == .paused {
                    Circle().stroke(.white.opacity(0.2), lineWidth: 3)
                    Circle().trim(from: 0, to: rec.progress).stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                    Image(systemName: rec.state == .paused ? "pause.fill" : "stop.fill").font(.caption2)
                } else {
                    Image(systemName: icon).foregroundStyle(rec?.state == .done ? Color.green : Color.primary)
                }
            }
            .frame(width: 26, height: 26)
            .accessibilityLabel(Text(text))
        } else {
            Label(text, systemImage: icon)
        }
    }

    private func qualityLine(_ q: OfflineQuality) -> String {
        let secs = item.RunTimeTicks.map { Double($0) / 10_000_000 }
        if let b = q.estimate(seconds: secs) { return "\(q.label), about \(Fmt.bytes(b))" }
        return q.label
    }

    private func start(_ q: OfflineQuality) {
        guard let client = app.jellyfinClient else {
            error = "Connect Jellyfin in Settings to download."
            return
        }
        Task { await store.download([item], series: series, client: client, quality: q) }
    }
}

private struct CompactShape: ViewModifier {
    let compact: Bool
    func body(content: Content) -> some View {
        if compact { content.buttonBorderShape(.circle) } else { content }
    }
}

/// Download a whole season (the episodes that are on Jellyfin), with progress and delete.
struct OfflineSeasonControl: View {
    @Environment(AppModel.self) private var app
    let episodes: [JFItem]
    var series: JFItem?

    private var store: OfflineStore { .shared }

    var body: some View {
        let recs = episodes.compactMap { store.item($0.Id) }
        let done = recs.filter { $0.state == .done }.count
        let active = recs.filter(\.isActive)
        let missing = episodes.filter { store.item($0.Id) == nil }
        let season = episodes.first?.ParentIndexNumber
        HStack(spacing: 14) {
            if !active.isEmpty {
                Menu {
                    Button { active.forEach { store.pause($0.id) } } label: { Label("Pause", systemImage: "pause.fill") }
                    Button { active.filter { $0.state == .paused }.forEach { store.resume($0.id) } } label: { Label("Resume", systemImage: "play.fill") }
                    Button(role: .destructive) { store.remove(active.map(\.id)) } label: { Label("Cancel downloads", systemImage: "xmark") }
                } label: {
                    Label("Downloading \(done) of \(recs.count)", systemImage: "arrow.down.circle.dotted")
                }
            } else if !missing.isEmpty {
                Menu {
                    Section("Download quality") {
                        ForEach(OfflineQuality.allCases) { q in
                            Button(q.label) { start(missing, q) }
                        }
                    }
                } label: {
                    Label(done > 0 ? "Download \(missing.count) more" : "Download season\(season.map { " \($0)" } ?? "")", systemImage: "arrow.down.circle")
                } primaryAction: {
                    start(missing, .preferred)
                }
            } else {
                Label("Season downloaded", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
            if done > 0, let sid = episodes.first?.SeriesId {
                Button(role: .destructive) {
                    store.removeSeason(series: sid, season: season)
                } label: {
                    Label("Delete season download", systemImage: "trash")
                }
                .labelStyle(.iconOnly)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .disabled(app.jellyfinClient == nil && recs.isEmpty)
        .padding(.horizontal, Metrics.gutter)
    }

    private func start(_ list: [JFItem], _ q: OfflineQuality) {
        guard let client = app.jellyfinClient else { return }
        Task { await store.download(list, series: series, client: client, quality: q) }
    }
}
#endif
