import SwiftUI
import WebKit

// MARK: - Reproductor de YouTube (IFrame Player API oficial)
// Web: loadYouTubeAPI() + ensureYouTubePlayer() (index.html:4385, 4401):
// carga https://www.youtube.com/iframe_api y crea un YT.Player con
// eventos onStateChange (play/pause/ended -> siguiente).
// Aquí lo mismo dentro de un WKWebView. El audio de YouTube NO se extrae:
// suena con el reproductor oficial, como en la web.
struct YouTubePlayerView: UIViewRepresentable {
    var videoId: String
    var autoplay: Bool = true
    var onStateChange: ((YouTubePlayerState) -> Void)?

    enum YouTubePlayerState: String {
        case unstarted, ended, playing, paused, buffering, cued
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onStateChange: onStateChange)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "ytEvent")
        config.userContentController = contentController
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.backgroundColor = .black
        webView.isOpaque = true
        context.coordinator.currentVideoId = videoId
        load(videoId: videoId, into: webView)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Si cambia el video, cargar el nuevo.
        if context.coordinator.currentVideoId != videoId {
            context.coordinator.currentVideoId = videoId
            load(videoId: videoId, into: uiView)
        }
    }

    private func load(videoId: String, into webView: WKWebView) {
        let html = """
        <!DOCTYPE html><html><head><meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>html,body{margin:0;padding:0;background:#000;height:100%;overflow:hidden}iframe{width:100%;height:100%;border:0}</style></head>
        <body><div id="player"></div>
        <script src="https://www.youtube.com/iframe_api"></script>
        <script>
        var player;
        function onYouTubeIframeAPIReady(){
          player = new YT.Player('player', {
            videoId: '\(videoId)',
            playerVars: { autoplay: \(autoplay ? 1 : 0), playsinline: 1, rel: 0 },
            events: {
              onStateChange: function(e){
                window.webkit.messageHandlers.ytEvent.postMessage({ state: e.data });
              },
              onError: function(e){
                window.webkit.messageHandlers.ytEvent.postMessage({ state: -1, error: e.data });
              }
            }
          });
        }
        </script></body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var currentVideoId: String?
        var onStateChange: ((YouTubePlayerState) -> Void)?

        init(onStateChange: ((YouTubePlayerState) -> Void)?) {
            self.onStateChange = onStateChange
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let raw = body["state"] as? Int else { return }
            let state: YouTubePlayerState
            switch raw {
            case 0: state = .ended
            case 1: state = .playing
            case 2: state = .paused
            case 3: state = .buffering
            case 5: state = .cued
            default: state = .unstarted
            }
            onStateChange?(state)
        }
    }
}
