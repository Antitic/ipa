import SwiftUI
import UIKit
import WebKit

/// Affiche le corps HTML (déjà nettoyé par le serveur), sans JavaScript, avec une
/// politique de contenu stricte : rien ne se charge à distance sauf si on autorise
/// les images. Les liens s'ouvrent dans Safari.
struct MailWebView: UIViewRepresentable {
    let html: String
    let allowRemote: Bool

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
        let doc = Self.prepare(html, allowRemote: allowRemote)
        guard context.coordinator.loaded != doc else { return }
        context.coordinator.loaded = doc
        web.loadHTMLString(doc, baseURL: nil)
    }

    static func prepare(_ html: String, allowRemote: Bool) -> String {
        let csp = "default-src 'none'; img-src data: \(allowRemote ? "https: http:" : ""); style-src 'unsafe-inline'; font-src data:; form-action 'none'"
        let head = """
        <meta http-equiv="Content-Security-Policy" content="\(csp)">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>html,body{background:transparent !important;} body{padding:4px 2px 24px !important; -webkit-text-size-adjust:100%;}</style>
        """
        if let r = html.range(of: "<head>", options: .caseInsensitive) {
            var s = html
            s.insert(contentsOf: head, at: r.upperBound)
            return s
        }
        return "<!DOCTYPE html><html><head><meta charset=\"utf-8\">" + head + "</head><body>" + html + "</body></html>"
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
