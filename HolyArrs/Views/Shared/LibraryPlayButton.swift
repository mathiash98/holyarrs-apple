import SwiftUI

/// "Play" for a title that is on Jellyfin: the movie, or the show's next episode (resuming where it stopped).
struct LibraryPlayButton: View {
    @Environment(AppModel.self) private var app
    let kind: String?
    let tmdb: String?
    var titleID: Int? = nil

    @State private var target: JFItem?
    @State private var error: String?

    var body: some View {
        Group {
            if let t = target {
                Button {
                    Task { await play(t) }
                } label: {
                    Label(label(t), systemImage: "play.fill")
                }
                .primaryAction()
            }
        }
        .task(id: "\(kind ?? "")/\(tmdb ?? "")/\(titleID ?? 0)/\(app.jellyfin?.userID ?? "")") { await resolve() }
        .alert("Could not play", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    private func label(_ t: JFItem) -> String {
        var s = t.resumeSeconds != nil ? "Resume" : "Play"
        if t.isEpisode, let a = t.ParentIndexNumber, let b = t.IndexNumber { s += " S\(a)E\(b)" }
        return s
    }

    private func resolve() async {
        target = nil
        guard let j = app.jellyfinClient else { return }
        var k = kind, t = tmdb
        if t == nil, let key = app.tmdbKey(titleID: titleID) { k = key.kind; t = key.tmdb }
        guard let k, let t, let id = await j.itemID(kind: k, tmdb: t) else { return }
        if k == "movie" {
            target = try? await j.item(id)
        } else {
            let next = try? await j.nextUp(series: id, limit: 1)
            if let n = next?.first { target = n } else { target = (try? await j.episodes(series: id))?.first }
        }
    }

    private func play(_ t: JFItem) async {
        guard let j = app.jellyfinClient else { return }
        do {
            let fresh = (try? await j.item(t.Id)) ?? t
            try await Player.play(fresh, client: j, from: fresh.resumeSeconds)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Plays the full trailer (with sound) in the built-in player when HolyArrs has one.
struct TrailerButton: View {
    @Environment(AppModel.self) private var app
    let kind: String?
    let tmdb: String?
    let name: String
    @State private var url: URL?

    var body: some View {
        Group {
            if let url {
                Button {
                    Player.play(url: url, title: name, subtitle: "Trailer")
                } label: {
                    Label("Trailer", systemImage: "play.rectangle")
                }
                .buttonStyle(.bordered)
            }
        }
        .task(id: "\(kind ?? "")/\(tmdb ?? "")") {
            url = nil
            guard let c = app.client, let kind, let tmdb, kind == "movie" || kind == "show",
                  let t: TrailerStream = try? await c.get("/trailer/\(kind)/\(tmdb.q)"), let s = t.url else { return }
            url = URL(string: s)
        }
    }
}
