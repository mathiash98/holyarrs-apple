import SwiftUI

/// The cinema backdrop behind every page: near-black, tinted by a heavily blurred picture of the current title.
struct AmbientBackground: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.035, blue: 0.045)
            if let a = app.ambient {
                RemoteImage(path: a)
                    .blur(radius: 90)
                    .saturation(1.3)
                    .opacity(0.55)
                    .id(a)
                    .transition(.opacity)
            }
            LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.55), .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
        }
        .animation(.easeInOut(duration: 0.9), value: app.ambient)
        .ignoresSafeArea()
    }
}

extension View {
    /// Makes this card the page's ambient backdrop when it gets focus (tvOS) or the pointer (visionOS with a mouse).
    func ambientOnFocus(_ picture: String?) -> some View { modifier(AmbientFocus(picture: picture)) }
}

private struct AmbientFocus: ViewModifier {
    @Environment(AppModel.self) private var app
    let picture: String?
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        #if os(tvOS)
        content
            .focused($focused)
            .onChange(of: focused) { _, f in if f, let picture { app.ambient = picture } }
        #else
        content.onHover { inside in if inside, let picture { app.ambient = picture } }
        #endif
    }
}

/// Tells the caller when a card gains or loses focus (Apple TV) or the pointer (iPad, Mac).
struct FocusReport: ViewModifier {
    let action: ((Bool) -> Void)?
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        if let action {
            #if os(tvOS)
            content
                .focused($focused)
                .onChange(of: focused) { _, f in action(f) }
            #else
            content.onHover { action($0) }
            #endif
        } else {
            content
        }
    }
}
