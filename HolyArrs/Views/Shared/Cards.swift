import SwiftUI

/// A poster card that pushes a route when chosen.
struct PosterCard: View {
    @Environment(AppModel.self) private var app
    let title: String
    var subtitle: String? = nil
    let image: String?
    var badge: String? = nil
    var route: Route?
    var width: CGFloat = Metrics.posterWidth
    var kind: String? = nil
    var tmdb: String? = nil
    var titleID: Int? = nil
    /// The wide picture used as the page backdrop while this card is focused.
    var backdrop: String? = nil
    /// For the corner symbol (downloaded / asked / can ask).
    var inLibrary: Bool? = nil
    var ask: AskBrief? = nil

    private var shownImage: String? { image ?? app.posterFallback(kind: kind, tmdb: tmdb, titleID: titleID) }

    var body: some View {
        VStack(alignment: .leading, spacing: titleGap) {
            NavigationLink(value: route ?? .popular) {
                ZStack(alignment: .topLeading) {
                    RemoteImage(path: shownImage)
                        .overlay {
                            if shownImage == nil {
                                Text(title).font(.xHeadline).multilineTextAlignment(.center).padding().foregroundStyle(.secondary)
                            }
                        }
                    if let badge {
                        Text(badge)
                            .font(.xCaption2.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.black.opacity(0.65), in: Capsule())
                            .foregroundStyle(.white)
                            .padding(8)
                    }
                    if let q = app.quality(kind: kind, tmdb: tmdb, titleID: titleID) {
                        QualityChip(label: q).frame(maxWidth: .infinity, alignment: .topTrailing).padding(8)
                    }
                    if let icon = app.statusIcon(kind: kind, tmdb: tmdb, titleID: titleID, inLibrary: inLibrary, ask: ask) {
                        CornerIcon(name: icon)
                    }
                }
                .frame(width: width, height: width * 1.5)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous))
            }
            .cardButton()
            .ambientOnFocus(backdrop)
            .disabled(route == nil)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.xCallout.weight(.medium)).lineLimit(1)
                if let subtitle { Text(subtitle).font(.xCaption).foregroundStyle(.secondary).lineLimit(1) }
            }
            .frame(width: width, alignment: .leading)
        }
    }
}

private var titleGap: CGFloat {
    #if os(tvOS)
    26
    #else
    14
    #endif
}

/// A 16:9 card with a title over the picture.
struct WideCard: View {
    @Environment(AppModel.self) private var app
    let title: String
    var subtitle: String? = nil
    let image: String?
    var route: Route?
    var width: CGFloat = Metrics.wideWidth
    var kind: String? = nil
    var titleID: Int? = nil

    var body: some View {
        NavigationLink(value: route ?? .popular) {
            ZStack(alignment: .bottomLeading) {
                RemoteImage(path: image)
                LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)
                if let q = app.quality(kind: kind, tmdb: nil, titleID: titleID) {
                    QualityChip(label: q).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(10)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.xHeadline).lineLimit(2)
                    if let subtitle { Text(subtitle).font(.xCaption).opacity(0.85).lineLimit(1) }
                }
                .foregroundStyle(.white)
                .padding(14)
            }
            .frame(width: width, height: width * 9 / 16)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous))
        }
        .cardButton()
        .ambientOnFocus(image)
        .disabled(route == nil)
    }
}

/// A round portrait for cast and people.
struct PersonCard: View {
    let name: String
    var detail: String? = nil
    let image: String?
    let id: String?
    #if os(tvOS)
    var size: CGFloat = 160
    #else
    var size: CGFloat = 120
    #endif

    var body: some View {
        #if os(tvOS)
        // The whole card is one focusable link: the round photo grows and gets a white ring, no square platter.
        NavigationLink(value: Route.person(id ?? "")) {
            PersonCardLabel(name: name, detail: detail, image: image, size: size)
        }
        .buttonStyle(PersonFocusStyle())
        .disabled(id == nil || id?.isEmpty == true)
        #else
        VStack(spacing: titleGap) {
            NavigationLink(value: Route.person(id ?? "")) {
                RemoteImage(path: image)
                    .overlay { if image == nil { Image(systemName: "person.fill").font(.xLargeTitle).foregroundStyle(.secondary) } }
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            }
            .cardButton(corner: size / 2)
            .disabled(id == nil || id?.isEmpty == true)
            Text(name).font(.xCaption.weight(.medium)).lineLimit(1)
            if let detail { Text(detail).font(.xCaption2).foregroundStyle(.secondary).lineLimit(1) }
        }
        .frame(width: size + 20)
        #endif
    }
}

#if os(tvOS)
/// Photo, name and role, tight together. Reads the button's focus to draw the ring and brighten the text.
private struct PersonCardLabel: View {
    let name: String
    let detail: String?
    let image: String?
    let size: CGFloat
    @Environment(\.isFocused) private var focused

