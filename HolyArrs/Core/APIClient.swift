import Foundation

/// How the app proves who it is to HolyArrs.
enum Credential: Codable, Equatable {
    /// An API key, sent as `X-Api-Key`. Never needs CSRF and is not subject to the server's host-name check.
    case apiKey(String)
    /// A `holyarrs_session` cookie value from sign-in. Mutations also need the CSRF token from `/auth/me`.
    case session(String)
}

enum APIError: LocalizedError {
    case http(status: Int, message: String)
    case transport(String)
    case decoding(String)
    case readOnly
    case badURL

    var errorDescription: String? {
        switch self {
        case let .http(status, message):
            if message.isEmpty { return "The server answered \(status)." }
            return message
        case let .transport(m): return m
        case let .decoding(m): return "Could not read the server's answer (\(m))."
        case .readOnly: return "This build is in read-only mode (debug API key), so changes are blocked."
        case .badURL: return "The server address is not valid."
        }
    }

    var status: Int? {
        if case let .http(s, _) = self { return s }
        return nil
    }
}

/// A small async/await client for `/api/v1`. Decoding is tolerant: models use optionals and unknown fields are ignored.
final class APIClient {
    let baseURL: URL
    private(set) var credential: Credential?
    /// CSRF token for session sign-ins (from `/auth/me` or the sign-in answer).
    var csrf: String = ""
    /// When true, every non-GET request is refused locally. Used for the DEBUG dev-key hook.
    let readOnly: Bool
    /// Called when the server answers 401 to a request that carried a credential: the saved sign-in has ended.
    var onUnauthorized: (() -> Void)?

    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(baseURL: URL, credential: Credential?, readOnly: Bool = false) {
        self.baseURL = baseURL
        self.credential = credential
        self.readOnly = readOnly
        let config = URLSessionConfiguration.ephemeral
        // Cookies are handled by hand so the session lives in the Keychain, not in a shared cookie jar.
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config)
    }

    func setCredential(_ c: Credential?) { credential = c }

    /// Builds a URL for an API path such as `/home` or `/asks?state=asked`.
    func url(_ path: String) -> URL? {
        let p = path.hasPrefix("/") ? path : "/" + path
        return URL(string: baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/v1" + p)
    }

    /// Resolves an image link from the API. Relative links (`/api/v1/artwork/...`) are served by HolyArrs itself.
    func imageURL(_ s: String?) -> URL? {
        guard let s, !s.isEmpty else { return nil }
        if s.hasPrefix("http://") || s.hasPrefix("https://") { return URL(string: s) }
        if s.hasPrefix("/") {
            return URL(string: baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + s)
        }
        return nil
    }

    /// Auth headers for a request to this server (never added for other hosts such as image.tmdb.org).
    func authHeaders(for url: URL) -> [String: String] {
        guard url.host == baseURL.host, url.port == baseURL.port else { return [:] }
        switch credential {
        case let .apiKey(k): return ["X-Api-Key": k]
        case let .session(v): return ["Cookie": "holyarrs_session=\(v)"]
        case nil: return [:]
        }
    }

    // MARK: Requests

    func get<T: Decodable>(_ path: String, as: T.Type = T.self) async throws -> T {
        try await send("GET", path, body: Optional<Empty>.none)
    }

    func post<T: Decodable, B: Encodable>(_ path: String, body: B?) async throws -> T {
        try await send("POST", path, body: body)
    }

    @discardableResult
    func post(_ path: String) async throws -> Empty {
        try await send("POST", path, body: Optional<Empty>.none)
    }

    @discardableResult
    func post<B: Encodable>(_ path: String, body: B) async throws -> Empty {
        try await send("POST", path, body: body)
    }

    @discardableResult
    func delete(_ path: String) async throws -> Empty {
        try await send("DELETE", path, body: Optional<Empty>.none)
    }

    /// Sends a request and returns the raw response too (used for sign-in, which reads Set-Cookie).
    func raw<B: Encodable>(_ method: String, _ path: String, body: B?) async throws -> (Data, HTTPURLResponse) {
        if readOnly && method != "GET" { throw APIError.readOnly }
        guard let url = url(path) else { throw APIError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        for (k, v) in authHeaders(for: url) { req.setValue(v, forHTTPHeaderField: k) }
        if method != "GET" {
            if case .session = credential, !csrf.isEmpty { req.setValue(csrf, forHTTPHeaderField: "X-CSRF-Token") }
            if let body {
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try encoder.encode(body)
            }
        }
        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await session.data(for: req)
        } catch is CancellationError {
            throw CancellationError()
        } catch let e as URLError where e.code == .cancelled {
            throw CancellationError()
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        guard let http = resp as? HTTPURLResponse else { throw APIError.transport("No HTTP answer.") }
        if !(200 ..< 300).contains(http.statusCode) {
            let msg = (try? decoder.decode(ServerError.self, from: data))?.error ?? ""
            if http.statusCode == 401, credential != nil { onUnauthorized?() }
            throw APIError.http(status: http.statusCode, message: msg)
        }
        return (data, http)
    }

    private func send<T: Decodable, B: Encodable>(_ method: String, _ path: String, body: B?) async throws -> T {
        let (data, _) = try await raw(method, path, body: body)
        if T.self == Empty.self { return Empty() as! T }
        if data.isEmpty, let e = Empty() as? T { return e }
        do {
            return try decoder.decode(T.self, from: data)
        } catch let DecodingError.keyNotFound(key, ctx) {
            throw APIError.decoding("missing \(key.stringValue) at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))")
        } catch let DecodingError.typeMismatch(_, ctx) {
            throw APIError.decoding("type mismatch at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))")
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }
}

struct Empty: Codable {}
struct ServerError: Decodable { let error: String? }

extension String {
    /// Percent-encodes a query value.
    var q: String { addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? self }
}
