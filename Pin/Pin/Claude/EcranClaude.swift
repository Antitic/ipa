import SwiftUI
import WebKit

/// claude.ai dans l'écran de l'iPod, avec tes discussions. La session est
/// gardée par le magasin de données par défaut de WebKit : on se connecte une
/// fois (lien ou code par email ; Google refuse les WebView).
@MainActor
final class NavigateurClaude: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let web: WKWebView
    @Published var chargement = true

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        web = WKWebView(frame: .zero, configuration: config)
        super.init()
        web.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Mobile/15E148 Safari/604.1"
        web.allowsBackForwardNavigationGestures = true
        web.navigationDelegate = self
        web.uiDelegate = self
        web.load(URLRequest(url: URL(string: "https://claude.ai/new")!))
    }

    /// Fait défiler la zone de conversation (le plus grand bloc qui défile).
    func defiler(_ sens: Int) {
        let js = """
        (function(d){
          var t = window.__pinDefile;
          if (!t || !document.contains(t) || t.scrollHeight <= t.clientHeight + 10) {
            var best = null, aire = 0;
            document.querySelectorAll('main *, body > div *').forEach(function(e){
              if (e.scrollHeight > e.clientHeight + 40) {
                var o = getComputedStyle(e).overflowY;
                if (o === 'auto' || o === 'scroll') {
                  var a = e.clientWidth * e.clientHeight;
                  if (a > aire) { aire = a; best = e; }
                }
              }
            });
            t = best || document.scrollingElement;
            window.__pinDefile = t;
          }
          t.scrollBy({ top: d, behavior: 'smooth' });
        })(\(sens * 90));
        """
        web.evaluateJavaScript(js, completionHandler: nil)
    }

    func retour() -> Bool {
        guard web.canGoBack else { return false }
        web.goBack()
        return true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { chargement = false }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { chargement = true }

    /// Liens hors de claude.ai et de sa connexion : Safari.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = action.request.url, let hote = url.host else { return .allow }
        let internes = ["claude.ai", "anthropic.com", "claudeusercontent.com", "cloudflare.com", "stripe.com", "google.com", "apple.com"]
        if action.navigationType == .linkActivated, !internes.contains(where: { hote == $0 || hote.hasSuffix("." + $0) }) {
            await UIApplication.shared.open(url)
            return .cancel
        }
        return .allow
    }

    /// Les liens « nouvelle fenêtre » s'ouvrent dans la même vue.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if action.targetFrame == nil { webView.load(action.request) }
        return nil
    }
}

/// Une seule instance pour toute l'app : la conversation reste où on l'a laissée.
@MainActor
enum PartageClaude {
    static let navigateur = NavigateurClaude()
}

struct VueWeb: UIViewRepresentable {
    let web: WKWebView
    func makeUIView(context: Context) -> WKWebView { web }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct EcranClaude: View {
    @EnvironmentObject var nav: Navigateur
    @ObservedObject private var claude = PartageClaude.navigateur

    var body: some View {
        ZStack(alignment: .top) {
            VueWeb(web: claude.web)
            if claude.chargement {
                ProgressView().progressViewStyle(.linear).tint(Color(red: 0.85, green: 0.47, blue: 0.34))
            }
        }
        .roue { g in
            g.tour = { s in claude.defiler(s) }
            g.menu = { claude.retour() }
            g.centre = { claude.web.becomeFirstResponder() }
            g.precedent = { _ = claude.retour() }
            g.suivant = { if claude.web.canGoForward { claude.web.goForward() } }
        }
    }
}
