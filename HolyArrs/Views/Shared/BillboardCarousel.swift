import SwiftUI

/// One page of the top slider.
struct HeroSlide: Identifiable {
    let id: String
    var content: BillboardContent
    /// On disk / in the library (gets a Play button) or a new recommendation.
    var inLibrary: Bool
    var kind: String?
    var tmdb: String?
    var titleID: Int?
    var name: String
    var route: Route?
}

/// The top billboard as a slider: it moves to the next title every 25 seconds, and the page dots under the
/// buttons pick a title (on Apple TV moving focus along the dots changes the page). The billboard keeps its
/// identity while pages change, so focus stays where it is.
struct BillboardCarousel<Actions: View>: View {
    let slides: [HeroSlide]
    var height: CGFloat = BillboardMetrics.height
    @ViewBuilder var actions: (HeroSlide) -> Actions

    @State private var index = 0
    /// Bumped by a manual change, so the auto-advance timer starts over.
    @State private var tick = 0
    @FocusState private var focusedDot: Int?

    var body: some View {
        if !slides.isEmpty {
            let s = slides[min(index, slides.count - 1)]
            Billboard(content: s.content, height: height, footer: slides.count > 1 ? AnyView(dots) : nil) {
                actions(s)
            }
            .task(id: "\(index)/\(tick)/\(slides.count)") {
                guard slides.count > 1 else { return }
                try? await Task.sleep(for: .seconds(25))
                guard !Task.isCancelled, focusedDot == nil else { return }
                index = (index + 1) % slides.count
            }
            .onChange(of: focusedDot) { _, d in
                if let d, d != index { index = d; tick += 1 }
            }
        }
    }

    private var dots: some View {
        HStack(spacing: 10) {
            ForEach(slides.indices, id: \.self) { i in
                Button {
                    index = i
                    tick += 1
                } label: {
                    PageDot(selected: i == index)
                }
                .buttonStyle(PageDotStyle())
                .focused($focusedDot, equals: i)
                .accessibilityLabel("\(slides[i].name), \(i + 1) of \(slides.count)")
            }
        }
        .padding(.vertical, 6)
        #if os(tvOS)
        .focusSection()
        #endif
    }
}

private struct PageDot: View {
    let selected: Bool
    @Environment(\.isFocused) private var focused

    var body: some View {
        Capsule()
            .fill(.white.opacity(selected || focused ? 1 : 0.4))
            .frame(width: selected ? 34 : 10, height: 10)
            .scaleEffect(focused ? 1.35 : 1)
            .padding(6)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.2), value: selected)
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}

/// No platter: the dot draws its own focus look.
private struct PageDotStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
    }
}
