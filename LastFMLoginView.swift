import SwiftUI
import WebKit

struct LastFMLoginView: UIViewRepresentable {
    let url: URL
    let onTokenReceived: (String) -> Void
    @Binding var isPresented: Bool
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        let request = URLRequest(url: url)
        uiView.load(request)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: LastFMLoginView
        
        init(_ parent: LastFMLoginView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url,
               url.scheme == "lastfmscrobbler",
               url.host == "auth",
               let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let token = components.queryItems?.first(where: { $0.name == "token" })?.value {
                
                parent.onTokenReceived(token)
                parent.isPresented = false
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
