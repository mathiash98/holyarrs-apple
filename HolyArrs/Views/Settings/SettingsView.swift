import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var confirmSignOut = false
    @State private var showJellyfin = false
    @AppStorage("autoplayPreviews") private var autoplayPreviews = true
    @AppStorage("autoplayNext") private var autoplayNext = true
    @AppStorage("theaterMode") private var theaterMode = true

    var body: some View {
        Form {
            Section("Server") {
                LabeledContent("Address", value: app.serverURL)
                LabeledContent("HolyArrs version", value: app.serverVersion ?? "…")
                LabeledContent("Signed in as", value: app.me?.name ?? "")
                LabeledContent("Role", value: (app.me?.role ?? "").capitalized)
                LabeledContent("Signed in with", value: signedInWith)
                if app.readOnly {
                    Label("Debug read-only mode: changes are blocked.", systemImage: "lock").foregroundStyle(.orange)
                }
            }
            Section("Jellyfin (for playback)") {
                if let j = app.jellyfin {
                    LabeledContent("Server", value: j.server)
                    LabeledContent("User", value: j.userName ?? j.userID)
                }
                Button(app.jellyfin == nil ? "Connect Jellyfin…" : "Connect a different Jellyfin user…") { showJellyfin = true }
            }
            Section("Playback") {
                #if os(visionOS)
                Toggle("Cinema theatre when playing", isOn: $theaterMode)
                #endif
                Toggle("Autoplay trailer previews", isOn: $autoplayPreviews)
                Toggle("Autoplay next episode", isOn: $autoplayNext)
            }
            Section("Messages") {
                NavigationLink("Messages", value: Route.messages)
            }
            Section("App") {
                LabeledContent("Version", value: appVersion)
                #if os(visionOS)
                LabeledContent("Device", value: "Apple Vision Pro")
                #else
                LabeledContent("Device", value: "Apple TV")
                #endif
            }
            Section {
                Button("Sign out", role: .destructive) { confirmSignOut = true }
            }
        }
        .confirmationDialog("Sign out of HolyArrs?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { Task { await app.signOut() } }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showJellyfin) { JellyfinConnectSheet { showJellyfin = false } }
    }

    private var signedInWith: String {
        switch app.client?.credential {
        case .apiKey: "API key"
        case .session: app.me?.auth_method?.isEmpty == false ? (app.me?.auth_method ?? "").capitalized : "Password"
        case nil: ""
        }
    }

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }
}

/// Connects a Jellyfin user for playback when HolyArrs was signed in another way (for example with an API key).
struct JellyfinConnectSheet: View {
    @Environment(AppModel.self) private var app
    let done: () -> Void
    @AppStorage("lastJellyfinServer") private var server = JellyfinAuth.defaultServer
    @State private var name = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Jellyfin") {
                    TextField("Address", text: $server).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("User name", text: $name).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password", text: $password)
                }
                if let error { Section { Text(error).foregroundStyle(.yellow) } }
                Section {
                    Button(busy ? "Connecting…" : "Connect") { Task { await connect() } }
                        .disabled(busy || name.isEmpty)
                }
            }
            .navigationTitle("Connect Jellyfin")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: done) } }
        }
        #if os(visionOS)
        .frame(minWidth: 560, minHeight: 460)
        #endif
    }

    private func connect() async {
        busy = true
        defer { busy = false }
        do {
            app.saveJellyfin(try await JellyfinAuth.signIn(server: server, name: name, password: password))
            done()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// My messages (`/messages`). Marking read is an explicit button, never automatic.
struct MessagesView: View {
    @Environment(AppModel.self) private var app
    @State private var state: Loadable<MessagesAnswer> = .loading
    @State private var actionError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeading(text: "Messages", padded: false)
                ActionErrorBanner(message: $actionError)
                LoadView(state: state, retry: load) { m in
                    let msgs = m.messages ?? []
                    if msgs.isEmpty {
                        EmptyNote(title: "No messages", systemImage: "bell")
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(msgs) { msg in
                                NavigationLink(value: msg.title_id.map { Route.libraryTitle($0) } ?? .messages) {
                                    HStack(alignment: .top, spacing: 16) {
                                        Circle().fill(msg.read_at == nil ? Color.accentColor : .clear).frame(width: 12, height: 12).padding(.top, 6)
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(msg.text ?? "").font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                                            Text([HADate.parse(msg.created_at)?.relative, msg.kind?.replacingOccurrences(of: "_", with: " ")].compactMap { $0 }.joined(separator: " · "))
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(16)
                                }
                                .rowButton(corner: 18)
                                .disabled(msg.title_id == nil)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 20)
        }
        .toolbar {
            if (state.value?.unread ?? 0) > 0 {
                ToolbarItem(placement: .primaryAction) {
                    Button("Mark all read") { Task { await markRead() } }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard let c = app.client else { return }
        do { state = .loaded(try await c.get("/messages?limit=100")) }
        catch is CancellationError {}
        catch { state = .failed(error.localizedDescription) }
    }

    private func markRead() async {
        guard let c = app.client else { return }
        do { try await c.post("/messages/read"); await load() } catch { actionError = error.localizedDescription }
    }
}
