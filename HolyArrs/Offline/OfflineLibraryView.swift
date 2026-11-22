#if !os(tvOS)
import SwiftUI
import UIKit

/// The Offline page: what is downloaded to this device, grouped by show, with storage use and the running downloads.
/// Works with no server: everything it shows comes from the offline catalogue and artwork on the device.
struct OfflineLibraryView: View {
    /// True when the app started without reaching HolyArrs (shows the reconnect banner).
    var offline = false

    @AppStorage(OfflineQuality.storageKey) private var quality: OfflineQuality = .high
    @State private var confirmDeleteAll = false
    @State private var confirmWatched = false
    @State private var actionError: String?

    private var store: OfflineStore { .shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                VStack(alignment: .leading, spacing: 4) {
                    PageHeading(text: "Offline")
                    Text("Downloaded to this \(deviceName). Plays without a connection.")
                        .font(.callout).foregroundStyle(.secondary)
                        .padding(.horizontal, Metrics.gutter)
                }
                if offline { OfflineBanner() }
                ActionErrorBanner(message: $actionError)
                storagePanel

                if store.items.isEmpty {
                    EmptyNote(title: "Nothing downloaded yet", systemImage: "arrow.down.circle",
                              detail: "Open a movie or a show and choose Download to watch it without a connection.")
                }

                let active = store.items.filter { $0.isActive || $0.state == .failed }
                if !active.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(text: "Downloading", subtitle: "One at a time. Downloads keep going when the app is closed.")
                        ForEach(active) { OfflineActiveRow(rec: $0).padding(.horizontal, Metrics.gutter) }
                    }
                }

                let movies = store.items.filter { !$0.isEpisode && $0.state == .done }
                Shelf(title: "Movies", subtitle: summary(movies), items: movies) { rec in
                    OfflineMovieCard(rec: rec, play: play)
                }

                ForEach(showGroups, id: \.id) { g in
                    OfflineShowSection(show: g.show, episodes: g.episodes, play: play)
                }
            }
            .padding(.vertical, 20)
        }
        .onAppear { store.refreshFreeSpace() }
        .confirmationDialog("Delete every download on this \(deviceName)?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Delete all downloads", role: .destructive) { store.removeAll() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Remove \(store.watchedIDs.count) watched download\(store.watchedIDs.count == 1 ? "" : "s")?", isPresented: $confirmWatched, titleVisibility: .visible) {
            Button("Remove watched", role: .destructive) { store.removeWatched() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var deviceName: String {
        #if os(visionOS)
        "Vision Pro"
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
    }

    private var storagePanel: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) {
                storageText
                Spacer(minLength: 10)
                storageControls
            }
            VStack(alignment: .leading, spacing: 14) {
                storageText
                HStack(spacing: 14) { storageControls }
            }
        }
        .panel(corner: 22, padding: 20)
        .padding(.horizontal, Metrics.gutter)
    }

    private var storageText: some View {
        HStack(spacing: 14) {
            Image(systemName: "internaldrive").font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.usedBytes > 0 ? "\(Fmt.bytes(store.usedBytes)) used by downloads" : "No space used yet").font(.headline)
                if let free = store.freeSpace { Text("\(Fmt.bytes(free)) free on this \(deviceName)").font(.callout).foregroundStyle(.secondary) }
            }
        }
    }

    @ViewBuilder
    private var storageControls: some View {
        Picker("Quality", selection: $quality) {
            ForEach(OfflineQuality.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.menu)
        .fixedSize()
        Button {
            confirmWatched = true
        } label: {
            Label("Remove watched", systemImage: "eye.slash")
        }
        .buttonStyle(.bordered)
        .disabled(store.watchedIDs.isEmpty)
        Button(role: .destructive) {
            confirmDeleteAll = true
        } label: {
            Label("Delete all", systemImage: "trash")
        }
        .buttonStyle(.bordered)
        .disabled(store.items.isEmpty)
    }

    private struct ShowGroup {
        var id: String
        var show: OfflineShow
        var episodes: [OfflineItem]
    }

    private var showGroups: [ShowGroup] {
        let eps = store.items.filter { $0.isEpisode && $0.state == .done }
        let bySeries = Dictionary(grouping: eps) { $0.seriesID ?? $0.seriesName ?? "" }
        return bySeries.map { sid, list in
            let show = store.shows[sid] ?? OfflineShow(id: sid, name: list.first?.seriesName ?? "Show")
            return ShowGroup(id: sid, show: show, episodes: list.sorted { ($0.season ?? 0, $0.episode ?? 0) < ($1.season ?? 0, $1.episode ?? 0) })
        }
        .sorted { $0.show.name.localizedCaseInsensitiveCompare($1.show.name) == .orderedAscending }
    }

    private func summary(_ list: [OfflineItem]) -> String {
        let bytes = list.reduce(Int64(0)) { $0 + ($1.bytes ?? 0) }
        return [bytes > 0 ? Fmt.bytes(bytes) : nil].compactMap { $0 }.joined()
    }

    private func play(_ rec: OfflineItem, _ fromStart: Bool) {
        if let e = OfflinePlayback.play(rec, from: fromStart ? nil : rec.resumeSeconds) { actionError = e }
    }
}

