import SwiftUI

/// Requests: every ask with its state, a filter, and approve / turn down / remove.
struct RequestsView: View {
    @Environment(AppModel.self) private var app

    enum Filter: String, CaseIterable, Identifiable {
        case all, asked, approved, available, turned_down
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: "All"
            case .asked: "Waiting"
            case .approved: "Approved"
            case .available: "Ready"
            case .turned_down: "Turned down"
            }
        }
    }

    @State private var filter: Filter = .all
    @State private var mineOnly = false
    @State private var state: Loadable<AsksAnswer> = .loading
    @State private var chosen: Ask?
    @State private var turningDown: Ask?
    @State private var removing: Ask?
    @State private var busy = false
    @State private var actionError: String?

    private var canApprove: Bool { app.me?.can("approve") == true }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 20) {
                    Picker("Filter", selection: $filter) {
                        ForEach(Filter.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    #if os(visionOS)
                    .frame(maxWidth: 820)
                    #endif
                    Toggle("Mine only", isOn: $mineOnly).fixedSize()
                    Spacer()
                }
                .padding(.horizontal, Metrics.gutter)

                ActionErrorBanner(message: $actionError)

                switch state {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity, minHeight: 300)
                case let .failed(m):
                    ErrorView(message: m) { await load() }.frame(minHeight: 300)
                case let .loaded(a):
                    let asks = a.asks ?? []
                    if asks.isEmpty {
                        EmptyNote(title: "No requests here", systemImage: "tray")
                    } else {
                        Text("\(asks.count) of \(a.total ?? asks.count)").font(.caption).foregroundStyle(.secondary).padding(.horizontal, Metrics.gutter)
                        LazyVStack(spacing: 14) {
                            ForEach(asks) { ask in
                                Button { chosen = ask } label: { AskRow(ask: ask) }
                                    .rowButton(corner: 22)
                            }
                        }
                        .padding(.horizontal, Metrics.gutter)
                    }
                }
            }
            .padding(.vertical, 20)
        }
        .disabled(busy)
        .task(id: "\(filter.rawValue)|\(mineOnly)") { await load() }
        .refreshable { await load() }
        .confirmationDialog(chosen?.name ?? "", isPresented: Binding(get: { chosen != nil }, set: { if !$0 { chosen = nil } }), titleVisibility: .visible, presenting: chosen) { ask in
            if let r = ask.route {
                NavigationLink("Open title", value: r)
            }
            if canApprove && ask.state == "asked" {
                Button("Approve") { Task { await approve(ask) } }
                Button("Turn down…") { turningDown = ask }
            }
            if ask.mine == true || app.me?.isOwner == true {
                Button("Remove request", role: .destructive) { removing = ask }
            }
            Button("Cancel", role: .cancel) {}
        } message: { ask in
            Text([ask.season_words, ask.state_label, ask.asked_by?.name.map { "Asked by \($0)" }].compactMap { $0 }.joined(separator: " · "))
        }
        .confirmationDialog("Remove this request?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible, presenting: removing) { ask in
            Button("Remove", role: .destructive) { Task { await remove(ask) } }
            Button("Keep", role: .cancel) {}
        } message: { ask in
            Text(ask.state == "asked" ? "It will be taken back before anyone approves it." : "The request is removed. Files already in the library stay.")
        }
        .sheet(item: $turningDown) { ask in
            TurnDownSheet(ask: ask) { note in
                turningDown = nil
                if let note { Task { await turnDown(ask, note: note) } }
            }
        }
    }

    private func load() async {
        guard let c = app.client else { return }
        var q = "/asks?limit=200"
        if filter != .all { q += "&state=\(filter.rawValue)" }
        if mineOnly { q += "&mine=1" }
        do {
            state = .loaded(try await c.get(q))
        } catch is CancellationError {
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func act(_ f: () async throws -> Void) async {
        busy = true
        defer { busy = false }
        do {
            try await f()
            await load()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func approve(_ ask: Ask) async {
        guard let c = app.client else { return }
        do {
            busy = true
            defer { busy = false }
            try await c.post("/asks/\(ask.id)/approve", body: Empty())
            await load()
        } catch let e as APIError where e.status == 404 {
            actionError = "HolyArrs could not find \(ask.name ?? "this title") at TMDB (id \(ask.tmdb_id?.value ?? "?")), so it cannot be added. The id was probably removed or merged at TMDB. Turn the request down or remove it, then ask for the title again from search."
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func turnDown(_ ask: Ask, note: String) async {
        guard let c = app.client else { return }
        await act { try await c.post("/asks/\(ask.id)/turn-down", body: TurnDownBody(note: note.isEmpty ? nil : note)) }
    }

    /// Same as the web: a waiting ask goes through POST /asks/remove, any other one through DELETE /asks/{id}.
    private func remove(_ ask: Ask) async {
        guard let c = app.client else { return }
        await act {
            if ask.state == "asked" {
                try await c.post("/asks/remove", body: RemoveAsksBody(ids: [ask.id]))
            } else {
                try await c.delete("/asks/\(ask.id)")
            }
        }
    }
}

struct AskRow: View {
    let ask: Ask
    var body: some View {
        HStack(spacing: 20) {
            RemoteImage(path: ask.poster)
                .frame(width: 80, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text(ask.name ?? "Untitled").font(.headline)
                    if let y = ask.year { Text(String(y)).foregroundStyle(.secondary) }
                }
                Text(subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                if let n = ask.note, !n.isEmpty { Text(n).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer()
            StateBadge(text: ask.state_label ?? ask.state ?? "", tint: StateBadge.tint(forAskState: ask.state))
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        #if os(visionOS)
        .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        #endif
    }

    private var subtitle: String {
        var p: [String] = [ask.kind == "show" ? "Show" : ask.kind == "artist" ? "Music" : "Movie"]
        if let s = ask.season_words, !s.isEmpty { p.append(s) }
        if let who = ask.asked_by?.name { p.append("by \(who)") }
        if let d = HADate.parse(ask.asked_at) { p.append(d.relative) }
        return p.joined(separator: " · ")
    }
}

struct TurnDownSheet: View {
    let ask: Ask
    let done: (String?) -> Void
    @State private var note = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Note to \(ask.asked_by?.name ?? "the person who asked") (optional)") {
                    TextField("Why", text: $note)
                }
                Section {
                    Button("Turn down \(ask.name ?? "")", role: .destructive) { done(note) }
                }
            }
            .navigationTitle("Turn down")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { done(nil) } } }
        }
        #if os(visionOS)
        .frame(minWidth: 560, minHeight: 380)
        #endif
    }
}
