import SwiftUI

/// Downloads: a live list that refreshes every few seconds while visible, plus Decide, History and Turned down.
struct DownloadsView: View {
    @Environment(AppModel.self) private var app
    @State private var state: Loadable<DownloadsAnswer> = .loading
    @State private var showAllFinished = false
    @State private var chosen: DownloadRow?
    @State private var actionError: String?
    @State private var decideCount = 0

    var body: some View {
        PageScrollView {
            VStack(alignment: .leading, spacing: 24) {
                subNav
                ActionErrorBanner(message: $actionError)
                switch state {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity, minHeight: 300)
                case let .failed(m):
                    ErrorView(message: m) { await load() }.frame(minHeight: 300)
                case let .loaded(d):
                    content(d)
                }
            }
            .padding(.vertical, 20)
        }
        .task {
            // Refreshes while the tab is visible; SwiftUI cancels this when the view goes away.
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(3))
            }
        }
        .task { await loadDecideCount() }
        .confirmationDialog(chosen?.title ?? chosen?.name ?? "", isPresented: Binding(get: { chosen != nil }, set: { if !$0 { chosen = nil } }), titleVisibility: .visible, presenting: chosen) { row in
            if let id = row.title_id { NavigationLink("Open title", value: Route.libraryTitle(id)) }
            if let id = row.downloadID, id > 0, row.can_act == true {
                if !row.isDone { Button("Mark failed and search again") { Task { await act("/downloads/\(id)/mark-failed") } } }
                Button("Remove from downloader", role: .destructive) { Task { await remove(id) } }
            } else if let dl = row.downloader_id, let h = row.hash, !h.isEmpty, row.can_act == true {
                // Items the downloader holds directly (id 0) are acted on by info hash.
                let base = "/downloaders/\(dl)/items/\(h)"
                if row.state == "paused" { Button("Resume") { Task { await act("\(base)/resume") } } }
                else if !row.isDone { Button("Pause") { Task { await act("\(base)/pause") } } }
                Button("Remove from downloader", role: .destructive) { Task { await act("\(base)/remove") } }
            }
            Button("Close", role: .cancel) {}
        } message: { row in
            Text(row.name ?? "")
        }
    }

    private var subNav: some View {
        HStack(spacing: 16) {
            NavigationLink(value: Route.decide) {
                Label(decideCount > 0 ? "Decide (\(decideCount))" : "Decide", systemImage: "questionmark.circle")
                    .padding(.horizontal, 18).padding(.vertical, 10)
            }
            .rowButton()
            NavigationLink(value: Route.history) {
                Label("History", systemImage: "clock.arrow.circlepath").padding(.horizontal, 18).padding(.vertical, 10)
            }
            .rowButton()
            NavigationLink(value: Route.turnedDown) {
                Label("Turned down", systemImage: "hand.thumbsdown").padding(.horizontal, 18).padding(.vertical, 10)
            }
            .rowButton()
            Spacer()
        }
        .padding(.horizontal, Metrics.gutter)
    }

    @ViewBuilder
    private func content(_ d: DownloadsAnswer) -> some View {
        let rows = d.downloads ?? []
        let active = rows.filter { !$0.isDone }
        let finished = rows.filter(\.isDone)
        HStack(spacing: 24) {
            Label(Fmt.speed(d.totals?.speed).isEmpty ? "Idle" : Fmt.speed(d.totals?.speed), systemImage: "arrow.down")
            if let up = d.totals?.up_speed, up > 0 { Label(Fmt.speed(up), systemImage: "arrow.up") }
            ForEach(d.clients ?? []) { c in
                Label(c.name ?? "Downloader", systemImage: c.health == "ok" ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(c.health == "ok" ? .green : .orange)
            }
            Spacer()
        }
        .font(.headline)
        .panel(corner: 20, padding: 16)
        .padding(.horizontal, Metrics.gutter)

        SectionTitle(text: "Downloading", subtitle: active.isEmpty ? "Nothing is downloading right now." : "\(active.count) active")
        if !active.isEmpty {
            LazyVStack(spacing: 12) {
                ForEach(active) { r in
                    Button { chosen = r } label: { DownloadRowView(row: r) }.rowButton(corner: 20)
                }
            }
            .padding(.horizontal, Metrics.gutter)
        }
        if !finished.isEmpty {
            SectionTitle(text: "Finished", subtitle: "\(finished.count) in the downloader")
            LazyVStack(spacing: 12) {
                ForEach(showAllFinished ? finished : Array(finished.prefix(15))) { r in
                    Button { chosen = r } label: { DownloadRowView(row: r) }.rowButton(corner: 20)
                }
            }
            .padding(.horizontal, Metrics.gutter)
            if !showAllFinished && finished.count > 15 {
                Button { showAllFinished = true } label: {
                    Label("Show all \(finished.count)", systemImage: "chevron.down").frame(maxWidth: .infinity).padding()
                }
                .rowButton()
                .padding(.horizontal, Metrics.gutter)
            }
        }
    }

    private func load() async {
        guard let c = app.client else { return }
        do {
            state = .loaded(try await c.get("/downloads/view?limit=200"))
        } catch is CancellationError {
        } catch {
            if state.value == nil { state = .failed(error.localizedDescription) }
        }
    }

    private func loadDecideCount() async {
        guard let c = app.client else { return }
        let d = (try? await c.get("/needs-decision", as: DecisionsAnswer.self))?.count ?? 0
        let m = (try? await c.get("/downloads/matches", as: MatchesAnswer.self))?.matches?.count ?? 0
        decideCount = d + m
    }

    private func act(_ path: String) async {
        guard let c = app.client else { return }
        do { try await c.post(path); await load() } catch { actionError = error.localizedDescription }
    }

    private struct RemoveBody: Encodable { var delete_files: Bool }
    private func remove(_ id: Int) async {
        guard let c = app.client else { return }
        do { try await c.post("/downloads/\(id)/remove", body: RemoveBody(delete_files: false)); await load() } catch { actionError = error.localizedDescription }
    }
}

struct DownloadRowView: View {
    @Environment(AppModel.self) private var app
    let row: DownloadRow
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            if let p = app.posterFallback(kind: row.kind, tmdb: nil, titleID: row.title_id) {
                RemoteImage(path: p)
                    .frame(width: 64, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            details
        }
        .padding(16)
        #if os(visionOS)
        .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        #endif
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.displayTitle).font(.headline).lineLimit(1)
                    Text(row.name ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                StateBadge(text: row.label ?? row.state ?? "", tint: tint)
            }
            if !row.isDone {
                ProgressView(value: min(max(row.progress ?? 0, 0), 1))
                    .tint(tint)
            }
            HStack(spacing: 16) {
                Text(String(format: "%.0f%%", (row.progress ?? 0) * 100))
                if let s = row.covers { Text(s) }
                if !Fmt.speed(row.speed).isEmpty { Text("↓ \(Fmt.speed(row.speed))") }
                if let eta = row.eta { Text("\(Fmt.duration(eta)) left") }
                Text(Fmt.bytes(row.size))
                if let d = row.downloader { Text(d) }
                if let who = row.requested_by { Text("for \(who)") }
                if let t = row.text, !t.isEmpty { Text(t).lineLimit(1) }
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var tint: Color {
        switch row.state {
        case "downloading": .blue
        case "seeding": .green
        case "paused", "queued": .secondary
        case "failed", "error", "stalled": .orange
        default: row.isDone ? .green : .blue
        }
    }
}
