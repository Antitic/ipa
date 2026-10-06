import Foundation

/// Données fictives pour le mode démo (-forceDemo YES) et les captures d'écran.
enum DemoData {
    static let user = "neo@dipherant.xyz"

    static let boxes: [Mailbox] = [
        Mailbox(path: "INBOX", label: "Réception", total: 128, unseen: 3, uidNext: 220),
        Mailbox(path: "Sent", label: "Envoyés", total: 41, unseen: 0, uidNext: 60),
        Mailbox(path: "Archive", label: "Archive", total: 512, unseen: 0, uidNext: 600),
        Mailbox(path: "Trash", label: "Corbeille", total: 7, unseen: 0, uidNext: 20),
    ]

    private static func ago(_ minutes: Double) -> Date { Date().addingTimeInterval(-minutes * 60) }

    static let rows: [String: [MailRow]] = [
        "INBOX": [
            MailRow(uid: 219, box: "INBOX", subject: "Ta commande de fil à broder est expédiée", name: "Mercerie Saint-Maur", address: "contact@mercerie.example", date: ago(12), seen: false, att: false),
            MailRow(uid: 218, box: "INBOX", subject: "Rapport de stage : retours de la mairie", name: "Service communication", address: "com@mairie.example", date: ago(95), seen: false, att: true),
            MailRow(uid: 217, box: "INBOX", subject: "Ton serveur a redémarré à 04:12", name: "Mohamlab", address: "mlab@dipherant.xyz", date: ago(380), seen: false, att: false),
            MailRow(uid: 216, box: "INBOX", subject: "Facture Ikoula — octobre", name: "Ikoula", address: "factures@ikoula.example", date: ago(60 * 26), seen: true, att: true),
            MailRow(uid: 215, box: "INBOX", subject: "On joue ce soir ?", name: "Léa", address: "lea@example.org", date: ago(60 * 50), seen: true, att: false),
            MailRow(uid: 214, box: "INBOX", subject: "Nouveau commentaire sur Dipherant", name: "contact.dipherant.xyz", address: "noreply@dipherant.xyz", date: ago(60 * 80), seen: true, att: false),
            MailRow(uid: 213, box: "INBOX", subject: "Ton t-shirt pixel rose a été vendu", name: "Vinted", address: "no-reply@vinted.example", date: ago(60 * 24 * 9), seen: true, att: false),
            MailRow(uid: 212, box: "INBOX", subject: "Renouvellement du domaine dipherant.xyz", name: "Registrar", address: "renew@registrar.example", date: ago(60 * 24 * 40), seen: true, att: false),
        ],
        "Sent": [
            MailRow(uid: 59, box: "Sent", subject: "Re: Rapport de stage", name: "com@mairie.example", address: "com@mairie.example", date: ago(60 * 30), seen: true, att: true),
            MailRow(uid: 58, box: "Sent", subject: "Commande de fil", name: "contact@mercerie.example", address: "contact@mercerie.example", date: ago(60 * 24 * 3), seen: true, att: false),
        ],
        "Archive": [
            MailRow(uid: 599, box: "Archive", subject: "Bienvenue sur ton nouveau serveur mail", name: "Postmaster", address: "postmaster@dipherant.xyz", date: ago(60 * 24 * 85), seen: true, att: false),
        ],
        "Trash": [
            MailRow(uid: 19, box: "Trash", subject: "Offre exceptionnelle !!!", name: "Promo", address: "promo@spam.example", date: ago(60 * 24 * 2), seen: true, att: false),
        ],
    ]

    static func message(for row: MailRow) -> MailMessage {
        MailMessage(
            box: row.box, uid: row.uid, subject: row.subject,
            fromName: row.name, fromAddress: row.address, from: "\(row.name) <\(row.address)>",
            to: user, cc: "", toAddresses: [user], ccAddresses: [], replyTo: "",
            date: row.date, text: plain(for: row), messageId: "<demo-\(row.uid)@dipherant.xyz>",
            references: "", remoteImages: row.uid == 219,
            attachments: row.att
                ? [Attachment(index: 0, name: "retours-rapport.pdf", size: 248_000, contentType: "application/pdf"),
                   Attachment(index: 1, name: "photo-accueil.jpg", size: 1_420_000, contentType: "image/jpeg")]
                : []
        )
    }

    static func plain(for row: MailRow) -> String {
        switch row.uid {
        case 218:
            return """
            Bonjour,

            Merci pour l'envoi de ton rapport de stage. Dans l'ensemble c'est très clair, \
            on a juste annoté deux ou trois passages (voir le PDF joint).

            La partie sur l'accueil du public est vraiment réussie.

            Bonne continuation,
            Le service communication
            """
        case 219:
            return """
            Bonjour Tikawski,

            Ton colis (3 bobines de fil rose fluo, 2 noires) a quitté l'entrepôt ce matin. \
            Livraison prévue jeudi.

            À bientôt !
            """
        default:
            return """
            Bonjour,

            Ceci est un message de démonstration affiché par Meyl.

            Bonne journée.
            """
        }
    }

    static func html(for row: MailRow) -> String {
        let paras = plain(for: row)
            .components(separatedBy: "\n\n")
            .map { "<p>" + $0.replacingOccurrences(of: "\n", with: "<br>") + "</p>" }
            .joined()
        return "<!DOCTYPE html><html><head><meta charset=\"utf-8\"></head><body>\(paras)</body></html>"
    }
}
