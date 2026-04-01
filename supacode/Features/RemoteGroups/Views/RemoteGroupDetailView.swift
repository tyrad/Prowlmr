import AppKit
import SwiftUI
import WebKit

struct RemoteGroupDetailView: View {
  let endpoint: RemoteEndpoint
  @AppStorage("remoteGroups_keepWebViewAlive") private var keepWebViewAlive = false
  @State private var reloadToken: UInt = 0

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        Spacer()

        Toggle("Keep Alive", isOn: $keepWebViewAlive)
          .toggleStyle(.switch)
          .help("Keep webview alive when switching selection (no shortcut)")
          .onChange(of: keepWebViewAlive) { _, enabled in
            RemoteWebViewCache.setKeepAliveEnabled(enabled)
          }

        Button {
          reloadToken &+= 1
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .keyboardShortcut("r", modifiers: .command)
        .help("Force refresh (\u{2318}R)")

        Button {
          NSWorkspace.shared.open(endpoint.baseURL)
        } label: {
          Image(systemName: "safari")
        }
        .keyboardShortcut("o", modifiers: [.command, .shift])
        .help("Open in browser (\u{2318}\u{21E7}O)")
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(.bar)

      Divider()

      RemoteGroupWebView(
        endpointID: endpoint.id,
        url: endpoint.baseURL,
        reloadToken: reloadToken,
        keepAlive: keepWebViewAlive
      )
      .id(endpoint.id)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(nsColor: .windowBackgroundColor))
    .onAppear {
      RemoteWebViewCache.setKeepAliveEnabled(keepWebViewAlive)
    }
  }
}

private struct RemoteGroupWebView: NSViewRepresentable {
  let endpointID: UUID
  let url: URL
  let reloadToken: UInt
  let keepAlive: Bool

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeNSView(context: Context) -> WKWebView {
    RemoteWebViewCache.setKeepAliveEnabled(keepAlive)
    let webView = RemoteWebViewCache.webView(for: endpointID, keepAlive: keepAlive) {
      let view = WKWebView(frame: .zero, configuration: RemoteWebViewEnvironment.makeConfiguration())
      view.allowsBackForwardNavigationGestures = true
      return view
    }
    // Cached web views may outlive prior coordinators; always rebind delegates.
    webView.uiDelegate = context.coordinator
    webView.navigationDelegate = context.coordinator
    context.coordinator.lastReloadToken = reloadToken
    loadIfNeeded(webView: webView, url: url, keepAlive: keepAlive)
    return webView
  }

  func updateNSView(_ nsView: WKWebView, context: Context) {
    RemoteWebViewCache.setKeepAliveEnabled(keepAlive)
    nsView.uiDelegate = context.coordinator
    nsView.navigationDelegate = context.coordinator
    loadIfNeeded(webView: nsView, url: url, keepAlive: keepAlive)
    if context.coordinator.lastReloadToken != reloadToken {
      context.coordinator.lastReloadToken = reloadToken
      nsView.reloadFromOrigin()
    }
  }

  final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate {
    var lastReloadToken: UInt = 0

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

      if challenge.previousFailureCount > 0 {
        // Wrong credential was rejected; clear cached/persisted value and prompt again.
        RemoteWebViewCredentialStore.invalidate(for: protectionSpace)
      }

      if challenge.previousFailureCount == 0,
        let cachedCredential = RemoteWebViewCredentialStore.credential(
          for: protectionSpace,
          proposedCredential: challenge.proposedCredential
        )
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

      RemoteWebViewCredentialStore.save(credential, for: protectionSpace)
      completionHandler(.useCredential, credential)
    }

    @MainActor
    func webView(
      _ webView: WKWebView,
      runJavaScriptAlertPanelWithMessage message: String,
      initiatedByFrame frame: WKFrameInfo,
      completionHandler: @escaping @MainActor @Sendable () -> Void
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

      return URLCredential(user: username, password: password, persistence: .permanent)
    }

    private func credentialPromptDescription(for protectionSpace: URLProtectionSpace) -> String {
      let host = protectionSpace.host
      let realm = protectionSpace.realm ?? "Restricted Area"
      return "\(host) requires sign-in.\nRealm: \(realm)"
    }
  }

  private func loadIfNeeded(webView: WKWebView, url: URL, keepAlive: Bool) {
    if RemoteWebViewLoadPolicy.shouldLoad(
      currentURL: webView.url,
      targetURL: url,
      keepAlive: keepAlive
    ) {
      webView.load(URLRequest(url: url))
    }
  }
}

