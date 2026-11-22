import SwiftUI

/// Sizes and styles that differ between the headset and the TV.
enum Metrics {
    #if os(tvOS)
    static let posterWidth: CGFloat = 250
    static let wideWidth: CGFloat = 420
    static let gutter: CGFloat = 60
    static let rowSpacing: CGFloat = 40
    static let cardSpacing: CGFloat = 40
    static let corner: CGFloat = 12
    #else
    static let posterWidth: CGFloat = 200
    static let wideWidth: CGFloat = 320
    static let gutter: CGFloat = 40
    static let rowSpacing: CGFloat = 32
    static let cardSpacing: CGFloat = 22
    static let corner: CGFloat = 18
    #endif
    static var posterHeight: CGFloat { posterWidth * 1.5 }
    static var wideHeight: CGFloat { wideWidth * 9 / 16 }
}

extension View {
    /// Card buttons: the system card style on tvOS (focus lift and parallax), a lift on gaze on visionOS.
    @ViewBuilder
    func cardButton(corner: CGFloat = Metrics.corner) -> some View {
        #if os(tvOS)
        self.buttonStyle(.card)
        #else
        // A small scale plus the highlight sheen: clear gaze feedback without growing over the title below.
        self.buttonStyle(.plain)
            .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: corner, style: .continuous))
            .hoverEffect(.highlight)
            .hoverEffect { effect, isActive, _ in effect.scaleEffect(isActive ? 1.04 : 1) }
        #endif
    }

    /// List rows and small tappables: highlight on gaze (visionOS), the system focus look on tvOS.
    @ViewBuilder
    func rowButton(corner: CGFloat = 14) -> some View {
        #if os(tvOS)
        self.buttonStyle(.card)
        #else
        self.buttonStyle(.plain)
            .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: corner, style: .continuous))
            .hoverEffect(.highlight)
        #endif
    }

    /// A panel behind grouped content: glass on visionOS, a soft fill on tvOS.
    @ViewBuilder
    func panel(corner: CGFloat = 24, padding: CGFloat = 20) -> some View {
        #if os(visionOS)
        self.padding(padding)
            .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: corner, style: .continuous))
        #else
        self.padding(padding)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: corner, style: .continuous))
        #endif
    }
}

/// Section heading used above rows.
struct SectionTitle: View {
    let text: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text).font(.title2.bold())
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Metrics.gutter)
    }
}

/// A big heading that scrolls with the page (used instead of a bar title, which floats over content).
struct PageHeading: View {
    let text: String
    var padded = true
    var body: some View {
        Text(text)
            .font(.largeTitle.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, padded ? Metrics.gutter : 0)
    }
}