/// "You're offline" with a way to try again.
struct OfflineBanner: View {
    @Environment(AppModel.self) private var app
    @State private var trying = false

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "wifi.slash").font(.title2).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Can't reach HolyArrs").font(.headline)
                Text("Your downloads still play. Watch progress is sent to Jellyfin when you're back online.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 10)
            Button {
                Task {
                    trying = true
                    await app.start()
                    trying = false
                }
            } label: {
                if trying { ProgressView() } else { Text("Try again") }
            }
            .buttonStyle(.borderedProminent)
            .disabled(trying)
        }
        .panel(corner: 22, padding: 20)
        .padding(.horizontal, Metrics.gutter)
    }
}

/// A downloaded movie: one tap plays (resuming), the context menu plays from the start or deletes.
struct OfflineMovieCard: View {
    let rec: OfflineItem
    let play: (OfflineItem, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                play(rec, false)
            } label: {
                ZStack(alignment: .bottomLeading) {
                    OfflineImage(file: rec.poster ?? rec.thumb, placeholder: rec.name)
                    if rec.played { WatchedMark().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(8) }
                    if let w = rec.watched { WatchBar(value: w).padding(10) }
                }
                .frame(width: Metrics.posterWidth, height: Metrics.posterHeight)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous))
            }
            .cardButton()
            .contextMenu { OfflineItemMenu(rec: rec, play: play) }
            VStack(alignment: .leading, spacing: 2) {
                Text(rec.name).font(.callout.weight(.medium)).lineLimit(1)
                Text([rec.year.map(String.init), rec.bytes.map(Fmt.bytes), rec.resumeSeconds.map { "\(Fmt.clock($0)) in" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: Metrics.posterWidth, alignment: .leading)
        }
    }
}

/// A show's downloaded episodes by season, with delete for the season and the show.
struct OfflineShowSection: View {
    let show: OfflineShow
    let episodes: [OfflineItem]
    let play: (OfflineItem, Bool) -> Void
    @State private var confirmShow = false