    var body: some View {
        VStack(spacing: 0) {
            RemoteImage(path: image)
                .overlay { if image == nil { Image(systemName: "person.fill").font(.xLargeTitle).foregroundStyle(.secondary) } }
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay { Circle().strokeBorder(.white, lineWidth: focused ? 4 : 0) }
                .shadow(color: .black.opacity(focused ? 0.5 : 0), radius: 14, y: 8)
                .scaleEffect(focused ? 1.1 : 1, anchor: .bottom)
            VStack(spacing: 2) {
                Text(name).font(.xCaption.weight(.semibold)).foregroundStyle(focused ? .white : .white.opacity(0.85))
                if let detail, !detail.isEmpty {
                    Text(detail).font(.xCaption2).foregroundStyle(.white.opacity(focused ? 0.75 : 0.55))
                }
            }
            .lineLimit(1)
            .multilineTextAlignment(.center)
            .padding(.top, 14)
        }
        .frame(width: size + 30)
        .animation(.easeOut(duration: 0.18), value: focused)
    }
}

/// No platter: the label draws its own focus look.
private struct PersonFocusStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.75 : 1)
    }
}
#endif

/// A horizontal row of cards with a heading.
struct Shelf<Item: Identifiable, Card: View>: View {
    let title: String
    var subtitle: String? = nil
    let items: [Item]
    @ViewBuilder let card: (Item) -> Card

    /// Scroll state for the visionOS arrows (a mouse wheel cannot scroll sideways) and pointer drags.
    @State private var position = ScrollPosition()
    @State private var geo = ShelfGeometry()

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .bottom) {
                    SectionTitle(text: title, subtitle: subtitle)
                    #if os(visionOS)
                    if items.count > 3 { arrows.padding(.trailing, Metrics.gutter) }
                    #endif
                }
                PageScrollView(.horizontal, position: $position) {
                    LazyHStack(alignment: .top, spacing: Metrics.cardSpacing) {
                        ForEach(items) { card($0) }
                    }
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.vertical, 20)
                }
                .onScrollGeometryChange(for: ShelfGeometry.self, of: {
                    ShelfGeometry(offset: $0.contentOffset.x, visible: $0.containerSize.width, content: $0.contentSize.width)
                }) { _, g in geo = g }
                #if os(tvOS)
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                #else
                // A visible bar that can be dragged with a mouse or trackpad.
                .scrollIndicators(.visible)
                #endif
            }
        }
    }

    #if os(visionOS)
    private var arrows: some View {
        HStack(spacing: 10) {
            Button { step(-1) } label: { Image(systemName: "chevron.left") }
                .disabled(geo.offset <= 1)
            Button { step(1) } label: { Image(systemName: "chevron.right") }
                .disabled(geo.offset >= geo.content - geo.visible - 1)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .controlSize(.small)
    }

    /// Moves by most of a screen width, like paging a row.
    private func step(_ dir: CGFloat) {
        let target = min(max(geo.offset + dir * geo.visible * 0.85, 0), max(0, geo.content - geo.visible))
        withAnimation(.smooth) { position.scrollTo(x: target) }
    }
    #endif
}

struct ShelfGeometry: Equatable {
    var offset: CGFloat = 0
    var visible: CGFloat = 0
    var content: CGFloat = 0
}

/// A shelf of MediaItem posters.
struct MediaShelf: View {
    let title: String
    var subtitle: String? = nil
    let items: [MediaItem]
    var defaultKind: String? = nil
    /// Posters, or landscape tiles with the title's logo. Auto picks tiles when the row has the art.
    enum Style { case auto, posters, tiles }
    var style: Style = .auto

    private var useTiles: Bool {
        switch style {
        case .posters: return false
        case .tiles: return true
        case .auto:
            guard !items.isEmpty else { return false }
            return Double(items.filter { $0.card_art != nil || $0.backdrop != nil }.count) / Double(items.count) >= 0.6
                && items.contains { $0.card_logo != nil }
        }
    }

    var body: some View {
        if useTiles {
            Shelf(title: title, subtitle: subtitle, items: items) { item in
                LogoCard(item: defaultKind.map { item.withKind($0) } ?? item)
            }
        } else {
            Shelf(title: title, subtitle: subtitle, items: items) { item in
                let it = defaultKind.map { item.withKind($0) } ?? item
                PosterCard(title: it.displayName, subtitle: subtitleFor(it), image: it.poster ?? it.card_art, badge: it.badge, route: it.route, kind: it.kind, tmdb: it.tmdbID, titleID: it.title_id, backdrop: it.backdrop ?? it.card_art, inLibrary: it.in_library, ask: it.ask)
            }
        }
    }

    private func subtitleFor(_ it: MediaItem) -> String? {
        if let w = it.what { return w }
        if let f = it.fresh?.text { return f }
        if let c = it.characters?.first, !c.isEmpty { return c }
        var p: [String] = []
        if let y = it.year { p.append(String(y)) }
        if let k = it.kind { p.append(k == "show" ? "Show" : "Movie") }
        return p.isEmpty ? nil : p.joined(separator: " · ")
    }
}

