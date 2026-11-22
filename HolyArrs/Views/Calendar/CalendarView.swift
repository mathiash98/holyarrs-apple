import SwiftUI

/// Calendar as cards: upcoming episodes and movie dates, grouped by day.
struct CalendarView: View {
    @Environment(AppModel.self) private var app

    enum Range: String, CaseIterable, Identifiable {
        case week = "Next 7 days", month = "Next 30 days", quarter = "Next 90 days", past = "Past 14 days"
        var id: String { rawValue }
    }

    @State private var range: Range = .month
    @State private var titles = "all"
    @State private var state: Loadable<CalendarAnswer> = .loading

    var body: some View {
        PageScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 20) {
                    Picker("Range", selection: $range) {
                        ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
                    }
                    #if os(tvOS)
                    .pickerStyle(.segmented)
                    #else
                    .pickerStyle(.menu)
                    #endif
                    Picker("Show", selection: $titles) {
                        Text("All").tag("all")
                        Text("Movies").tag("movies")
                        Text("Shows").tag("shows")
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 480)
                    Spacer()
                }
                .padding(.horizontal, Metrics.gutter)

                LoadView(state: state, retry: load) { a in
                    let groups = group(a.dates ?? [])
                    if groups.isEmpty {
                        EmptyNote(title: "Nothing on the calendar", systemImage: "calendar", detail: "Follow titles or add them to the library to see their dates here.")
                    } else {
                        LazyVStack(alignment: .leading, spacing: 30) {
                            ForEach(groups, id: \.day) { g in
                                VStack(alignment: .leading, spacing: 14) {
                                    SectionTitle(text: dayTitle(g.day), subtitle: "\(g.entries.count) item\(g.entries.count == 1 ? "" : "s")")
                                    PageScrollView(.horizontal) {
                                        LazyHStack(spacing: Metrics.cardSpacing) {
                                            ForEach(g.entries) { e in CalendarCard(e: e) }
                                        }
                                        .padding(.horizontal, Metrics.gutter)
                                        .padding(.vertical, 16)
                                    }
                                    .scrollIndicators(.hidden)
                                    #if os(tvOS)
                                    .scrollClipDisabled()
                                    #endif
                                }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 20)
        }
        .task(id: "\(range.rawValue)|\(titles)") { await load() }
    }

    private struct DayGroup { let day: String; let entries: [CalendarEntry] }

    private func group(_ es: [CalendarEntry]) -> [DayGroup] {
        let sorted = es.sorted { ($0.when ?? .distantFuture) < ($1.when ?? .distantFuture) }
        var out: [DayGroup] = []
        for e in sorted {
            if let last = out.last, last.day == e.dayKey {
                out[out.count - 1] = DayGroup(day: last.day, entries: last.entries + [e])
            } else {
                out.append(DayGroup(day: e.dayKey, entries: [e]))
            }
        }
        return range == .past ? out.reversed() : out
    }

    private func dayTitle(_ ymd: String) -> String {
        guard let d = HADate.parse(ymd) else { return ymd }
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInTomorrow(d) { return "Tomorrow" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        return d.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    private func load() async {
        guard let c = app.client else { return }
        let now = Date()
        let cal = Calendar.current
        let (from, to): (Date, Date) = switch range {
        case .week: (now, cal.date(byAdding: .day, value: 7, to: now)!)
        case .month: (now, cal.date(byAdding: .day, value: 30, to: now)!)
        case .quarter: (now, cal.date(byAdding: .day, value: 90, to: now)!)
        case .past: (cal.date(byAdding: .day, value: -14, to: now)!, now)
        }
        do {
            state = .loaded(try await c.get("/calendar?from=\(HADate.ymd(from))&to=\(HADate.ymd(to))&titles=\(titles)"))
        } catch is CancellationError {
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

struct CalendarCard: View {
    let e: CalendarEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink(value: e.route ?? .popular) {
                ZStack(alignment: .bottomLeading) {
                    RemoteImage(path: e.still ?? e.backdrop ?? e.banner ?? e.poster)
                    LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.name ?? "").font(.headline).lineLimit(1)
                            Text(line).font(.caption).lineLimit(1).opacity(0.9)
                        }
                        Spacer()
                        Text(kindLabel)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.white.opacity(0.2), in: Capsule())
                    }
                    .foregroundStyle(.white)
                    .padding(14)
                }
                .frame(width: Metrics.wideWidth, height: Metrics.wideHeight)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous))
            }
            .cardButton()
            .disabled(e.route == nil)
            if let t = timeText { Text(t).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private var line: String {
        if let s = e.season, let ep = e.episode {
            return ["S\(s)E\(ep)", e.episode_name, e.network].compactMap { $0 }.joined(separator: " · ")
        }
        if let a = e.album { return a }
        return [e.year.map(String.init), Fmt.runtime(e.runtime)].compactMap { $0 }.joined(separator: " · ")
    }

    private var kindLabel: String {
        switch e.kind {
        case "physical": "Blu-ray"
        case "digital": "Digital"
        case "cinema", "theatrical": "Cinema"
        case "episode", "show": e.episode == 1 ? "Premiere" : "Episode"
        case "album": "Album"
        default: (e.kind ?? "").capitalized
        }
    }

    private var timeText: String? {
        guard e.timed == true, let d = e.when else { return nil }
        return d.formatted(date: .omitted, time: .shortened)
    }
}