private struct ProtectionSpaceKey: Hashable {
  let host: String
  let port: Int
  let realm: String
  let authenticationMethod: String
}

@MainActor
private enum RemoteWebViewCredentialStore {
  private static var credentialsByProtectionSpace: [ProtectionSpaceKey: URLCredential] = [:]

  static func credential(
    for protectionSpace: URLProtectionSpace,
    proposedCredential: URLCredential?
  ) -> URLCredential? {
    let key = ProtectionSpaceKey(from: protectionSpace)
    if let cached = credentialsByProtectionSpace[key] {
      return cached
    }
    if let proposedCredential {
      credentialsByProtectionSpace[key] = proposedCredential
      return proposedCredential
    }
    if let persisted = URLCredentialStorage.shared.defaultCredential(for: protectionSpace) {
      credentialsByProtectionSpace[key] = persisted
      return persisted
    }
    if let persistedMap = URLCredentialStorage.shared.credentials(for: protectionSpace),
      let persisted = persistedMap.values.first
    {
      credentialsByProtectionSpace[key] = persisted
      return persisted
    }
    return nil
  }

  static func save(_ credential: URLCredential, for protectionSpace: URLProtectionSpace) {
    let key = ProtectionSpaceKey(from: protectionSpace)
    credentialsByProtectionSpace[key] = credential
    URLCredentialStorage.shared.setDefaultCredential(credential, for: protectionSpace)
    URLCredentialStorage.shared.set(credential, for: protectionSpace)
  }

  static func invalidate(for protectionSpace: URLProtectionSpace) {
    let key = ProtectionSpaceKey(from: protectionSpace)
    if let existing = credentialsByProtectionSpace.removeValue(forKey: key) {
      URLCredentialStorage.shared.remove(existing, for: protectionSpace)
    }
    if let defaultCredential = URLCredentialStorage.shared.defaultCredential(for: protectionSpace) {
      URLCredentialStorage.shared.remove(defaultCredential, for: protectionSpace)
    }
  }
}

private extension ProtectionSpaceKey {
  init(from protectionSpace: URLProtectionSpace) {
    self.init(
      host: protectionSpace.host,
      port: protectionSpace.port,
      realm: protectionSpace.realm ?? "",
      authenticationMethod: protectionSpace.authenticationMethod
    )
  }
}

@MainActor
private enum RemoteWebViewEnvironment {
  private static let sharedWebsiteDataStore = WKWebsiteDataStore.default()
  private static var hasConfiguredURLCache = false

  static func makeConfiguration() -> WKWebViewConfiguration {
    configureResourceCacheIfNeeded()

    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = sharedWebsiteDataStore
    return configuration
  }

  private static func configureResourceCacheIfNeeded() {
    guard !hasConfiguredURLCache else {
      return
    }
    hasConfiguredURLCache = true

    let memoryCapacity = 64 * 1024 * 1024
    let diskCapacity = 512 * 1024 * 1024
    URLCache.shared = URLCache(
      memoryCapacity: memoryCapacity,
      diskCapacity: diskCapacity,
      diskPath: "com.onevcat.prowl.remote-webview"
    )
  }
}

nonisolated enum RemoteWebViewLoadPolicy {
  static func shouldLoad(
    currentURL: URL?,
    targetURL: URL,
    keepAlive: Bool
  ) -> Bool {
    guard let currentURL else {
      return true
    }
    guard !keepAlive else {
      return false
    }
    return currentURL.absoluteString != targetURL.absoluteString
  }
}

@MainActor
private enum RemoteWebViewCache {
  private static var isKeepAliveEnabled = false
  private static var webViewsByEndpointID: [UUID: WKWebView] = [:]

  static func setKeepAliveEnabled(_ enabled: Bool) {
    isKeepAliveEnabled = enabled
    if !enabled {
      webViewsByEndpointID.removeAll()
    }
  }

  static func webView(
    for endpointID: UUID,
    keepAlive: Bool,
    make: () -> WKWebView
  ) -> WKWebView {
    guard keepAlive else {
      return make()
    }
    if let cached = webViewsByEndpointID[endpointID] {
      return cached
    }
    let created = make()
    webViewsByEndpointID[endpointID] = created
    return created
  }
}
