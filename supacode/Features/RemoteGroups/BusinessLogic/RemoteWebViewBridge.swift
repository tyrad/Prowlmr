import Foundation

enum RemoteBridgeRequest: Equatable, Sendable {
  case notification(RemoteBridgeNotificationRequest)
  case markRead(RemoteBridgeMarkReadRequest)
}

struct RemoteBridgeNotificationRequest: Equatable, Sendable {
  let title: String
  let body: String
  let tag: String?
}

struct RemoteBridgeMarkReadRequest: Equatable, Sendable {
  let tag: String
}

nonisolated enum RemoteWebViewBridge {
  static let handlerName = "prowlBridge"

  static func request(
    from body: Any,
    originURL: URL?,
    endpointURL: URL
  ) -> RemoteBridgeRequest? {
    guard
      let originURL,
      isSameOrigin(originURL, endpointURL),
      let payload = body as? [String: Any]
    else {
      return nil
    }

    switch payload["type"] as? String {
    case "notify":
      return notificationRequest(from: payload)
    case "markRead":
      return markReadRequest(from: payload)
    default:
      return nil
    }
  }

  private static func notificationRequest(from payload: [String: Any]) -> RemoteBridgeRequest? {
    let trimmedTitle = trim((payload["title"] as? String) ?? "")
    let trimmedBody = trim((payload["body"] as? String) ?? "")
    let trimmedTag = trim((payload["tag"] as? String) ?? "")
    let tag = trimmedTag.isEmpty ? nil : trimmedTag

    switch (trimmedTitle.isEmpty, trimmedBody.isEmpty) {
    case (true, true):
      return nil
    case (true, false):
      return .notification(
        RemoteBridgeNotificationRequest(
          title: trimmedBody,
          body: "",
          tag: tag
        )
      )
    case (false, _):
      return .notification(
        RemoteBridgeNotificationRequest(
          title: trimmedTitle,
          body: trimmedBody,
          tag: tag
        )
      )
    }
  }

  private static func markReadRequest(from payload: [String: Any]) -> RemoteBridgeRequest? {
    let trimmedTag = trim((payload["tag"] as? String) ?? "")
    guard !trimmedTag.isEmpty else {
      return nil
    }

    return .markRead(RemoteBridgeMarkReadRequest(tag: trimmedTag))
  }

  static func isSameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
    lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
      && lhs.host(percentEncoded: false)?.lowercased() == rhs.host(percentEncoded: false)?.lowercased()
      && normalizedPort(for: lhs) == normalizedPort(for: rhs)
  }

  private static func normalizedPort(for url: URL) -> Int? {
    if let port = url.port {
      return port
    }

    switch url.scheme?.lowercased() {
    case "http":
      return 80
    case "https":
      return 443
    default:
      return nil
    }
  }

  private static func trim(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
