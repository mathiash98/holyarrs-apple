import SwiftUI

/// Sign-in: server address first, then a way to sign in (password, Jellyfin, or an API key).
struct SignInView: View {
    @Environment(AppModel.self) private var app

    enum Step { case server, credentials, twoFactor }
    enum Way: String, CaseIterable, Identifiable {
        case password = "HolyArrs account"
        case jellyfin = "Jellyfin"
        case apiKey = "API key"
        var id: String { rawValue }
    }

    @AppStorage("lastServer") private var server = ""
    @AppStorage("lastJellyfinServer") private var jellyfinServer = JellyfinAuth.defaultServer
    @State private var step: Step = .server
    @State private var state: AuthState?
    @State private var way: Way = .jellyfin
    @State private var name = ""
    @State private var password = ""
    @State private var apiKey = ""
    @State private var code = ""
    @State private var ticket = ""
    @State private var busy = false
    @State private var error: String?
    @State private var pendingClient: APIClient?

    var body: some View {
        PageScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    Image(systemName: "sparkles.tv.fill").font(.system(size: 64)).foregroundStyle(.tint)
                    Text("HolyArrs").font(.largeTitle.bold())
                    Text("Sign in to your HolyArrs server").foregroundStyle(.secondary)
                }
                .padding(.top, 40)

                Group {
                    switch step {
                    case .server: serverStep
                    case .credentials: credentialsStep
                    case .twoFactor: twoFactorStep
                    }
                }
                .frame(maxWidth: 760)
                .panel(corner: 32, padding: 32)

                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .frame(maxWidth: 760, alignment: .leading)
                }
            }
            .padding(Metrics.gutter)
            .frame(maxWidth: .infinity)
        }
        .disabled(busy)
        .overlay { if busy { ProgressView().controlSize(.large) } }
    }

    // MARK: Steps

    private var serverStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Server address").font(.headline)
            TextField("https://holyarrs.example.ts.net", text: $server)
                .textContentType(.URL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button {
                Task { await checkServer() }
            } label: {
                Label("Continue", systemImage: "arrow.right").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var credentialsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(server).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button("Change") { step = .server; error = nil }
            }
            if let refused = state?.host_refused {
                Label {
                    Text("HolyArrs doesn't know the name \(refused), so it refuses password sign-in here. Add it under Settings › Sign-in and security › Allowed host names on the web, or use an API key.")
                } icon: {
                    Image(systemName: "exclamationmark.shield").foregroundStyle(.orange)
                }
                .font(.callout)
            }
            Picker("Sign in with", selection: $way) {
                ForEach(availableWays) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            switch way {
            case .password, .jellyfin:
                TextField(way == .jellyfin ? "Jellyfin user name" : "User name", text: $name)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                    .textContentType(.password)
                if way == .jellyfin {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Jellyfin address (for playback)").font(.caption).foregroundStyle(.secondary)
                        TextField("https://jellyfin.example.ts.net", text: $jellyfinServer)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
                Button {
                    Task { await signIn() }
                } label: {
                    Label("Sign in", systemImage: "person.crop.circle.badge.checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || password.isEmpty)
            case .apiKey:
                Text("Make a key in HolyArrs under Settings › Sign-in and security › API keys, then paste it here.")
                    .font(.callout).foregroundStyle(.secondary)
                SecureField("API key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button {
                    Task { await useKey() }
                } label: {
                    Label("Use key", systemImage: "key").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var twoFactorStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Two-factor code").font(.headline)
            Text("Enter the 6-digit code from your authenticator app, or a backup code.").foregroundStyle(.secondary)
            TextField("123456", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
            HStack {
                Button("Back") { step = .credentials; code = ""; ticket = "" }
                Button {
                    Task { await sendCode() }
                } label: {
                    Label("Verify", systemImage: "checkmark.shield").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(code.isEmpty)
            }
        }
    }

    private var availableWays: [Way] {
        let ways = state?.ways ?? ["password"]
        var out: [Way] = []
        if ways.contains("jellyfin") { out.append(.jellyfin) }
        if ways.contains("password") { out.append(.password) }
        out.append(.apiKey)
        return out
    }

    // MARK: Actions

    private func normalizedServer() -> URL? {
        var s = server.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.contains("://") { s = "https://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        server = s
        return URL(string: s)
    }

    private func checkServer() async {
        error = nil
        guard let url = normalizedServer() else { error = APIError.badURL.localizedDescription; return }
        busy = true
        defer { busy = false }
        let c = APIClient(baseURL: url, credential: nil)
        do {
            let st: AuthState = try await c.get("/auth/state")
            state = st
            pendingClient = c
            if let first = availableWays.first { way = first }
            step = .credentials
        } catch {
            self.error = "Could not reach HolyArrs at \(url.absoluteString): \(error.localizedDescription)"
        }
    }

    private func signIn() async {
        guard let c = pendingClient else { step = .server; return }
        error = nil
        busy = true
        defer { busy = false }
        do {
            let path = way == .jellyfin ? "/auth/media-server/jellyfin" : "/auth/login"
            let answer = try await login(c, path: path, body: LoginBody(name: name, password: password))
            if answer.done {
                if way == .jellyfin { await connectJellyfin() }
                password = ""
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Signs in to Jellyfin itself too, so the app has a Jellyfin token for playback. A failure here does not block HolyArrs.
    private func connectJellyfin() async {
        guard !jellyfinServer.isEmpty else { return }
        if let j = try? await JellyfinAuth.signIn(server: jellyfinServer, name: name, password: password) {
            app.saveJellyfin(j)
        }
    }

    private func sendCode() async {
        guard let c = pendingClient else { return }
        error = nil
        busy = true
        defer { busy = false }
        do {
            _ = try await login(c, path: "/auth/login/two-factor", body: TwoFactorBody(ticket: ticket, code: code.trimmingCharacters(in: .whitespaces)))
            if way == .jellyfin { await connectJellyfin() }
            password = ""
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Posts a sign-in body, reads the session cookie, and either finishes or asks for a two-factor code.
    private func login<B: Encodable>(_ c: APIClient, path: String, body: B) async throws -> (done: Bool, Void) {
        let (data, resp) = try await c.raw("POST", path, body: body)
        let answer = (try? JSONDecoder().decode(LoginAnswer.self, from: data)) ?? LoginAnswer()
        if answer.two_factor == true, let t = answer.ticket {
            ticket = t
            code = ""
            step = .twoFactor
            return (false, ())
        }
        guard let cookie = sessionCookie(resp, url: c.url(path)) else {
            throw APIError.transport("Signed in, but the server sent no session cookie.")
        }
        c.csrf = answer.csrf ?? ""
        try await app.signedIn(client: c, credential: .session(cookie))
        return (true, ())
    }

    private func sessionCookie(_ resp: HTTPURLResponse, url: URL?) -> String? {
        guard let url else { return nil }
        let fields = resp.allHeaderFields.reduce(into: [String: String]()) { d, kv in
            if let k = kv.key as? String, let v = kv.value as? String { d[k] = v }
        }
        return HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
            .first { $0.name == "holyarrs_session" }?.value
    }

    private func useKey() async {
        guard let c = pendingClient else { step = .server; return }
        error = nil
        busy = true
        defer { busy = false }
        do {
            try await app.signedIn(client: c, credential: .apiKey(apiKey.trimmingCharacters(in: .whitespacesAndNewlines)))
            apiKey = ""
        } catch {
            self.error = "That key was not accepted: \(error.localizedDescription)"
        }
    }
}
