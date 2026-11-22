import SwiftUI

/// What the app shows when HolyArrs could not be reached at launch. The saved login is kept, and the app keeps
/// trying in the background; when HolyArrs answers it switches to the normal tabs by itself.
/// visionOS and iOS: the Offline library in its own tab. tvOS (no downloads): a "can't reach" page.
struct OfflineRoot: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        content
            .task {
                // Try again every 20 seconds while offline.
                while !Task.isCancelled, app.phase == .offline {
                    try? await Task.sleep(for: .seconds(20))
                    guard !Task.isCancelled, app.phase == .offline else { return }
                    await app.start()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        #if os(tvOS)
        Unreachable()
        #else
        TabView {
            Tab("Offline", systemImage: "arrow.down.circle") {
                NavigationStack { OfflineLibraryView(offline: true) }
            }
        }
        #endif
    }
}

#if os(tvOS)
private struct Unreachable: View {
    @Environment(AppModel.self) private var app
    @State private var trying = false

    var body: some View {
        ContentUnavailableView {
            Label("Can't reach HolyArrs", systemImage: "wifi.slash")
        } description: {
            Text("Check that the server is running and that this Apple TV can reach it. You are still signed in.")
        } actions: {
            Button {
                Task {
                    trying = true
                    await app.start()
                    trying = false
                }
            } label: {
                if trying { ProgressView() } else { Text("Try again") }
            }
            .disabled(trying)
            Button("Sign out") { Task { await app.signOut() } }
        }
    }
}
#endif
