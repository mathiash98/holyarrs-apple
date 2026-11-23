import SwiftUI

/// Choose seasons of a show and ask for them (asking for the whole show is one click on the title page).
/// Sends POST /asks.
struct AskSheet: View {
    @Environment(AppModel.self) private var app
    let kind: String
    let tmdb: String
    let name: String
    var year: Int? = nil
    var poster: String? = nil
    let seasons: [TitleMeta.Season]
    let done: (Bool) -> Void

    @State private var picked: Set<Int> = []
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            header
            seasonGrid
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.xCallout).foregroundStyle(.yellow)
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(outerPadding)
        #if os(visionOS)
        .frame(width: 760, height: 560)
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
                Text("Choose seasons").font(.xCallout).foregroundStyle(.secondary)
                Text(name).font(.xTitle.bold()).lineLimit(2)
                Text([year.map(String.init), kind == "show" ? "TV show" : "Movie"].compactMap { $0 }.joined(separator: " · "))
                    .font(.xCallout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var seasonGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Seasons").font(.xHeadline)
                Spacer()
                Button(picked.count == seasons.count ? "Clear" : "Select all") {
                    picked = picked.count == seasons.count ? [] : Set(seasons.map(\.number))
                }
                .font(.xCallout)
                .secondaryAction()
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
                                    Text(s.name ?? "Season \(s.number)").font(.xCallout.weight(.semibold)).lineLimit(1)
                                    if let n = s.episode_count {
                                        Text("\(n) episodes\(s.year.map { " · \($0)" } ?? "")").font(.xCaption2).foregroundStyle(.secondary)
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
            .frame(maxHeight: 380)
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Button("Cancel", role: .cancel) { done(false) }
                .secondaryAction()
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
            .primaryAction()
            .disabled(busy || picked.isEmpty)
        }
    }

    private var askLabel: String {
        picked.isEmpty ? "Pick seasons" : "Ask for \(picked.count) season\(picked.count == 1 ? "" : "s")"
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
        body.seasons = picked.sorted()
        do {
            let _: AskAnswer = try await c.post("/asks", body: body)
            done(true)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
