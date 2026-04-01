import AppKit
import SwiftUI
import WebKit

struct RemoteGroupDetailView: View {
  let endpoint: RemoteEndpoint

  var body: some View {
    RemoteGroupWebView(url: endpoint.baseURL)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color(nsColor: .windowBackgroundColor))
  }
}

private struct RemoteGroupWebView: NSViewRepresentable {
  let url: URL

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeNSView(context: Context) -> WKWebView {
    let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    webView.uiDelegate = context.coordinator
    webView.allowsBackForwardNavigationGestures = true
    webView.load(URLRequest(url: url))
    return webView
  }

  func updateNSView(_ nsView: WKWebView, context: Context) {
    if nsView.url?.absoluteString != url.absoluteString {
      nsView.load(URLRequest(url: url))
    }
  }

  @MainActor
  final class Coordinator: NSObject, WKUIDelegate {
    func webView(
      _ webView: WKWebView,
      runJavaScriptAlertPanelWithMessage message: String,
      initiatedByFrame frame: WKFrameInfo,
      completionHandler: @escaping @MainActor () -> Void
    ) {
      _ = runAlert(
        message: message,
        style: .informational,
        defaultButtonTitle: "OK",
        alternateButtonTitle: nil
      )
      completionHandler()
    }

    func webView(
      _ webView: WKWebView,
      runJavaScriptConfirmPanelWithMessage message: String,
      initiatedByFrame frame: WKFrameInfo,
      completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
      let response = runAlert(
        message: message,
        style: .warning,
        defaultButtonTitle: "Confirm",
        alternateButtonTitle: "Cancel"
      )
      completionHandler(response == .alertFirstButtonReturn)
    }

    func webView(
      _ webView: WKWebView,
      runJavaScriptTextInputPanelWithPrompt prompt: String,
      defaultText: String?,
      initiatedByFrame frame: WKFrameInfo,
      completionHandler: @escaping @MainActor @Sendable (String?) -> Void
    ) {
      let alert = NSAlert()
      alert.messageText = prompt
      alert.alertStyle = .informational
      alert.addButton(withTitle: "OK")
      alert.addButton(withTitle: "Cancel")

      let textField = NSTextField(string: defaultText ?? "")
      textField.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
      alert.accessoryView = textField

      let response = alert.runModal()
      completionHandler(response == .alertFirstButtonReturn ? textField.stringValue : nil)
    }

    func webView(
      _ webView: WKWebView,
      createWebViewWith configuration: WKWebViewConfiguration,
      for navigationAction: WKNavigationAction,
      windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
      guard navigationAction.targetFrame == nil else {
        return nil
      }
      webView.load(navigationAction.request)
      return nil
    }

    private func runAlert(
      message: String,
      style: NSAlert.Style,
      defaultButtonTitle: String,
      alternateButtonTitle: String?
    ) -> NSApplication.ModalResponse {
      let alert = NSAlert()
      alert.messageText = message
      alert.alertStyle = style
      alert.addButton(withTitle: defaultButtonTitle)
      if let alternateButtonTitle {
        alert.addButton(withTitle: alternateButtonTitle)
      }
      return alert.runModal()
    }
  }
}
