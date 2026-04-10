import Foundation

struct RemotePageNotification: Identifiable, Equatable, Sendable {
  let id: UUID
  let endpointID: UUID
  let title: String
  let body: String
  let tag: String?
  var isRead: Bool
  let createdAt: Date

  init(
    id: UUID = UUID(),
    endpointID: UUID,
    title: String,
    body: String,
    tag: String? = nil,
    isRead: Bool = false,
    createdAt: Date = .now
  ) {
    self.id = id
    self.endpointID = endpointID
    self.title = title
    self.body = body
    self.tag = tag
    self.isRead = isRead
    self.createdAt = createdAt
  }

  var content: String {
    [title, body].filter { !$0.isEmpty }.joined(separator: " - ")
  }
}
