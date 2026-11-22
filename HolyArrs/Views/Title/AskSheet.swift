import SwiftUI

/// Ask for a movie, or for a show with a season choice. Sends POST /asks.
struct AskSheet: View {
    @Environment(AppModel.self) private var app
    let kind: String
    let tmdb: String
    let name: String
    var year: Int? = nil
    var poster: String? = nil
    let seasons: [TitleMeta.Season]
    let done: (Bool) -> Void

    enum Scope: String, CaseIterable, Identifiable {
        case whole, pick, future
        var id: String { rawValue }
        var title: String {
            switch self {
            case .whole: "Whole show"
            case .pick: "Choose seasons"
            case .future: "New episodes"
            }
        }
        var detail: String {
            switch self {
            case .whole: "Every season, kept up to date"
            case .pick: "Only the seasons you pick"
            case .future: "Episodes that air from now on"
            }
        }
        var icon: String {
            switch self {
            case .whole: "square.stack.3d.up.fill"
            case .pick: "checklist"
            case .future: "calendar.badge.clock"
            }
        }
    }

    @State private var scope: Scope = .whole
    @State private var picked: Set<Int> = []
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            header
            if kind == "show" {
                scopeCards
                if scope == .pick { seasonGrid }
            } else {
                Text("HolyArrs looks for this movie once the request is approved.")
                    .font(.body).foregroundStyle(.secondary)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.yellow)
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(outerPadding)
        #if os(visionOS)
        .frame(width: 760, height: kind == "show" ? (scope == .pick ? 660 : 400) : 300)
        .animation(.smooth, value: scope)
        #else
        .frame(maxWidth: 1300)
        #endif
        .disabled(busy)
    }

    // MARK: Parts

    private var header: some View {
        HStack(spacing: 20) {
            if poster != nil {
                RemoteImage(path: poster)
                    .frame(width: posterW, height: posterW * 1.5)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Ask for").font(.callout).foregroundStyle(.secondary)
                Text(name).font(.title.bold()).lineLimit(2)
                Text([year.map(String.init), kind == "show" ? "TV show" : "Movie"].compactMap { $0 }.joined(separator: " · "))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var scopeCards: some View {
        let layout = Metrics.isPhone ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 16))
        return layout {
            ForEach(Scope.allCases) { s in
                Button {
                    scope = s
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: s.icon).font(.title2)
                        Text(s.title).font(.headline).lineLimit(2).minimumScaleFactor(0.8)
                        Text(s.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, minHeight: cardHeight, alignment: .topLeading)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(scope == s ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(scope == s ? Color.accentColor : .clear, lineWidth: 2)
                    )
                }
                .rowButton(corner: 18)
            }
        }
    }

    private var seasonGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Seasons").font(.headline)
                Spacer()
                Button(picked.count == seasons.count ? "Clear" : "Select all") {
                    picked = picked.count == seasons.count ? [] : Set(seasons.map(\.number))
                }
                .font(.callout)
            }
            PageScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: chipWidth), spacing: 12)], spacing: 12) {
                    ForEach(seasons) { s in
                        let on = picked.contains(s.number)
                        Button {
                            if on { picked.remove(s.number) } else { picked.insert(s.number) }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(on ? Color.accentColor : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.name ?? "Season \(s.number)").font(.callout.weight(.semibold)).lineLimit(1)
                                    if let n = s.episode_count {
                                        Text("\(n) episodes\(s.year.map { " · \($0)" } ?? "")").font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(on ? Color.accentColor.opacity(0.25) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .rowButton(corner: 14)
                    }
                }
                .padding(4)
            }
            .frame(maxHeight: 260)
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Button("Cancel", role: .cancel) { done(false) }
                .buttonStyle(.bordered)
            Spacer()
            Button {
                Task { await send() }
            } label: {
                HStack(spacing: 10) {
                    if busy { ProgressView() }
                    Label(askLabel, systemImage: "plus.circle.fill")
                }
                .padding(.horizontal, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(busy || (kind == "show" && scope == .pick && picked.isEmpty))
        }
    }

    private var askLabel: String {
        guard kind == "show" else { return "Ask" }
        switch scope {
        case .whole: return "Ask for all seasons"
        case .future: return "Ask for new episodes"
        case .pick: return picked.isEmpty ? "Pick seasons" : "Ask for \(picked.count) season\(picked.count == 1 ? "" : "s")"
        }
    }

    // MARK: Sizes

    private var spacing: CGFloat {
        #if os(tvOS)
        32
        #else
        22
        #endif
    }
    private var outerPadding: CGFloat {
        #if os(tvOS)
        60
        #else
        32
        #endif
    }
    private var posterW: CGFloat {
        #if os(tvOS)
        110
        #else
        72
        #endif
    }
    private var cardHeight: CGFloat {
        #if os(tvOS)
        150
        #else
        96
        #endif
    }
    private var chipWidth: CGFloat {
        #if os(tvOS)
        280
        #else
        200
        #endif
    }

    private func send() async {
        guard let c = app.client else { return }
        busy = true
        defer { busy = false }
        var body = AskBody(id: "tmdb:\(tmdb)", kind: kind)
        if kind == "show" {
            switch scope {
            case .whole: break
            case .pick: body.seasons = picked.sorted()
            case .future: body.future_only = true
            }
        }
        do {
            let _: AskAnswer = try await c.post("/asks", body: body)
            done(true)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
