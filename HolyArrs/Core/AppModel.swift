import Foundation
import Observation

/// App-wide sign-in state. One instance lives in the environment.
@Observable
final class AppModel {
    enum Phase: Equatable {
        case starting
        case signedOut
        case signedIn
    }

    var phase: Phase = .starting
    private(set) var client: APIClient?
    private(set) var me: Me?
    private(set) var serverVersion: String?
    /// Jellyfin login kept for playback (batch 1.5) and for "Play in Swiftfin".
    private(set) var jellyfin: JellyfinLogin?
    /// True when the DEBUG dev-key hook is active: every change is blocked locally.
    private(set) var readOnly = false
    /// Debug hooks for screenshots: which tab to open and which route to push.
    var debugStartTab: String?
    var debugRoute: Route?
    var debugQuery: String?
    var debugOpenAsk = false
    /// Seconds to play before the player closes itself (0 = off).
    var debugAutoPlay: Double = 0

    var serverURL: String { client?.baseURL.absoluteString ?? "" }

    func start() async {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if let key = env["HOLYARRS_API_KEY"], !key.isEmpty {
            // Kept in memory only, never written to the Keychain, and the client refuses every change.
            if let server = env["HOLYARRS_SERVER"], let url = URL(string: server) {
                readOnly = true
                debugStartTab = env["HOLYARRS_TAB"]
                debugRoute = env["HOLYARRS_OPEN"].flatMap(Route.init(debugString:))
                debugQuery = env["HOLYARRS_QUERY"]
                debugOpenAsk = env["HOLYARRS_ASK"] == "1"
                debugAutoPlay = Double(env["HOLYARRS_PLAY"] ?? "") ?? 0
                if let t = env["HOLYARRS_JF_TOKEN"], !t.isEmpty, let u = env["HOLYARRS_JF_USER"] {
                    // In memory only; never saved to the Keychain.
                    jellyfin = JellyfinLogin(server: JellyfinAuth.defaultServer, serverID: nil, userID: u, userName: "debug", accessToken: t)
                }
                let c = APIClient(baseURL: url, credential: .apiKey(key), readOnly: true)
                if await adopt(c) { return }
            }
        }
        #endif
        jellyfin = JellyfinStore.load()
        guard let saved = Keychain.load(), let url = URL(string: saved.server) else {
            phase = .signedOut
            return
        }
        let c = APIClient(baseURL: url, credential: saved.credential)
        if await adopt(c) { return }
        // Keep the saved login when the server is just unreachable; only drop it when it was refused.
        phase = .signedOut
    }

    /// Checks the credential with `/auth/me` and switches to the signed-in state.
    @discardableResult
    func adopt(_ c: APIClient) async -> Bool {
        do {
            let me: Me = try await c.get("/auth/me")
            if let csrf = me.csrf, !csrf.isEmpty { c.csrf = csrf }
            self.client = c
            self.me = me
            self.phase = .signedIn
            Task { await loadAbout() }
            Task { await loadQuality() }
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    var lastError: String?

    private func loadAbout() async {
        guard let client else { return }
        if let a: AboutAnswer = try? await client.get("/app/about") { serverVersion = a.version }
    }

    func signedIn(client c: APIClient, credential: Credential) async throws {
        c.setCredential(credential)
        guard await adopt(c) else { throw APIError.transport(lastError ?? "Signed in, but /auth/me failed.") }
        Keychain.save(SavedLogin(server: c.baseURL.absoluteString, credential: credential, name: me?.name))
    }

    func saveJellyfin(_ j: JellyfinLogin) {
        jellyfin = j
        jellyfinClientCache = nil
        JellyfinStore.save(j)
        Task { await loadQuality() }
    }

    /// Quality labels by "kind:tmdb" (from Jellyfin) and Library title id to "kind:tmdb" (from /titles/owned).
    private(set) var qualityByKey: [String: String] = [:]
    private(set) var keyByTitleID: [Int: String] = [:]
    private(set) var jellyfinIDByKey: [String: String] = [:]

    /// A poster from Jellyfin for a Library title, when HolyArrs has no artwork for it.
    func posterFallback(kind: String?, tmdb: String?, titleID: Int?) -> String? {
        guard let j = jellyfinClient else { return nil }
        var key: String?
        if let k = kind, let t = tmdb { key = "\(k):\(t)" }
        if key == nil || jellyfinIDByKey[key!] == nil, let id = titleID { key = keyByTitleID[id] }
        guard let key, let jid = jellyfinIDByKey[key] else { return nil }
        return j.posterURL(itemID: jid)
    }

    /// "movie" / "show" and the TMDB id for a Library title id.
    func tmdbKey(titleID: Int?) -> (kind: String, tmdb: String)? {
        guard let id = titleID, let k = keyByTitleID[id] else { return nil }
        let p = k.split(separator: ":", maxSplits: 1).map(String.init)
        return p.count == 2 ? (p[0], p[1]) : nil
    }

    func quality(kind: String?, tmdb: String?, titleID: Int?) -> String? {
        if let k = kind, let t = tmdb, let q = qualityByKey["\(k):\(t)"] { return q }
        if let id = titleID, let key = keyByTitleID[id] { return qualityByKey[key] }
        return nil
    }

    private struct OwnedAnswer: Decodable {
        struct Item: Decodable { var kind: String?; var tmdb: String?; var id: Int? }
        var items: [Item]?
    }

    func loadQuality() async {
        if let c = client, let o: OwnedAnswer = try? await c.get("/titles/owned") {
            var m: [Int: String] = [:]
            for i in o.items ?? [] { if let id = i.id, let k = i.kind, let t = i.tmdb { m[id] = "\(k):\(t)" } }
            keyByTitleID = m
        }
        if let j = jellyfinClient {
            let r = await j.qualityIndex()
            qualityByKey = r.quality
            jellyfinIDByKey = r.ids
        }
    }

    private var jellyfinClientCache: JellyfinClient?
    /// One shared Jellyfin client (it caches the TMDB-to-Jellyfin item map).
    var jellyfinClient: JellyfinClient? {
        if let c = jellyfinClientCache { return c }
        guard let j = jellyfin, let c = JellyfinClient(login: j) else { return nil }
        jellyfinClientCache = c
        return c
    }

    func signOut() async {
        if let client, case .session = client.credential, !readOnly {
            _ = try? await client.post("/auth/logout")
        }
        Keychain.clear()
        JellyfinStore.clear()
        jellyfin = nil
        jellyfinClientCache = nil
        client = nil
        me = nil
        phase = .signedOut
    }
}
