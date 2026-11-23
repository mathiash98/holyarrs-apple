import SwiftUI

/// A ScrollView that also scrolls with mouse and trackpad click-and-drag on visionOS, where the system scroll
/// view does not follow a pointer drag. Only pointer events are handled here (gaze-and-pinch and touch keep the
/// system behaviour), and each drag locks to one direction after a few points, so in a vertical page a sideways
/// drag on a row moves the row and an up-down drag moves the page.
struct PageScrollView<Content: View>: View {
    let axes: Axis.Set
    var position: Binding<ScrollPosition>?
    @ViewBuilder let content: () -> Content

    @State private var own = ScrollPosition()
    @State private var offset: CGPoint = .zero
    @State private var drag: Drag?

    private struct Drag {
        var start: CGPoint
        var startOffset: CGPoint
        var locked: Axis?
    }

    init(_ axes: Axis.Set = .vertical, position: Binding<ScrollPosition>? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.axes = axes
        self.position = position
        self.content = content
    }

    var body: some View {
        #if os(visionOS)
        ScrollView(axes) { content() }
            .scrollPosition(position ?? $own)
            .onScrollGeometryChange(for: CGPoint.self, of: { $0.contentOffset }) { _, new in offset = new }
            .simultaneousGesture(pointerDrag)
        #elseif os(tvOS)
        // Each sideways row is a focus section: pressing up or down from any card reaches the next row,
        // even when no card sits straight above or below.
        Group {
            if let position {
                ScrollView(axes) { content() }.scrollPosition(position)
            } else {
                ScrollView(axes) { content() }
            }
        }
        .modifier(RowFocusSection(on: axes == .horizontal))
        #else
        if let position {
            ScrollView(axes) { content() }.scrollPosition(position)
        } else {
            ScrollView(axes) { content() }
        }
        #endif
    }

    #if os(visionOS)
    private var pointerDrag: some Gesture {
        SpatialEventGesture()
            .onChanged { events in
                guard let e = events.first(where: { $0.kind == .pointer }) else { return }
                if drag == nil { drag = Drag(start: e.location, startOffset: offset, locked: nil) }
                guard var d = drag else { return }
                let dx = e.location.x - d.start.x
                let dy = e.location.y - d.start.y
                if d.locked == nil {
                    guard hypot(dx, dy) > 8 else { return }
                    d.locked = abs(dx) > abs(dy) ? .horizontal : .vertical
                    drag = d
                }
                var pos = position?.wrappedValue ?? own
                switch d.locked {
                case .vertical? where axes.contains(.vertical):
                    pos.scrollTo(y: max(0, d.startOffset.y - dy))
                case .horizontal? where axes.contains(.horizontal):
                    pos.scrollTo(x: max(0, d.startOffset.x - dx))
                default:
                    return
                }
                if let position { position.wrappedValue = pos } else { own = pos }
            }
            .onEnded { _ in drag = nil }
    }
    #endif
}

#if os(tvOS)
private struct RowFocusSection: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.focusSection() } else { content }
    }
}
#endif
