import Foundation

/// An id the API sends as a string in one place and a number in another (TMDB ids, person ids).
nonisolated struct FlexID: Codable, Hashable, CustomStringConvertible {
    let value: String
    init(_ v: String) { value = v }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { value = s }
        else if let i = try? c.decode(Int64.self) { value = String(i) }
        else if let d = try? c.decode(Double.self) { value = String(Int64(d)) }
        else { value = "" }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(value)
    }
    var description: String { value }
}

/// A list of names that may arrive as strings or as `{ "name": ... }` objects.
nonisolated struct NameList: Codable, Hashable {
    let names: [String]
    init(from decoder: Decoder) throws {
        var out: [String] = []
        if var c = try? decoder.unkeyedContainer() {
            while !c.isAtEnd {
                if let s = try? c.decode(String.self) { out.append(s) }
                else if let o = try? c.decode(Named.self), let n = o.name { out.append(n) }
                else { _ = try? c.decode(Skip.self) }
            }
        }
        names = out
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(contentsOf: names)
    }
    private struct Named: Decodable { let name: String? }
}

/// Consumes any JSON value.
nonisolated struct Skip: Decodable {}

nonisolated struct IDs: Codable, Hashable {
    var tmdb: FlexID?
    var imdb: String?
    var tvdb: FlexID?
    var tvmaze: FlexID?
}

/// Parses the API's timestamps (RFC 3339 with up to nanosecond fractions, `Z` or an offset) and plain dates.
nonisolated enum HADate {
    nonisolated(unsafe) private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    nonisolated(unsafe) private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let day: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func parse(_ s: String?) -> Date? {
        guard var s, !s.isEmpty else { return nil }
        if s.count == 10 { return day.date(from: s) }
        // ISO8601DateFormatter handles at most 3 fractional digits: trim the rest.
        if let dot = s.firstIndex(of: ".") {
            var end = s.index(after: dot)
            while end < s.endIndex, s[end].isNumber { end = s.index(after: end) }
            let digits = s[s.index(after: dot) ..< end]
            if digits.count > 3 {
                s = String(s[..<s.index(after: dot)]) + digits.prefix(3) + s[end...]
            }
            return isoFrac.date(from: s) ?? iso.date(from: s)
        }
        return iso.date(from: s)
    }

    static func ymd(_ d: Date) -> String { day.string(from: d) }
}

extension Date {
    var relative: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: self, relativeTo: .now)
    }
}

enum Fmt {
    static func bytes(_ n: Int64?) -> String {
        guard let n, n > 0 else { return "" }
        return ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
    static func speed(_ n: Int64?) -> String {
        guard let n, n > 0 else { return "" }
        return ByteCountFormatter.string(fromByteCount: n, countStyle: .file) + "/s"
    }
    static func runtime(_ m: Int?) -> String? {
        guard let m, m > 0 else { return nil }
        return m >= 60 ? "\(m / 60)h \(m % 60 > 0 ? "\(m % 60)m" : "")".trimmingCharacters(in: .whitespaces) : "\(m)m"
    }
    /// 1:02:03 or 12:34.
    static func clock(_ seconds: Double) -> String {
        let t = Int(seconds)
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t % 3600 / 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
    }
    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "" }
        let f = DateComponentsFormatter()
        f.allowedUnits = seconds > 3600 ? [.hour, .minute] : [.minute, .second]
        f.unitsStyle = .abbreviated
        f.maximumUnitCount = 2
        return f.string(from: seconds) ?? ""
    }
}