    private var store: OfflineStore { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 18) {
                OfflineImage(file: show.poster, placeholder: show.name)
                    .frame(width: 70, height: 105)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(show.name).font(.title2.bold())
                    let bytes = episodes.reduce(Int64(0)) { $0 + ($1.bytes ?? 0) }
                    Text("\(episodes.count) episode\(episodes.count == 1 ? "" : "s") · \(Fmt.bytes(bytes))").font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 10)
                if let next = episodes.first(where: { !$0.played }) ?? episodes.first {
                    Button {
                        play(next, false)
                    } label: {
                        Label(next.resumeSeconds != nil ? "Resume \(next.season.map { "S\($0)" } ?? "")E\(next.episode ?? 0)" : "Play \(next.season.map { "S\($0)" } ?? "")E\(next.episode ?? 0)", systemImage: "play.fill")
                    }
                    .primaryAction()
                }
                Button(role: .destructive) {
                    confirmShow = true
                } label: {
                    Label("Delete show", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .labelStyle(.iconOnly)
            }
            .padding(.horizontal, Metrics.gutter)

            let seasons = Dictionary(grouping: episodes) { $0.season ?? 0 }.sorted { $0.key < $1.key }
            ForEach(seasons, id: \.key) { season, list in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(season == 0 ? "Specials" : "Season \(season)").font(.headline)
                        Spacer()
                        Button(role: .destructive) {
                            store.removeSeason(series: show.id, season: list.first?.season)
                        } label: {
                            Label("Delete season", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    ForEach(list) { OfflineEpisodeRow(rec: $0, play: play) }
                }
                .padding(.horizontal, Metrics.gutter)
            }
        }
        .confirmationDialog("Delete every downloaded episode of \(show.name)?", isPresented: $confirmShow, titleVisibility: .visible) {
            Button("Delete \(episodes.count) episode\(episodes.count == 1 ? "" : "s")", role: .destructive) { store.removeShow(show.id) }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct OfflineEpisodeRow: View {
    let rec: OfflineItem
    let play: (OfflineItem, Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button { play(rec, false) } label: { content.padding(12) }
                .rowButton(corner: 18)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contextMenu { OfflineItemMenu(rec: rec, play: play) }
            Menu {
                OfflineItemMenu(rec: rec, play: play)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.button)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
        }
    }

    private var content: some View {
        HStack(spacing: 16) {
            ZStack(alignment: .bottomLeading) {
                OfflineImage(file: rec.thumb, placeholder: nil)
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let w = rec.watched { WatchBar(value: w).padding(6) }
            }
            .frame(width: 160, height: 90)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("\(rec.episode ?? 0). \(rec.name)").font(.headline).lineLimit(1)
                    if rec.played { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                }
                Text([rec.runtimeSeconds.map { Fmt.duration($0) }, rec.bytes.map(Fmt.bytes), rec.resumeSeconds.map { "\(Fmt.clock($0)) in" }]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                if let o = rec.overview { Text(o).font(.callout).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Play, play from start and delete, for context menus and the row's menu button.
struct OfflineItemMenu: View {
    let rec: OfflineItem
    let play: (OfflineItem, Bool) -> Void

    var body: some View {
        Button { play(rec, false) } label: { Label(rec.resumeSeconds != nil ? "Resume" : "Play", systemImage: "play.fill") }
        if rec.resumeSeconds != nil {
            Button { play(rec, true) } label: { Label("Play from start", systemImage: "arrow.counterclockwise") }
        }
        Button(role: .destructive) { OfflineStore.shared.remove([rec.id]) } label: { Label("Delete download", systemImage: "trash") }
    }
}

/// A queued, running, paused or failed download with its controls.
struct OfflineActiveRow: View {
    let rec: OfflineItem

    private var store: OfflineStore { .shared }

    var body: some View {
        HStack(spacing: 16) {
            OfflineImage(file: rec.thumb ?? rec.poster, placeholder: nil)
                .frame(width: 120, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(rec.isEpisode ? "\(rec.seriesName ?? "") · \(rec.title)" : rec.name).font(.headline).lineLimit(1)
                Text(status).font(.caption).foregroundStyle(rec.state == .failed ? .yellow : .secondary).lineLimit(2)
                if rec.state != .failed { ProgressView(value: rec.progress).tint(rec.state == .paused ? Color.secondary : Color.accentColor) }
            }
            Spacer(minLength: 10)
            switch rec.state {
            case .downloading, .queued:
                Button { store.pause(rec.id) } label: { Label("Pause", systemImage: "pause.fill") }
                    .labelStyle(.iconOnly)
            case .paused, .failed:
                Button { store.resume(rec.id) } label: { Label(rec.state == .failed ? "Try again" : "Resume", systemImage: rec.state == .failed ? "arrow.clockwise" : "play.fill") }
                    .labelStyle(.iconOnly)
            case .done:
                EmptyView()
            }
            Button(role: .destructive) { store.remove([rec.id]) } label: { Label("Cancel", systemImage: "xmark") }
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .panel(corner: 18, padding: 14)
    }

    private var status: String {
        let pct = "\(Int(rec.progress * 100))%"
        let size = [rec.bytes.map(Fmt.bytes), rec.quality.estimate(seconds: rec.runtimeSeconds).map { "about \(Fmt.bytes($0))" }]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " of ")
        switch rec.state {
        case .queued: return "Waiting · \(rec.quality.label)"
        case .downloading: return ["Downloading \(pct)", size, rec.quality.label].filter { !$0.isEmpty }.joined(separator: " · ")
        case .paused: return "Paused at \(pct)"
        case .failed: return rec.error ?? "The download failed."
        case .done: return "Downloaded"
        }
    }
}

/// A picture from the offline artwork folder, with a quiet placeholder.
struct OfflineImage: View {
    let file: String?
    var placeholder: String?
    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(.quaternary)
                        .overlay {
                            if let placeholder {
                                Text(placeholder).font(.headline).multilineTextAlignment(.center).padding().foregroundStyle(.secondary)
                            }
                        }
                }
            }
            .clipped()
            .task(id: file) { image = await OfflineImageCache.load(file) }
    }
}

enum OfflineImageCache {
    private static let cache = NSCache<NSString, UIImage>()

    static func load(_ file: String?) async -> UIImage? {
        guard let file else { return nil }
        if let hit = cache.object(forKey: file as NSString) { return hit }
        let url = OfflinePaths.artwork.appendingPathComponent(file)
        let img = await Task.detached(priority: .utility) { UIImage(contentsOfFile: url.path)?.preparingForDisplay() }.value
        if let img { cache.setObject(img, forKey: file as NSString) }
        return img
    }
}

private struct WatchBar: View {
    let value: Double
    var body: some View {
        GeometryReader { g in
            Capsule().fill(.white.opacity(0.3))
                .overlay(alignment: .leading) { Capsule().fill(Color.accentColor).frame(width: g.size.width * value) }
        }
        .frame(height: 5)
    }
}

private struct WatchedMark: View {
    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.title3)
            .foregroundStyle(.white, .green)
    }
}
#endif
