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
    webView.navigationDelegate = context.coordinator
    webView.allowsBackForwardNavigationGestures = true
    webView.load(URLRequest(url: url))
    return webView
  }

  func updateNSView(_ nsView: WKWebView, context: Context) {
    if nsView.url?.absoluteString != url.absoluteString {
      nsView.load(URLRequest(url: url))
    }
  }

  final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate {
    private var credentialsByProtectionSpace: [ProtectionSpaceKey: URLCredential] = [:]

    @MainActor
    func webView(
      _ webView: WKWebView,
      didReceive challenge: URLAuthenticationChallenge,
      completionHandler: @escaping @MainActor @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
      let protectionSpace = challenge.protectionSpace
      guard supportsInteractiveAuthentication(method: protectionSpace.authenticationMethod) else {
        completionHandler(.performDefaultHandling, nil)
        return
      }

      let key = ProtectionSpaceKey(
        host: protectionSpace.host,
        port: protectionSpace.port,
        realm: protectionSpace.realm ?? "",
        authenticationMethod: protectionSpace.authenticationMethod
      )

      if challenge.previousFailureCount == 0,
        let cachedCredential = credentialsByProtectionSpace[key]
      {
        completionHandler(.useCredential, cachedCredential)
        return
      }

      guard
        let credential = promptCredential(
          for: protectionSpace,
          prefilledUsername: challenge.proposedCredential?.user
        )
      else {
        completionHandler(.cancelAuthenticationChallenge, nil)
        return
      }

      credentialsByProtectionSpace[key] = credential
      completionHandler(.useCredential, credential)
    }

    func webView(
      _ webView: WKWebView,
      runJavaScriptAlertPanelWithMessage message: String,
      initiatedByFrame frame: WKFrameInfo,
      completionHandler: @escaping @Sendable () -> Void
    ) {
      _ = runAlert(
        message: message,
        style: .informational,
        defaultButtonTitle: "OK",
        alternateButtonTitle: nil
      )
      completionHandler()
    }

    @MainActor
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

    @MainActor
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

    private func supportsInteractiveAuthentication(method: String) -> Bool {
      method == NSURLAuthenticationMethodHTTPBasic
        || method == NSURLAuthenticationMethodHTTPDigest
    }

    private func promptCredential(
      for protectionSpace: URLProtectionSpace,
      prefilledUsername: String?
    ) -> URLCredential? {
      let alert = NSAlert()
      alert.messageText = "Authentication Required"
      alert.informativeText = credentialPromptDescription(for: protectionSpace)
      alert.alertStyle = .warning
      alert.addButton(withTitle: "Sign In")
      alert.addButton(withTitle: "Cancel")

      let usernameField = NSTextField(string: prefilledUsername ?? "")
      usernameField.placeholderString = "Username"

      let passwordField = NSSecureTextField(string: "")
      passwordField.placeholderString = "Password"

      let stack = NSStackView(views: [usernameField, passwordField])
      stack.orientation = .vertical
      stack.spacing = 8
      stack.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0)
      stack.translatesAutoresizingMaskIntoConstraints = false

      let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 58))
      container.addSubview(stack)

      NSLayoutConstraint.activate([
        stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        stack.topAnchor.constraint(equalTo: container.topAnchor),
        stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      ])

      alert.accessoryView = container

      let response = alert.runModal()
      guard response == .alertFirstButtonReturn else {
        return nil
      }

      let username = usernameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
      let password = passwordField.stringValue
      guard !username.isEmpty else {
        return nil
      }

      return URLCredential(user: username, password: password, persistence: .forSession)
    }

    private func credentialPromptDescription(for protectionSpace: URLProtectionSpace) -> String {
      let host = protectionSpace.host
      let realm = protectionSpace.realm ?? "Restricted Area"
      return "\(host) requires sign-in.\nRealm: \(realm)"
    }
  }
}

private struct ProtectionSpaceKey: Hashable {
  let host: String
  let port: Int
  let realm: String
  let authenticationMethod: String
}
