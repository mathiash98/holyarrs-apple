import SwiftUI

/// Decide: movies and episodes that need a choice (`/needs-decision`) and downloads to confirm (`/downloads/matches`).
struct DecideView: View {
    @Environment(AppModel.self) private var app
    @State private var decisions: Loadable<DecisionsAnswer> = .loading
    @State private var matches: MatchesAnswer?
    @State private var actionError: String?
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(text: "Decide")
                ActionErrorBanner(message: $actionError)
                SectionTitle(text: "Needs a decision")
                LoadView(state: decisions, retry: load) { d in
                    let items = d.items ?? []
                    if items.isEmpty {
                        EmptyNote(title: "Nothing to decide", systemImage: "checkmark.seal")
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(items) { DecisionRow(d: $0, decide: decide) }
                        }
                        .padding(.horizontal, Metrics.gutter)
                    }
                }
                let ms = (matches?.matches ?? []).filter { $0.state == "unsure" || !($0.candidates ?? []).isEmpty }
                if !ms.isEmpty {
                    SectionTitle(text: "Confirm match", subtitle: "Downloads HolyArrs did not send and could not match for sure")
                    LazyVStack(spacing: 12) {
                        ForEach(ms) { MatchRow(m: $0, pick: pick) }
                    }
                    .padding(.horizontal, Metrics.gutter)
                }
            }
            .padding(.vertical, 20)
        }
        .disabled(busy)
        .task { await load() }
    }

    private func load() async {
        guard let c = app.client else { return }
        do {
            decisions = .loaded(try await c.get("/needs-decision"))
        } catch is CancellationError {
        } catch {
            decisions = .failed(error.localizedDescription)
        }
        matches = try? await c.get("/downloads/matches")
    }

    private func decide(_ d: Decision, _ action: String) {
        guard let c = app.client else { return }
        Task {
            busy = true
            defer { busy = false }
            do { try await c.post("/needs-decision/\(d.slot_id)/decide", body: DecideBody(action: action)); await load() }
            catch { actionError = error.localizedDescription }
        }
    }

    private func pick(_ m: DownloadMatch, _ body: PickBody) {
        guard let c = app.client else { return }
        Task {
            busy = true
            defer { busy = false }
            do { try await c.post("/downloads/matches/\(m.id)/pick", body: body); await load() }
            catch { actionError = error.localizedDescription }
        }
    }
}

private struct DecisionRow: View {
    let d: Decision
    let decide: (Decision, String) -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            RemoteImage(path: d.artwork).frame(width: 70, height: 105).clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 6) {
                Text([d.title, d.year.map(String.init)].compactMap { $0 }.joined(separator: " ")).font(.headline)
                if let r = d.reason { Text(r).font(.callout).foregroundStyle(.secondary) }
                if let rn = d.release_name { Text(rn).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                HStack(spacing: 12) {
                    Button("Search again") { decide(d, "search") }
                    Button("Turn down release") { decide(d, "turn_down") }
                    Button("Stop looking", role: .destructive) { decide(d, "stop") }
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        }
        .panel(corner: 20, padding: 16)
    }
}

private struct MatchRow: View {
    let m: DownloadMatch
    let pick: (DownloadMatch, PickBody) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(m.name ?? "").font(.headline).lineLimit(2)
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(m.candidates ?? []) { c in
                        Button {
                            pick(m, PickBody(candidate: c.id))
                        } label: {
                            Text([c.name, c.year.map(String.init), c.kind].compactMap { $0 }.joined(separator: " · "))
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Button("Not a movie or show") { pick(m, PickBody(not_media: true)) }.buttonStyle(.bordered)
                    Button("Skip") { pick(m, PickBody(skip: true)) }.buttonStyle(.bordered)
                }
                .padding(.vertical, 6)
            }
        }
        .panel(corner: 20, padding: 16)
    }
}

/// History (`/events`), newest first.
struct HistoryView: View {
    @Environment(AppModel.self) private var app
    @State private var state: Loadable<[HistoryEvent]> = .loading
    @State private var total = 0
    @State private var loadingMore = false

