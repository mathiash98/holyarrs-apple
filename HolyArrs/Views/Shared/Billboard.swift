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
    /// A bold line above the overview, such as "New movie" or "New episodes".
    var headline: String?
    /// Age rating shown on the right edge, such as "TV-MA".
    var rating: String?
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
            LinearGradient(colors: [.clear, .clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)

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
                if let h = content.headline, !h.isEmpty {
                    Text(h).font(headlineFont).foregroundStyle(.white)
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
                .tint(.white)
                .padding(.top, 6)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 110)

            if let r = content.rating, !r.isEmpty {
                HStack(spacing: 0) {
                    Rectangle().fill(.white.opacity(0.8)).frame(width: 3)
                    Text(r).font(metaFont).padding(.horizontal, 14).padding(.vertical, 6)
                }
                .fixedSize()
                .background(.black.opacity(0.35))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.bottom, 130)
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.82), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
        .onAppear { if let b = content.backdrop { app.ambient = b } }
        .onChange(of: content.backdrop) { _, b in if let b { app.ambient = b } }
    }

    private var logoWidth: CGFloat {
        #if os(tvOS)
        640
        #else
        Metrics.isPhone ? 260 : 520
        #endif
    }
    private var logoHeight: CGFloat {
        #if os(tvOS)
        220
        #else
        Metrics.isPhone ? 90 : 170
        #endif
    }
    private var titleSize: CGFloat {
        #if os(tvOS)
        96
        #else
        Metrics.isPhone ? 38 : 64
        #endif
    }
    private var overviewWidth: CGFloat {
        #if os(tvOS)
        1000
        #else
        Metrics.isPhone ? .infinity : 720
        #endif
    }
    private var metaFont: Font {
        #if os(tvOS)
        .title3.weight(.semibold)
        #else
        Metrics.isPhone ? .subheadline.weight(.semibold) : .headline
        #endif
    }
    private var headlineFont: Font {
        #if os(tvOS)
        .title2.bold()
        #else
        Metrics.isPhone ? .headline : .title3.bold()
        #endif
    }
    private var overviewFont: Font {
        #if os(tvOS)
        .title3
        #else
        Metrics.isPhone ? .callout : .body
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
        Metrics.isPhone ? 560 : 620
        #endif
    }
}
