import Foundation

enum Fmt {
    static let fr = Locale(identifier: "fr_FR")

    static func duration(_ s: Int?) -> String? {
        guard let s, s > 0 else { return nil }
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    static func count(_ n: Int?) -> String? {
        guard let n, n >= 0 else { return nil }
        return n.formatted(.number.notation(.compactName).locale(fr))
    }

    static func relative(ms: Int64?) -> String? {
        guard let ms, ms > 0 else { return nil }
        let date = Date(timeIntervalSince1970: Double(ms) / 1000)
        let f = RelativeDateTimeFormatter()
        f.locale = fr
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: Date())
    }

    static func stripHTML(_ s: String) -> String {
        var t = s
        for br in ["<br>", "<br/>", "<br />"] { t = t.replacingOccurrences(of: br, with: "\n") }
        t = t.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " "]
        for (k, v) in entities { t = t.replacingOccurrences(of: k, with: v) }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
