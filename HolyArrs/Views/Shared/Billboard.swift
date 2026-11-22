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
    /// Small black pills next to the quality mark: "In library", "HDR10", "Downloading", "Asked · Approved".
    var pills: [String] = []
    /// Live downloads for this title (shown with progress under the pills).
    var downloads: [DownloadRow] = []
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
            // Fades: dark to the left for text, and down into the page.
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
                // Pills first, then the facts; both wrap onto more lines on narrow screens.
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    if let q = app.quality(kind: content.kind, tmdb: content.tmdb, titleID: content.titleID) { QualityChip(label: q) }
                    ForEach(content.pills, id: \.self) { Pill(text: $0) }
                }
                if !content.downloads.isEmpty {
                    DownloadStatus(rows: content.downloads)
                }
                if !content.meta.isEmpty {
                    Text(content.meta.joined(separator: "  ·  "))
                        .font(metaFont)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(2)
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
                FlowLayout(spacing: 14, lineSpacing: 12) {
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

/// The primary billboard button: white with black text.
struct PlayButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .lineLimit(1)
            .fixedSize()
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

/// Secondary billboard buttons: white text on translucent grey, readable over any picture.
struct SecondaryActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 22).padding(.vertical, 14)
            .background(Color(white: 0.38).opacity(configuration.isPressed ? 0.95 : 0.75), in: Capsule())
            .foregroundStyle(.white)
    }
}

extension View {
    /// The secondary actions next to Play (Trailer, More info, Ask, Swiftfin, From start).
    @ViewBuilder
    func secondaryAction() -> some View {
        #if os(tvOS)
        self.buttonStyle(.bordered)
        #else
        self.buttonStyle(SecondaryActionStyle())
            .contentShape(.hoverEffect, Capsule())
            .hoverEffect(.highlight)
        #endif
    }
}

/// A small black label in the billboard's facts row, matching the quality mark.
struct Pill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption2.weight(.heavy))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .foregroundStyle(.white)
            .fixedSize()
    }
}

/// Lays children out left to right and wraps onto new lines when they do not fit (pills, buttons).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let size = v.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            if x > 0, x + size.width > maxWidth {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, maxWidth), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for v in subviews {
            let size = v.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

/// The live download state of a title: label, progress bar, percentage, speed and time left.
struct DownloadStatus: View {
    let rows: [DownloadRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows.prefix(3)) { r in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Image(systemName: r.state == "downloading" ? "arrow.down.circle.fill" : "clock")
                        Text(line(r)).lineLimit(1)
                    }
                    .font(.callout.weight(.semibold))
                    ProgressView(value: min(max(r.progress ?? 0, 0), 1))
                        .tint(.accentColor)
                        .frame(maxWidth: 420)
                }
            }
            if rows.count > 3 {
                Text("+ \(rows.count - 3) more downloading").font(.caption).foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(12)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .foregroundStyle(.white)
    }

    private func line(_ r: DownloadRow) -> String {
        var p: [String] = [r.label ?? r.state?.capitalized ?? "Downloading"]
        if let c = r.covers, !c.isEmpty { p.append(c) }
        p.append(String(format: "%.0f%%", (r.progress ?? 0) * 100))
        let sp = Fmt.speed(r.speed)
        if !sp.isEmpty { p.append(sp) }
        if let eta = r.eta { p.append("\(Fmt.duration(eta)) left") }
        return p.joined(separator: " · ")
    }
}
