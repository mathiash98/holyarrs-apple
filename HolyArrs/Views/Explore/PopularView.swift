import SwiftUI

/// New & Popular (`/explore/new`): top 10 rows, new on streaming services and the release rail.
struct PopularView: View {
    @Environment(AppModel.self) private var app
    @State private var type = "all"
    @State private var state: Loadable<NewAnswer> = .loading
    @State private var extraRows: [ExploreRow] = []
    @State private var page = 0
    @State private var more = false

    var body: some View {
        PageScrollView {
            VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                PageHeading(text: "New & Popular")
                Picker("Type", selection: $type) {
                    Text("All").tag("all")
                    Text("Movies").tag("movies")
                    Text("Shows").tag("shows")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 520)
                .padding(.horizontal, Metrics.gutter)

                switch state {
                case .loading: ProgressView().frame(maxWidth: .infinity, minHeight: 300)
                case let .failed(m): ErrorView(message: m) { await load() }.frame(minHeight: 300)
                case let .loaded(n):
                    if let hero = n.hero, !hero.isEmpty { HeroCarousel(items: hero) }
                    ForEach((n.rows ?? []) + extraRows) { r in
                        if r.type?.hasPrefix("np_top") == true {
                            Shelf(title: r.title ?? "", items: Array((r.items ?? []).enumerated()).map { Ranked(rank: $0.offset + 1, item: $0.element) }) { rk in
                                RankedCard(rank: rk.rank, item: rk.item)
                            }
                        } else {
                            MediaShelf(title: r.title ?? "", subtitle: r.subtitle, items: r.items ?? [])
                        }
                    }
                    ForEach(n.rail ?? []) { day in
                        MediaShelf(title: dayTitle(day.day), items: day.items ?? [])
                    }
                    if more {
                        Button {
                            Task { await loadMore() }
                        } label: {
                            Label("Show more", systemImage: "chevron.down").frame(maxWidth: .infinity).padding()
                        }
                        .rowButton()
                        .padding(.horizontal, Metrics.gutter)
                    }
                }
            }
            .padding(.vertical, 20)
        }
        .task(id: type) { await load() }
    }

    private func dayTitle(_ s: String) -> String {
        guard let d = HADate.parse(s) else { return s }
        if Calendar.current.isDateInToday(d) { return "Today" }
        if Calendar.current.isDateInYesterday(d) { return "Yesterday" }
        return d.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    private func load() async {
        guard let c = app.client else { return }
        state = .loading
        extraRows = []
        page = 0
        do {
            let n: NewAnswer = try await c.get("/explore/new?type=\(type)&page=0")
            state = .loaded(n)
            more = n.more ?? false
        } catch is CancellationError {
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func loadMore() async {
        guard let c = app.client else { return }
        let next = page + 1
        if let n: NewAnswer = try? await c.get("/explore/new?type=\(type)&page=\(next)") {
            extraRows += (n.rows ?? []).filter { r in !extraRows.contains { $0.id == r.id } }
            page = next
            more = n.more ?? false
        } else { more = false }
    }
}

struct Ranked: Identifiable {
    let rank: Int
    let item: MediaItem
    var id: String { "\(rank)-\(item.id)" }
}

struct RankedCard: View {
    let rank: Int
    let item: MediaItem
    var body: some View {
        HStack(alignment: .bottom, spacing: -16) {
            Text("\(rank)")
                .font(.system(size: 120, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.18))
                .frame(width: 100, alignment: .trailing)
            PosterCard(title: item.displayName, subtitle: item.streaming?.name ?? item.fresh?.text, image: item.poster, badge: item.badge, route: item.route, kind: item.kind, tmdb: item.tmdbID, titleID: item.title_id)
        }
    }
}
