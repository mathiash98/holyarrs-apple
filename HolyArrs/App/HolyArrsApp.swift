import SwiftUI

@main
struct HolyArrsApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .preferredColorScheme(.dark)
                .tint(Color(red: 0.95, green: 0.23, blue: 0.18))
                .task { await app.start() }
        }
        #if os(visionOS)
        .windowStyle(.plain)
        .defaultSize(width: 1680, height: 1050)
        #endif
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Group {
            switch app.phase {
            case .starting:
                ProgressView("Connecting to HolyArrs").controlSize(.large)
            case .signedOut:
                SignInView()
            case .signedIn:
                MainTabs()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { AmbientBackground() }
        #if os(visionOS)
        .clipShape(RoundedRectangle(cornerRadius: 46, style: .continuous))
        #endif
    }
}

enum AppTab: String, Hashable, CaseIterable {
    case home, library, explore, search, requests, downloads, calendar, settings
}

struct MainTabs: View {
    @Environment(AppModel.self) private var app
    @State private var tab: AppTab = .home

    var body: some View {
        TabView(selection: $tab) {
            Tab("Home", systemImage: "house", value: AppTab.home) { stack { HomeView() } }
            Tab("Library", systemImage: "film.stack", value: AppTab.library) { stack { LibraryView() } }
            Tab("Explore", systemImage: "sparkles.tv", value: AppTab.explore) { stack { ExploreView() } }
            Tab("Search", systemImage: "magnifyingglass", value: AppTab.search, role: .search) { stack { SearchView() } }
            Tab("Requests", systemImage: "tray.full", value: AppTab.requests) { stack { RequestsView() } }
            if app.me?.can("manage_library") == true {
                Tab("Downloads", systemImage: "arrow.down.circle", value: AppTab.downloads) { stack { DownloadsView() } }
            }
            Tab("Calendar", systemImage: "calendar", value: AppTab.calendar) { stack { CalendarView() } }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) { stack { SettingsView() } }
        }
        #if os(iOS)
        .tabViewStyle(.sidebarAdaptable)
        #endif
        .onAppear {
            if let t = app.debugStartTab.flatMap(AppTab.init(rawValue:)) { tab = t }
        }
    }

    @ViewBuilder
    private func stack<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        DebugStack(root: content())
    }
}

/// A NavigationStack that can open a debug route once (for simulator screenshots).
struct DebugStack<Root: View>: View {
    @Environment(AppModel.self) private var app
    let root: Root
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            root.withRoutes()
        }
        .onAppear {
            if let r = app.debugRoute {
                app.debugRoute = nil
                path.append(r)
            }
        }
    }
}
