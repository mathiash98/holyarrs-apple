import Foundation
import Security
#if canImport(UIKit)
import UIKit
#endif

/// A direct Jellyfin login, kept for playback (batch 1.5) and "Play in Swiftfin".
/// HolyArrs' own Jellyfin sign-in returns a HolyArrs session, not a Jellyfin token, so the app also
/// signs in to Jellyfin itself with the same name and password.
struct JellyfinLogin: Codable, Equatable {
    var server: String
    var serverID: String?
    var userID: String
    var userName: String?
    var accessToken: String
}

enum JellyfinStore {
    private static let service = (Bundle.main.bundleIdentifier ?? "holyarrs") + ".jellyfin"

    static func load() -> JellyfinLogin? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "default",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return try? JSONDecoder().decode(JellyfinLogin.self, from: d)
    }

    static func save(_ j: JellyfinLogin) {
        clear()
        guard let d = try? JSONEncoder().encode(j) else { return }
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "default",
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: d,
        ]
        SecItemAdd(q as CFDictionary, nil)
    }

    static func clear() {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "default",
        ]
        SecItemDelete(q as CFDictionary)
    }
}

/// Minimal Jellyfin client for batch 1: sign in by name. Batch 1.5 replaces this with jellyfin-sdk-swift.
enum JellyfinAuth {
    /// No default: people type their Jellyfin address (or DEBUG builds read HOLYARRS_JF_SERVER).
    static var defaultServer: String { ProcessInfo.processInfo.environment["HOLYARRS_JF_SERVER"] ?? "" }

    static var deviceID: String {
        let k = "jellyfin.deviceID"
        if let v = UserDefaults.standard.string(forKey: k) { return v }
        let v = UUID().uuidString
        UserDefaults.standard.set(v, forKey: k)
        return v
    }

    static func authHeader(token: String? = nil) -> String {
        #if os(tvOS)
        let device = "Apple TV"
        #else
        let device = "Apple Vision Pro"
        #endif
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        var h = "MediaBrowser Client=\"HolyArrs\", Device=\"\(device)\", DeviceId=\"\(deviceID)\", Version=\"\(version)\""
        if let token { h += ", Token=\"\(token)\"" }
        return h
    }

    private struct AuthBody: Encodable { let Username: String; let Pw: String }
    private struct AuthAnswer: Decodable {
        struct User: Decodable { let Id: String; let Name: String?; let ServerId: String? }
        let User: User
        let AccessToken: String
        let ServerId: String?
    }

    /// POST /Users/AuthenticateByName. Only called when the person signs in on the device.
    static func signIn(server: String, name: String, password: String) async throws -> JellyfinLogin {
        guard let base = URL(string: server.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))),
              let url = URL(string: base.absoluteString + "/Users/AuthenticateByName") else { throw APIError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(authHeader(), forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONEncoder().encode(AuthBody(Username: name, Pw: password))
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.transport("No answer from Jellyfin.") }
        guard http.statusCode == 200 else {
            throw APIError.http(status: http.statusCode, message: http.statusCode == 401 ? "Jellyfin did not accept that name and password." : "Jellyfin answered \(http.statusCode).")
        }
        let a = try JSONDecoder().decode(AuthAnswer.self, from: data)
        return JellyfinLogin(server: base.absoluteString, serverID: a.ServerId ?? a.User.ServerId, userID: a.User.Id, userName: a.User.Name, accessToken: a.AccessToken)
    }
}

/// Builds a Swiftfin deep link (`swiftfin://<serverId>/<userId>/item/<itemId>`) from a HolyArrs watch link.
enum SwiftfinLink {
    /// The Jellyfin web link has its ids in the fragment: `.../web/#/details?id=<item>&serverId=<server>`.
    static func ids(fromWatchURL s: String) -> (item: String, server: String)? {
        guard let hash = s.firstIndex(of: "#") else { return nil }
        let frag = s[s.index(after: hash)...]
        guard let qi = frag.firstIndex(of: "?") else { return nil }
        var item: String?, server: String?
        for pair in frag[frag.index(after: qi)...].split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            if kv[0] == "id" { item = kv[1] }
            if kv[0] == "serverId" { server = kv[1] }
        }
        guard let item, let server else { return nil }
        return (item, server)
    }

    static func url(server: String, user: String, item: String) -> URL? {
        URL(string: "swiftfin://\(server)/\(user)/item/\(item)")
    }
}
