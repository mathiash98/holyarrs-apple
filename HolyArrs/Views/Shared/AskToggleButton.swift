import SwiftUI

/// "+ Ask" / "✓ Asked" for a title that is not in the library, like Netflix's My List button: one click asks
/// (a show: every season), a second click takes my ask back.
struct AskToggleButton: View {
    @Environment(AppModel.self) private var app
    let kind: String?
    let tmdb: String?
    let name: String
    var initial: AskBrief? = nil
    /// White like Play (the billboard's main button) or translucent grey.
    var prominent = true

    @State private var ask: AskBrief?
    @State private var loaded = false
    @State private var busy = false
    @State private var error: String?

    private var active: AskBrief? {
        guard let a = ask, a.mine == true, a.id != nil, a.state == "asked" || a.state == "approved" else { return nil }
        return a
    }

    var body: some View {
        Group {
            if let a = active {
                Button { Task { await remove(a) } } label: {
                    Label("Asked", systemImage: "checkmark")
                }
                .secondaryAction()
            } else if prominent {
                Button { Task { await send() } } label: { Label("Ask", systemImage: "plus") }
                    .primaryAction()
            } else {
                Button { Task { await send() } } label: { Label("Ask", systemImage: "plus") }
                    .secondaryAction()
            }
        }
        .disabled(busy || tmdb == nil || (app.me?.can("ask") != true && app.me?.isOwner != true))
        .onAppear { if !loaded { ask = initial; loaded = true } }
        .onChange(of: "\(kind ?? "")/\(tmdb ?? "")") { _, _ in ask = initial }
        .alert("Could not ask", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    private func send() async {
        guard let c = app.client, let tmdb, let kind else { return }
        busy = true
        defer { busy = false }
        do {
            let a: AskAnswer = try await c.post("/asks", body: AskBody(id: "tmdb:\(tmdb)", kind: kind))
            if let x = a.ask {
                ask = AskBrief(id: x.id, state: x.state, state_label: x.state_label, mine: true)
            } else {
                ask = AskBrief(id: nil, state: "asked", state_label: "Asked", mine: true)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func remove(_ a: AskBrief) async {
        guard let c = app.client, let id = a.id else { return }
        busy = true
        defer { busy = false }
        do {
            if a.state == "asked" {
                try await c.post("/asks/remove", body: RemoveAsksBody(ids: [id]))
            } else {
                try await c.delete("/asks/\(id)")
            }
            ask = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// The billboard's "i": opens the title page.
struct InfoButton: View {
    let route: Route
    var body: some View {
        NavigationLink(value: route) {
            Image(systemName: "info.circle")
        }
        .secondaryAction()
        .buttonBorderShape(.circle)
        .accessibilityLabel("More info")
    }
}
