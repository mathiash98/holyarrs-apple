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
    /// The ask on a title that is not in the library (for the Ask / Asked button).
    var ask: AskBrief? = nil
}

extension HeroSlide {
    /// TMDB has junk entries such as "Ticket+1-888-…" phone-number titles.
    static func looksLikeSpam(_ name: String) -> Bool {
        name.filter(\.isNumber).count >= 7 || name.contains("+1-") || name.lowercased().contains("call ")
    }

    /// A slide for an Explore / Discover item: in the library or a new recommendation.
    init(item m: MediaItem, headline: String? = nil) {
        let have = m.in_library == true || m.title_id != nil
        self.init(id: "item:\(m.id)", content: BillboardContent(
            kind: m.kind, tmdb: m.tmdbID, titleID: m.title_id, name: m.displayName,
            logo: m.card_logo, backdrop: m.backdrop ?? m.card_art,
            headline: headline,
            meta: [m.year.map(String.init), m.kind == "show" ? "Series" : "Movie", Self.stars(m.score), m.fresh?.text].compactMap { $0 },
            overview: m.overview, route: m.route),
            inLibrary: have, kind: m.kind, tmdb: m.tmdbID, titleID: m.title_id, name: m.displayName, route: m.route, ask: m.ask)
    }

    /// "★ 7.4" from a 0–10 score (TMDB's average).
    static func stars(_ score: Double?) -> String? {
        guard let s = score, s > 0 else { return nil }
        return String(format: "★ %.1f", s)
    }

    /// Items with a logo and wide art, without junk, de-duplicated, movies and shows taking turns.
    static func mix(_ items: [MediaItem], limit: Int) -> [MediaItem] {
        var seen = Set<String>()
        let usable = items.filter {
            $0.card_logo != nil && ($0.backdrop ?? $0.card_art) != nil && !looksLikeSpam($0.displayName)
                && seen.insert("\($0.kind ?? ""):\($0.tmdbID ?? $0.displayName)").inserted
        }
        var movies = usable.filter { $0.kind != "show" }[...]
        var shows = usable.filter { $0.kind == "show" }[...]
        var out: [MediaItem] = []
        while out.count < limit, !(movies.isEmpty && shows.isEmpty) {
            if let m = movies.popFirst() { out.append(m) }
            if out.count < limit, let s = shows.popFirst() { out.append(s) }
        }
        return out
    }
}

/// The top billboard with its "Featured" row right under it, like Netflix: moving focus along the row
/// switches the billboard to that title and starts its trailer; clicking a tile opens the title. The billboard
/// has no buttons. Each trailer plays once, then the picture stays; when the row does not have focus the
/// billboard moves on to the next title after the trailer (or a short while without one).
struct BillboardCarousel: View {
    let slides: [HeroSlide]
    var height: CGFloat = BillboardMetrics.height
    var rowTitle = "Featured"
    /// False while the page is scrolled down to other rows: the trailer pauses.
    var active = true
    /// Called when the Featured row gets focus, so the page can stay scrolled to the top (the trailer stays
    /// full screen behind the row instead of being pushed up).
    var onRowFocus: (() -> Void)? = nil

    @State private var index = 0
    /// Bumped by a manual change, so the auto-advance timer starts over.
    @State private var tick = 0
    @FocusState private var tileFocus: String?
    @State private var focusedOnce = false

    var body: some View {
        if !slides.isEmpty {
            let s = slides[min(index, slides.count - 1)]
            VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                // No buttons: clicking a Featured tile opens the title, where Play or Ask is already selected.
                Billboard(content: s.content, height: heroHeight, contentBottom: textBottom, muteButton: false, trailerPaused: !active) {
                    EmptyView()
                }
                .ignoresSafeArea(edges: .top)
                .padding(.bottom, -overlap)
                if slides.count > 1 {
                    Shelf(title: rowTitle, items: slides) { slide in
                        let i = slides.firstIndex { $0.id == slide.id } ?? 0
                        TileCard(title: slide.name, line: slide.content.meta.first,
                                 art: slide.content.backdrop, logo: slide.content.logo,
                                 badge: i == index ? "Now showing" : nil,
                                 route: slide.route, kind: slide.kind, tmdb: slide.tmdb, titleID: slide.titleID,
                                 cornerIcon: statusIcon(slide),
                                 focusBinding: $tileFocus, focusID: slide.id)
                    }
                }
            }
            .onChange(of: tileFocus) { _, f in
                guard let f else { return }
                onRowFocus?()
                if let i = slides.firstIndex(where: { $0.id == f }), i != index { index = i; tick += 1 }
            }
            #if os(tvOS)
            .onAppear {
                // Start on the first Featured tile, like Netflix (not on the tab bar).
                guard !focusedOnce else { return }
                focusedOnce = true
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    tileFocus = slides.first?.id
                }
            }
            #endif
            .task(id: "\(index)/\(tick)/\(slides.count)") {
                guard slides.count > 1 else { return }
                try? await Task.sleep(for: .seconds(12))
                // Let a running trailer finish, then keep the picture a moment.
                let key = "\(s.kind ?? "")/\(s.tmdb ?? "")"
                while !Task.isCancelled, TrailerPlayers.shared.isRunning(key) {
                    try? await Task.sleep(for: .seconds(2))
                }
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled, tileFocus == nil, active else { return }
                index = (index + 1) % slides.count
            }
        }
    }

    /// Downloaded (in the library), asked by me, or something I can ask for.
    private func statusIcon(_ s: HeroSlide) -> String {
        if s.inLibrary { return "arrow.down.circle.fill" }
        if let a = s.ask, a.mine == true, a.state == "asked" || a.state == "approved" { return "checkmark.circle.fill" }
        return "plus.circle"
    }

    // Apple TV: the picture fills the whole screen and the Featured row sits over its bottom edge, so the
    // trailer stays as large as possible. Elsewhere the row starts just under a tall picture.
    #if os(tvOS)
    private var heroHeight: CGFloat { slides.count > 1 ? BillboardMetrics.fullScreen : height }
    private var overlap: CGFloat { slides.count > 1 ? 350 : 90 }
    private var textBottom: CGFloat { slides.count > 1 ? 380 : 110 }
    #else
    private var heroHeight: CGFloat { height }
    private var overlap: CGFloat { 90 }
    private var textBottom: CGFloat { 110 }
    #endif
}
