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

    private var shownImage: String? { image ?? app.posterFallback(kind: kind, tmdb: tmdb, titleID: titleID) }

    var body: some View {
        VStack(alignment: .leading, spacing: titleGap) {
            NavigationLink(value: route ?? .popular) {
                ZStack(alignment: .topLeading) {
                    RemoteImage(path: shownImage)
                        .overlay {
                            if shownImage == nil {
                                Text(title).font(.headline).multilineTextAlignment(.center).padding().foregroundStyle(.secondary)
                            }
                        }
                    if let badge {
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.black.opacity(0.65), in: Capsule())
                            .foregroundStyle(.white)
                            .padding(8)
                    }
                    if let q = app.quality(kind: kind, tmdb: tmdb, titleID: titleID) {
                        QualityChip(label: q).frame(maxWidth: .infinity, alignment: .topTrailing).padding(8)
                    }
                }
                .frame(width: width, height: width * 1.5)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous))
            }
            .cardButton()
            .disabled(route == nil)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium)).lineLimit(1)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
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
                    Text(title).font(.headline).lineLimit(2)
                    if let subtitle { Text(subtitle).font(.caption).opacity(0.85).lineLimit(1) }
                }
                .foregroundStyle(.white)
                .padding(14)
            }
            .frame(width: width, height: width * 9 / 16)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous))
        }
        .cardButton()
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
        VStack(spacing: titleGap) {
            NavigationLink(value: Route.person(id ?? "")) {
                RemoteImage(path: image)
                    .overlay { if image == nil { Image(systemName: "person.fill").font(.largeTitle).foregroundStyle(.secondary) } }
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            }
            .cardButton(corner: size / 2)
            .disabled(id == nil || id?.isEmpty == true)
            Text(name).font(.caption.weight(.medium)).lineLimit(1)
            if let detail { Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
        }
        .frame(width: size + 20)
    }
}

/// A horizontal row of cards with a heading.
struct Shelf<Item: Identifiable, Card: View>: View {
    let title: String
    var subtitle: String? = nil
    let items: [Item]
    @ViewBuilder let card: (Item) -> Card

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(text: title, subtitle: subtitle)
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: Metrics.cardSpacing) {
                        ForEach(items) { card($0) }
                    }
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.vertical, 20)
                }
                .scrollIndicators(.hidden)
                #if os(tvOS)
                .scrollClipDisabled()
                #endif
            }
        }
    }
}

/// A shelf of MediaItem posters.
struct MediaShelf: View {
    let title: String
    var subtitle: String? = nil
    let items: [MediaItem]
    var defaultKind: String? = nil

    var body: some View {
        Shelf(title: title, subtitle: subtitle, items: items) { item in
            let it = defaultKind.map { item.withKind($0) } ?? item
            PosterCard(title: it.displayName, subtitle: subtitleFor(it), image: it.poster ?? it.card_art, badge: it.badge, route: it.route, kind: it.kind, tmdb: it.tmdbID, titleID: it.title_id)
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
            .font(.caption2.weight(.heavy))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(label == "4K" ? AnyShapeStyle(Color(red: 0.85, green: 0.65, blue: 0.2)) : AnyShapeStyle(.black.opacity(0.7)),
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .foregroundStyle(label == "4K" ? .black : .white)
    }
}