/// A small 4K / FHD / HD / SD mark for what is on disk.
struct QualityChip: View {
    let label: String
    var body: some View {
        Text(label)
            .font(.xCaption2.weight(.heavy))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(label == "4K" ? AnyShapeStyle(Color(red: 0.85, green: 0.65, blue: 0.2)) : AnyShapeStyle(.black.opacity(0.7)),
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .foregroundStyle(label == "4K" ? .black : .white)
    }
}

/// A landscape tile: the title's art with its logo on top, status marks and an optional progress bar.
struct TileCard: View {
    @Environment(AppModel.self) private var app
    let title: String
    var line: String? = nil
    let art: String?
    var logo: String? = nil
    var badge: String? = nil
    var progress: Double? = nil
    var route: Route? = nil
    var action: (() -> Void)? = nil
    var kind: String? = nil
    var tmdb: String? = nil
    var titleID: Int? = nil
    var ambient: String? = nil
    var width: CGFloat = Metrics.wideWidth
    /// Called when the tile gains or loses focus (Apple TV) or the pointer (iPad, Mac).
    var onFocusChange: ((Bool) -> Void)? = nil
    /// A small status symbol in the bottom-right corner (downloaded, asked, can ask). Worked out from the
    /// title when not given (not on Jellyfin play tiles, which have an action).
    var cornerIcon: String? = nil
    var inLibrary: Bool? = nil
    var ask: AskBrief? = nil
    /// Lets a parent move focus to this tile (the Featured row selects its first tile on Apple TV).
    var focusBinding: FocusState<String?>.Binding? = nil
    var focusID: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let action {
                    Button(action: action) { tile }
                } else {
                    NavigationLink(value: route ?? .popular) { tile }
                        .disabled(route == nil)
                }
            }
            .cardButton()
            .ambientOnFocus(ambient ?? art)
            .modifier(FocusReport(action: onFocusChange))
            .modifier(BoundFocus(binding: focusBinding, id: focusID))
            if let line, !line.isEmpty {
                Text(line).font(.xCaption).foregroundStyle(.secondary).lineLimit(1).frame(width: width, alignment: .leading)
            }
        }
    }

    private var tile: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(path: art)
            LinearGradient(colors: [.clear, .clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
            if let logo {
                RemoteImage(path: logo, contentMode: .fit)
                    .frame(maxWidth: width * 0.55, maxHeight: width * 0.2, alignment: .bottomLeading)
                    .shadow(color: .black.opacity(0.7), radius: 8)
                    .padding(14)
                    .padding(.bottom, progress != nil ? 8 : 0)
            } else {
                Text(title).font(.xHeadline.bold()).foregroundStyle(.white).lineLimit(2).shadow(radius: 6)
                    .padding(14)
                    .padding(.bottom, progress != nil ? 8 : 0)
            }
            VStack {
                HStack(alignment: .top) {
                    if let badge {
                        Text(badge)
                            .font(.xCaption2.weight(.bold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.accentColor, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    if let q = app.quality(kind: kind, tmdb: tmdb, titleID: titleID) { QualityChip(label: q) }
                }
                Spacer()
            }
            .padding(10)
            if let icon = cornerIcon ?? (action == nil ? app.statusIcon(kind: kind, tmdb: tmdb, titleID: titleID, inLibrary: inLibrary, ask: ask) : nil) {
                CornerIcon(name: icon)
            }
            if let progress {
                GeometryReader { g in
                    Rectangle().fill(.white.opacity(0.25))
                        .overlay(alignment: .leading) { Rectangle().fill(Color.accentColor).frame(width: g.size.width * progress) }
                }
                .frame(height: 4)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .frame(width: width, height: width * 9 / 16)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous))
    }
}

/// A landscape tile for an Explore item.
struct LogoCard: View {
    let item: MediaItem
    var width: CGFloat = Metrics.wideWidth

    var body: some View {
        TileCard(title: item.displayName, line: line, art: item.card_art ?? item.backdrop ?? item.poster, logo: item.card_logo,
                 badge: item.in_library == true || item.title_id != nil ? nil : (item.ask?.state_label ?? item.ask?.state),
                 route: item.route, kind: item.kind, tmdb: item.tmdbID, titleID: item.title_id,
                 ambient: item.backdrop ?? item.card_art, width: width, inLibrary: item.in_library, ask: item.ask)
    }

    private var line: String? {
        if let w = item.what { return w }
        if let f = item.fresh?.text { return f }
        var p: [String] = []
        if let y = item.year { p.append(String(y)) }
        if let k = item.kind { p.append(k == "show" ? "Series" : "Movie") }
        return p.isEmpty ? nil : p.joined(separator: " · ")
    }
}

/// The white status symbol in a card's bottom-right corner.
struct CornerIcon: View {
    let name: String
    var body: some View {
        Image(systemName: name)
            .font(.xHeadline)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.85), radius: 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(10)
    }
}

/// Binds a card's button to a parent's focus state when one is given.
struct BoundFocus: ViewModifier {
    let binding: FocusState<String?>.Binding?
    let id: String?
    func body(content: Content) -> some View {
        if let binding, let id { content.focused(binding, equals: id) } else { content }
    }
}