    var body: some View {
        LoadView(state: state, retry: { await load(reset: true) }) { events in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    PageHeading(text: "History", padded: false)
                    ForEach(grouped(events), id: \.0) { day, evs in
                        Text(day).font(.headline).foregroundStyle(.secondary).padding(.top, 14)
                        ForEach(evs) { e in
                            Button {} label: { EventRow(e: e) }.rowButton(corner: 16)
                        }
                    }
                    if events.count < total {
                        Button {
                            Task { await load(reset: false) }
                        } label: {
                            Label(loadingMore ? "Loading…" : "Older", systemImage: "chevron.down").frame(maxWidth: .infinity).padding()
                        }
                        .rowButton()
                        .disabled(loadingMore)
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, 20)
            }
        }
        .task { await load(reset: true) }
    }

    private func grouped(_ evs: [HistoryEvent]) -> [(String, [HistoryEvent])] {
        var out: [(String, [HistoryEvent])] = []
        for e in evs {
            let key = HADate.parse(e.at)?.formatted(date: .complete, time: .omitted) ?? "Earlier"
            if out.last?.0 == key { out[out.count - 1].1.append(e) } else { out.append((key, [e])) }
        }
        return out
    }

    private func load(reset: Bool) async {
        guard let c = app.client else { return }
        let have = reset ? [] : (state.value ?? [])
        loadingMore = !reset
        defer { loadingMore = false }
        do {
            let a: EventsAnswer = try await c.get("/events?limit=50&offset=\(have.count)")
            total = a.total ?? 0
            state = .loaded(have + (a.events ?? []))
        } catch is CancellationError {
        } catch {
            if reset { state = .failed(error.localizedDescription) }
        }
    }
}

private struct EventRow: View {
    let e: HistoryEvent
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon).frame(width: 30).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(e.summary ?? e.kind ?? "").font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                Text([HADate.parse(e.at)?.formatted(date: .omitted, time: .shortened), e.actorName, e.kind?.replacingOccurrences(of: "_", with: " ")].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    private var icon: String {
        let k = e.kind ?? ""
        if k.contains("import") { return "tray.and.arrow.down" }
        if k.contains("grab") || k.contains("download") { return "arrow.down.circle" }
        if k.contains("ask") { return "hand.raised" }
        if k.contains("delete") || k.contains("remove") { return "trash" }
        if k.contains("key") || k.contains("sign") { return "key" }
        if k.contains("fail") { return "exclamationmark.triangle" }
        return "clock"
    }
}

/// Turned-down releases (`/turned-down`), with the option to take one off the list.
struct TurnedDownView: View {
    @Environment(AppModel.self) private var app
    @State private var state: Loadable<ReleasePage> = .loading
    @State private var actionError: String?
    @State private var chosen: ReleaseRow?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeading(text: "Turned down")
                ActionErrorBanner(message: $actionError)
                LoadView(state: state, retry: load) { p in
                    let rs = p.releases ?? []
                    if rs.isEmpty {
                        EmptyNote(title: "No turned-down releases", systemImage: "hand.thumbsdown")
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(rs) { r in
                                Button { chosen = r } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(r.title_name ?? "").font(.headline)
                                        Text(r.name ?? "").font(.callout).lineLimit(1)
                                        Text([r.turned_down_for, r.source_name, Fmt.bytes(r.size)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(14)
                                }
                                .rowButton(corner: 16)
                            }
                        }
                        .padding(.horizontal, Metrics.gutter)
                    }
                }
            }
            .padding(.vertical, 20)
        }
        .task { await load() }
        .confirmationDialog(chosen?.name ?? "", isPresented: Binding(get: { chosen != nil }, set: { if !$0 { chosen = nil } }), titleVisibility: .visible, presenting: chosen) { r in
            if let t = r.title_id { NavigationLink("Open title", value: Route.libraryTitle(t)) }
            Button("Allow this release again") { Task { await allow(r) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func load() async {
        guard let c = app.client else { return }
        do { state = .loaded(try await c.get("/turned-down?limit=100")) }
        catch is CancellationError {}
        catch { state = .failed(error.localizedDescription) }
    }

    private func allow(_ r: ReleaseRow) async {
        guard let c = app.client else { return }
        do { try await c.delete("/turned-down/\(r.id)"); await load() } catch { actionError = error.localizedDescription }
    }
}
