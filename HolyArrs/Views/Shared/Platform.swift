import SwiftUI

/// Sizes and styles that differ between the headset, the TV, the iPad and the iPhone.
enum Metrics {
    /// iPhone (compact screens) get smaller cards and margins.
    static var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }
    #if os(tvOS)
    static let posterWidth: CGFloat = 250
    static let wideWidth: CGFloat = 420
    static let gutter: CGFloat = 60
    static let rowSpacing: CGFloat = 40
    static let cardSpacing: CGFloat = 40
    static let corner: CGFloat = 12
    #else
    static var posterWidth: CGFloat { isPhone ? 108 : 200 }
    static var wideWidth: CGFloat { isPhone ? 260 : 320 }
    static var gutter: CGFloat { isPhone ? 16 : 40 }
    static var rowSpacing: CGFloat { isPhone ? 22 : 32 }
    static var cardSpacing: CGFloat { isPhone ? 12 : 22 }
    static var corner: CGFloat { isPhone ? 12 : 18 }
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
        #if os(visionOS)
        // A small scale plus the highlight sheen: clear gaze feedback without growing over the title below.
        self.buttonStyle(TapThroughButtonStyle())
            .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: corner, style: .continuous))
            .hoverEffect(.highlight)
            .hoverEffect { effect, isActive, _ in effect.scaleEffect(isActive ? 1.04 : 1) }
        #else
        self.buttonStyle(.plain)
            .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: corner, style: .continuous))
            .hoverEffect(.lift)
        #endif
        #endif
    }

    /// List rows and small tappables: highlight on gaze (visionOS), the system focus look on tvOS.
    @ViewBuilder
    func rowButton(corner: CGFloat = 14) -> some View {
        #if os(tvOS)
        self.buttonStyle(.card)
        #elseif os(visionOS)
        self.buttonStyle(TapThroughButtonStyle())
            .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: corner, style: .continuous))
            .hoverEffect(.highlight)
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
            Text(text).font(.xTitle2.bold())
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle).font(.xCallout).foregroundStyle(.secondary)
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
            .font(.xLargeTitle.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, padded ? Metrics.gutter : 0)
    }
}

/// Triggers on a tap instead of a press. A press claims a mouse or trackpad click at once, so click-and-drag that
/// starts on a card never scrolls; a tap gesture gives up as soon as the pointer moves, letting the scroll view
/// take the drag. Gaze-and-pinch and touch still trigger it like any button.
struct TapThroughButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .onTapGesture { configuration.trigger() }
            .accessibilityAddTraits(.isButton)
    }
}
