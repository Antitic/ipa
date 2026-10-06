import SwiftUI
import UIKit
import WebKit

/// Affiche le corps HTML (déjà nettoyé par le serveur), sans JavaScript, avec une
/// politique de contenu stricte : rien ne se charge à distance sauf si on autorise
/// les images. Les liens s'ouvrent dans Safari.
struct MailWebView: UIViewRepresentable {
    let html: String
    let allowRemote: Bool
    var codex = false

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.websiteDataStore = .nonPersistent()
        config.dataDetectorTypes = [.link, .phoneNumber]
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.allowsLinkPreview = true
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        let doc = Self.prepare(html, allowRemote: allowRemote, codex: codex)
        guard context.coordinator.loaded != doc else { return }
        context.coordinator.loaded = doc
        web.loadHTMLString(doc, baseURL: nil)
    }

    /// Garamond embarquée en data: (le moteur web ne voit pas les polices de l'app).
    static let garamondFace: String = {
        func face(_ file: String, style: String, weight: Int) -> String {
            guard let url = Bundle.main.url(forResource: file, withExtension: "ttf"),
                  let data = try? Data(contentsOf: url) else { return "" }
            return "@font-face{font-family:'MeylGaramond';font-style:\(style);font-weight:\(weight);src:url(data:font/ttf;base64,\(data.base64EncodedString())) format('truetype');}"
        }
        return face("EBGaramond-Regular", style: "normal", weight: 400)
            + face("EBGaramond-Italic", style: "italic", weight: 400)
            + face("EBGaramond-SemiBold", style: "normal", weight: 700)
    }()

    static func prepare(_ html: String, allowRemote: Bool, codex: Bool = false) -> String {
        let csp = "default-src 'none'; img-src data: \(allowRemote ? "https: http:" : ""); style-src 'unsafe-inline'; font-src data:; form-action 'none'"
        let head = """
        <meta http-equiv="Content-Security-Policy" content="\(csp)">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        """
        var tail = "<style>html,body{background:transparent !important;} body{padding:4px 2px 24px !important; -webkit-text-size-adjust:100%;}</style>"
        if codex {
            tail += "<style>\(garamondFace) html,body{font-family:'MeylGaramond',Georgia,serif;font-size:19px;line-height:1.5;color:#091717;} body{padding:18px 22px 40px !important;} pre.plain{font-family:'MeylGaramond',Georgia,serif;font-size:19px;} a{color:#20808D;} blockquote{border-left:2px solid #E4E2D9;color:#556161;} pre.plain .q{color:#8F9A99;}</style>"
        }
        var s = html
        if let r = s.range(of: "<head>", options: .caseInsensitive) {
            s.insert(contentsOf: head, at: r.upperBound)
        } else {
            s = "<!DOCTYPE html><html><head><meta charset=\"utf-8\">" + head + "</head><body>" + s + "</body></html>"
        }
        // Nos styles en fin d'en-tête : ils passent après ceux du serveur.
        if let r = s.range(of: "</head>", options: .caseInsensitive) {
            s.insert(contentsOf: tail, at: r.lowerBound)
        }
        return s
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loaded: String?

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated || action.targetFrame == nil, let url = action.request.url,
               ["http", "https", "mailto", "tel"].contains(url.scheme?.lowercased() ?? "") {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            let scheme = action.request.url?.scheme?.lowercased() ?? ""
            decisionHandler(scheme == "about" || scheme == "data" || scheme.isEmpty ? .allow : .cancel)
        }
    }
}
