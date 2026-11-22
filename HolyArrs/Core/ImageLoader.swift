import SwiftUI
import UIKit

/// A tiny in-memory image cache. HolyArrs' own artwork (`/api/v1/artwork/...`) needs the auth header, so AsyncImage is not enough.
final class ImageLoader {
    static let shared = ImageLoader()

    private let cache = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]
    private let session: URLSession

    private init() {
        cache.countLimit = 400
        let config = URLSessionConfiguration.default
        config.httpShouldSetCookies = false
        config.urlCache = URLCache(memoryCapacity: 32 << 20, diskCapacity: 256 << 20)
        session = URLSession(configuration: config)
    }

    func cached(_ url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }

    func load(_ url: URL, headers: [String: String]) async -> UIImage? {
        if let img = cache.object(forKey: url as NSURL) { return img }
        if let t = inFlight[url] { return await t.value }
        let session = session
        let t = Task<UIImage?, Never> {
            var req = URLRequest(url: url)
            for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
            guard let (data, resp) = try? await session.data(for: req),
                  let http = resp as? HTTPURLResponse, http.statusCode == 200
            else { return nil }
            return await Self.decode(data)
        }
        inFlight[url] = t
        let img = await t.value
        inFlight[url] = nil
        if let img { cache.setObject(img, forKey: url as NSURL) }
        return img
    }

    nonisolated private static func decode(_ data: Data) async -> UIImage? {
        await Task.detached(priority: .utility) {
            UIImage(data: data)?.preparingForDisplay()
        }.value
    }
}

/// Shows a remote picture from the API, with a quiet placeholder.
struct RemoteImage: View {
    @Environment(AppModel.self) private var app
    let path: String?
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?

    var body: some View {
        // Color.clear takes exactly the offered size; the picture fills it and is clipped, so a fill
        // image never makes its container (and the text laid over it) larger than the frame.
        Color.clear
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .transition(.opacity)
                } else if contentMode == .fill {
                    Rectangle().fill(.quaternary)
                }
            }
            .clipped()
        .task(id: path) {
            guard let client = app.client, let url = client.imageURL(path) else { image = nil; return }
            if let hit = ImageLoader.shared.cached(url) { image = hit; return }
            let img = await ImageLoader.shared.load(url, headers: client.authHeaders(for: url))
            withAnimation(.easeOut(duration: 0.2)) { image = img }
        }
    }
}
