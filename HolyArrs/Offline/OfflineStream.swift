import Foundation

/// PlaybackInfo for a download: never direct play (AVAssetDownloadTask only takes HLS), the bitrate capped by the
/// chosen quality, and the video copied when it fits under the cap.
nonisolated struct OfflinePlaybackInfoBody: Encodable {
    var UserId: String
    var MaxStreamingBitrate: Int
    var AutoOpenLiveStream = false
    var EnableDirectPlay = false
    var EnableDirectStream = false
    var EnableTranscoding = true
    var AllowVideoStreamCopy = true
    var AllowAudioStreamCopy = true
    var DeviceProfile: DeviceProfile
}

enum OfflineStream {
    struct Stream {
        /// The HLS master playlist. It carries the Jellyfin token, so it is never stored or logged.
        var url: URL
        var mediaSourceID: String
        var playSessionID: String
    }

    /// Asks Jellyfin for an fMP4 HLS stream of the item at the given quality.
    static func request(itemID: String, quality: OfflineQuality, client: JellyfinClient) async throws -> Stream {
        var profile = DeviceProfile.avPlayer
        profile.MaxStreamingBitrate = quality.maxBitrate
        profile.MaxStaticBitrate = quality.maxBitrate
        let body = OfflinePlaybackInfoBody(UserId: client.login.userID, MaxStreamingBitrate: quality.maxBitrate, DeviceProfile: profile)
        let data = try await client.request("POST", "/Items/\(itemID)/PlaybackInfo?UserId=\(client.login.userID)", body: try JSONEncoder().encode(body))
        let info = try JSONDecoder().decode(JFPlaybackInfo.self, from: data)
        guard let src = info.MediaSources?.first, let path = src.TranscodingUrl,
              var c = URLComponents(string: client.base.absoluteString + path) else {
            throw APIError.transport("Jellyfin could not offer a stream to download for this item.")
        }
        guard c.path.lowercased().hasSuffix(".m3u8") else {
            throw APIError.transport("Jellyfin offered a \(src.Container ?? "file") stream, not HLS, so it cannot be downloaded here.")
        }
        var q = c.percentEncodedQueryItems ?? []
        func set(_ name: String, _ value: String) {
            q.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            q.append(URLQueryItem(name: name, value: value))
        }
        if let size = quality.maxSize {
            set("MaxWidth", String(size.width))
            set("MaxHeight", String(size.height))
        }
        if !q.contains(where: { ["api_key", "apikey"].contains($0.name.lowercased()) }) {
            set("api_key", client.login.accessToken.q)
        }
        c.percentEncodedQueryItems = q
        guard let url = c.url else { throw APIError.badURL }
        return Stream(url: url, mediaSourceID: src.Id ?? itemID, playSessionID: info.PlaySessionId ?? "")
    }

    /// Ends the server's transcode for a download session (the same call the player makes when it closes).
    static func stop(_ client: JellyfinClient, playSessionID: String) async {
        guard !playSessionID.isEmpty else { return }
        _ = try? await client.request("DELETE", "/Videos/ActiveEncodings?DeviceId=\(JellyfinAuth.deviceID)&PlaySessionId=\(playSessionID)")
    }
}
