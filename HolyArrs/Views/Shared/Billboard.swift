import SwiftUI

/// What a billboard shows.
struct BillboardContent {
    var kind: String?
    var tmdb: String?
    var titleID: Int?
    var name: String
    var logo: String?
    var backdrop: String?
    var tagline: String?
    var meta: [String] = []
    var overview: String?
    var route: Route?
}

/// A full-bleed hero: trailer preview (or the backdrop), a big logo or title, facts, overview and actions.
struct Billboard<Actions: View>: View {
    @Environment(AppModel.self) private var app
    let content: BillboardContent
    var height: CGFloat = BillboardMetrics.height
    var overviewLines = 3
    @ViewBuilder var actions: () -> Actions

    @State private var muted = true
    @State private var playing = false
    @State private var zoom = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(path: content.backdrop)
                .scaleEffect(zoom ? 1.08 : 1.0)
                .animation(.easeInOut(duration: 24).repeatForever(autoreverses: true), value: zoom)
                .onAppear { zoom = true }
            TrailerPreview(kind: content.kind, tmdb: content.tmdb, muted: $muted, playing: $playing)
            // Netflix-style fades: dark to the left for text, and down into the page.
            LinearGradient(colors: [.black.opacity(0.85), .black.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
            LinearGradient(colors: [.clear, .clear, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 16) {
                if let logo = content.logo {
                    RemoteImage(path: logo, contentMode: .fit)
                        .frame(maxWidth: logoWidth, maxHeight: logoHeight, alignment: .bottomLeading)
                        .shadow(color: .black.opacity(0.6), radius: 12)
                } else {
                    Text(content.name)
                        .font(.system(size: titleSize, weight: .black, design: .default))
                        .tracking(-0.5)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .shadow(color: .black.opacity(0.6), radius: 10)
                }
                HStack(spacing: 10) {
                    if let q = app.quality(kind: content.kind, tmdb: content.tmdb, titleID: content.titleID) { QualityChip(label: q) }
                    Text(content.meta.joined(separator: "  ·  "))
                        .font(metaFont)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
                if let t = content.tagline, !t.isEmpty {
                    Text(t).font(metaFont.italic()).foregroundStyle(.white.opacity(0.9))
                }
                if let o = content.overview, !o.isEmpty {
                    Text(o)
                        .font(overviewFont)
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(overviewLines)
                        .frame(maxWidth: overviewWidth, alignment: .leading)
                }
                HStack(spacing: 16) {
                    actions()
                    if playing {
                        Button { muted.toggle() } label: {
                            Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.circle)
                    }
                }
                .padding(.top, 6)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 40)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var logoWidth: CGFloat {
        #if os(tvOS)
        640
        #else
        520
        #endif
    }
    private var logoHeight: CGFloat {
        #if os(tvOS)
        220
        #else
        170
        #endif
    }
    private var titleSize: CGFloat {
        #if os(tvOS)
        96
        #else
        64
        #endif
    }
    private var overviewWidth: CGFloat {
        #if os(tvOS)
        1000
        #else
        720
        #endif
    }
    private var metaFont: Font {
        #if os(tvOS)
        .title3.weight(.semibold)
        #else
        .headline
        #endif
    }
    private var overviewFont: Font {
        #if os(tvOS)
        .title3
        #else
        .body
        #endif
    }
}

/// Netflix-style primary button: white with black text.
struct PlayButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 26).padding(.vertical, 14)
            .background(.white, in: Capsule())
            .foregroundStyle(.black)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

extension View {
    /// The main action on a billboard: white on tvOS and visionOS, with focus and gaze feedback.
    @ViewBuilder
    func primaryAction() -> some View {
        #if os(tvOS)
        self.buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
        #else
        self.buttonStyle(PlayButtonStyle()).hoverEffect(.highlight)
        #endif
    }
}

enum BillboardMetrics {
    static var height: CGFloat {
        #if os(tvOS)
        760
        #else
        620
        #endif
    }
}
