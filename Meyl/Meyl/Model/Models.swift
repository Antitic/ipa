import Foundation

// MARK: - Réponses de l'API /app/v1

struct Mailbox: Codable, Identifiable, Hashable {
    let path: String
    let label: String
    var total: Int?
    var unseen: Int?
    var uidNext: Int?

    var id: String { path }

    var symbol: String {
        switch path {
        case "INBOX": return "tray.and.arrow.down.fill"
        case "Sent": return "paperplane.fill"
        case "Archive": return "archivebox.fill"
        case "Trash": return "trash.fill"
        default: return "folder.fill"
        }
    }

    static let defaults: [Mailbox] = [
        Mailbox(path: "INBOX", label: "Réception"),
        Mailbox(path: "Sent", label: "Envoyés"),
        Mailbox(path: "Archive", label: "Archive"),
        Mailbox(path: "Trash", label: "Corbeille"),
    ]

    static func label(for path: String) -> String {
        defaults.first { $0.path == path }?.label ?? path
    }
}

struct MeResponse: Codable {
    let user: String
    let boxes: [Mailbox]
}

struct BoxCount: Codable {
    let total: Int
    let unseen: Int
    let uidNext: Int
}

struct MailRow: Codable, Identifiable, Hashable {
    let uid: Int
    let box: String
    let subject: String
    let name: String
    let address: String
    let date: Date?
    var seen: Bool
    let att: Bool

    var id: String { box + "/" + String(uid) }
}

struct ListResponse: Codable {
    let box: String
    let rows: [MailRow]
    let more: Bool
}

struct PollResponse: Codable {
    let counts: [String: BoxCount]
    let rows: [MailRow]
}

struct SearchResponse: Codable {
    let rows: [MailRow]
}

struct Attachment: Codable, Identifiable, Hashable {
    let index: Int
    let name: String
    let size: Int
    let contentType: String

    var id: Int { index }

    var symbol: String {
        let t = contentType.lowercased()
        if t.hasPrefix("image/") { return "photo" }
        if t.contains("pdf") { return "doc.richtext" }
        if t.hasPrefix("audio/") { return "waveform" }
        if t.hasPrefix("video/") { return "film" }
        if t.contains("zip") || t.contains("compressed") { return "archivebox" }
        return "doc"
    }

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

struct MailMessage: Codable, Hashable {
    let box: String
    let uid: Int
    let subject: String
    let fromName: String
    let fromAddress: String
    let from: String
    let to: String
    let cc: String
    let toAddresses: [String]
    let ccAddresses: [String]
    let replyTo: String
    let date: Date?
    let text: String
    let messageId: String
    let references: String
    let remoteImages: Bool
    let attachments: [Attachment]
}

struct MoveResponse: Codable {
    let ok: Bool
    let uid: Int?
    let box: String
}

struct OKResponse: Codable {
    let ok: Bool
}

struct SendResponse: Codable {
    let ok: Bool
    let delivered: Bool
}

struct ErrorResponse: Codable {
    let error: String
}

// MARK: - Brouillon

struct Draft: Identifiable, Hashable {
    let id = UUID()
    var to: String = ""
    var cc: String = ""
    var subject: String = ""
    var body: String = ""
    var inReplyTo: String = ""
    var references: String = ""
    var files: [DraftFile] = []

    static func reply(to m: MailMessage, all: Bool, me: String) -> Draft {
        var d = Draft()
        let target = m.replyTo.isEmpty ? m.fromAddress : m.replyTo
        d.to = target
        if all {
            let others = (m.toAddresses + m.ccAddresses)
                .filter { $0.lowercased() != me.lowercased() && $0.lowercased() != target.lowercased() }
            d.cc = Array(NSOrderedSet(array: others)).compactMap { $0 as? String }.joined(separator: ", ")
        }
        d.subject = m.subject.lowercased().hasPrefix("re:") ? m.subject : "Re: " + m.subject
        d.inReplyTo = m.messageId
        d.references = m.references
        d.body = "\n\n" + quoteHeader(m) + "\n" + quoted(m.text)
        return d
    }

    static func forward(_ m: MailMessage) -> Draft {
        var d = Draft()
        d.subject = m.subject.lowercased().hasPrefix("fwd:") ? m.subject : "Fwd: " + m.subject
        var head = "\n\n---------- Message transféré ----------\n"
        head += "De : \(m.from)\n"
        if let date = m.date { head += "Date : \(Fmt.long(date))\n" }
        head += "Objet : \(m.subject)\n"
        head += "À : \(m.to)\n\n"
        d.body = head + m.text
        return d
    }

    private static func quoteHeader(_ m: MailMessage) -> String {
        let who = m.fromName.isEmpty ? m.fromAddress : m.fromName
        if let date = m.date { return "Le \(Fmt.long(date)), \(who) a écrit :" }
        return "\(who) a écrit :"
    }

    private static func quoted(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { "> " + $0 }
            .joined(separator: "\n")
    }
}

struct DraftFile: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let mime: String
    let data: Data
}

// MARK: - Dates

enum Fmt {
    static let paris = TimeZone(identifier: "Europe/Paris") ?? .current
    static let fr = Locale(identifier: "fr_FR")

    private static func f(_ format: String) -> DateFormatter {
        let d = DateFormatter()
        d.locale = fr
        d.timeZone = paris
        d.setLocalizedDateFormatFromTemplate(format)
        return d
    }

    private static let time = f("HH:mm")
    private static let weekday = f("EEE")
    private static let dayMonth = f("d MMM")
    private static let full = f("dd/MM/yy")
    private static let longF: DateFormatter = {
        let d = DateFormatter()
        d.locale = fr
        d.timeZone = paris
        d.dateStyle = .full
        d.timeStyle = .short
        return d
    }()

    static func list(_ date: Date?) -> String {
        guard let date else { return "" }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = paris
        let now = Date()
        if cal.isDate(date, inSameDayAs: now) { return time.string(from: date) }
        let days = now.timeIntervalSince(date) / 86400
        if days < 6 && days >= 0 { return weekday.string(from: date).replacingOccurrences(of: ".", with: "") }
        if cal.component(.year, from: date) == cal.component(.year, from: now) {
            return dayMonth.string(from: date).replacingOccurrences(of: ".", with: "")
        }
        return full.string(from: date)
    }

    static func long(_ date: Date) -> String { longF.string(from: date) }
}
