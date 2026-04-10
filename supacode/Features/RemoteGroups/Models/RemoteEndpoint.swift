import Foundation

nonisolated struct RemoteEndpoint: Equatable, Codable, Identifiable, Sendable {
  var id: UUID
  var baseURL: URL

  init(id: UUID = UUID(), baseURL: URL) {
    self.id = id
    self.baseURL = baseURL
  }

  var overviewURL: URL {
    baseURL
  }

  var displayName: String {
    baseURL.host(percentEncoded: false) ?? baseURL.absoluteString
  }

  func groupURL(group: String) -> URL {
    baseURL.appending(queryItems: [URLQueryItem(name: "group", value: group)])
  }
}
