import SwiftUI

/// The three states every page goes through.
enum Loadable<T> {
    case loading
    case failed(String)
    case loaded(T)

    var value: T? {
        if case let .loaded(v) = self { return v }
        return nil
    }
}

/// Shows a spinner, an error with Retry, or the content.
struct LoadView<T, Content: View>: View {
    let state: Loadable<T>
    let retry: () async -> Void
    @ViewBuilder let content: (T) -> Content

    var body: some View {
        switch state {
        case .loading:
            ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(msg):
            ErrorView(message: msg, retry: retry)
        case let .loaded(v):
            content(v)
        }
    }
}

struct ErrorView: View {
    let message: String
    let retry: () async -> Void
    var body: some View {
        ContentUnavailableView {
            Label("Could not load", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try again") { Task { await retry() } }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A quiet empty state.
struct EmptyNote: View {
    let title: String
    var systemImage: String = "tray"
    var detail: String? = nil
    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: detail.map { Text($0) })
            .frame(maxWidth: .infinity, minHeight: 300)
    }
}

/// A small colored state capsule.
struct StateBadge: View {
    let text: String
    var tint: Color = .secondary
    var body: some View {
        Text(text)
            .font(.xCaption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(tint == .secondary ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(tint.opacity(0.85)), in: Capsule())
            .foregroundStyle(tint == .secondary ? Color.primary : .white)
    }

    static func tint(forAskState s: String?) -> Color {
        switch s {
        case "asked": .orange
        case "approved": .blue
        case "available": .green
        case "turned_down": .red
        default: .secondary
        }
    }
}

/// A banner explaining a failed action.
struct ActionErrorBanner: View {
    @Binding var message: String?
    var body: some View {
        if let message {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                Text(message).font(.xCallout).frame(maxWidth: .infinity, alignment: .leading)
                Button("Dismiss") { self.message = nil }
            }
            .panel(corner: 18, padding: 16)
            .padding(.horizontal, Metrics.gutter)
        }
    }
}
