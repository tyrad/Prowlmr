import ComposableArchitecture
import Foundation
import Sharing

@Reducer
struct RemoteGroupsFeature {
  @ObservableState
  struct State: Equatable {
    struct NotificationRowState: Equatable {
      let notifications: [RemotePageNotification]
      let showsNotificationIndicator: Bool
    }

    @Shared(.appStorage("remoteGroups_endpoints")) var endpoints: [RemoteEndpoint] = []
    @Shared(.appStorage("remoteGroups_selection")) var selection: RemoteSelection = .none
    var notificationsByEndpointID: [UUID: [RemotePageNotification]] = [:]
    var isAddPromptPresented = false
    var addURLDraft = ""

    func notifications(for endpointID: UUID) -> [RemotePageNotification] {
      notificationsByEndpointID[endpointID] ?? []
    }

    func notificationRowState(for endpointID: UUID) -> NotificationRowState {
      let notifications = notifications(for: endpointID)
      return NotificationRowState(
        notifications: notifications,
        showsNotificationIndicator: notifications.contains { !$0.isRead }
      )
    }
  }

  enum Action: Equatable {
    case setAddPromptPresented(Bool)
    case addURLDraftChanged(String)
    case submitEndpoint(urlText: String)
    case removeEndpoint(UUID)
    case clearSelection
    case selectEndpoint(UUID)
    case receiveBridgeNotification(endpointID: UUID, title: String, body: String, tag: String?)
    case markNotificationRead(endpointID: UUID, notificationID: UUID)
    case dismissAllNotifications
    case delegate(Delegate)
  }

  enum Delegate: Equatable {
    case notificationReceived(endpointID: UUID, title: String, body: String)
  }

  @Dependency(\.date.now) private var now
  @Dependency(\.uuid) private var uuid

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .setAddPromptPresented(let presented):
        state.isAddPromptPresented = presented
        if !presented {
          state.addURLDraft = ""
        }
        return .none

      case .addURLDraftChanged(let value):
        state.addURLDraft = value
        return .none

      case .submitEndpoint(let urlText):
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawURL = URL(string: trimmed),
          rawURL.scheme != nil,
          rawURL.host != nil
        else {
          return .none
        }

        let normalizedURL = rawURL.absoluteString.hasSuffix("/") ? rawURL : rawURL.appending(path: "")
        let endpoint: RemoteEndpoint
        if let existing = state.endpoints.first(where: { $0.baseURL == normalizedURL }) {
          endpoint = existing
        } else {
          let created = RemoteEndpoint(baseURL: normalizedURL)
          state.$endpoints.withLock {
            $0.append(created)
          }
          endpoint = created
        }

        state.$selection.withLock {
          $0 = .overview(endpointID: endpoint.id)
        }

        state.isAddPromptPresented = false
        state.addURLDraft = ""
        return .none

      case .removeEndpoint(let endpointID):
        state.$endpoints.withLock {
          $0.removeAll(where: { $0.id == endpointID })
        }
        state.notificationsByEndpointID.removeValue(forKey: endpointID)

        if state.selection.matches(endpointID: endpointID) {
          state.$selection.withLock {
            $0 = .none
          }
        }
        return .none

      case .clearSelection:
        state.$selection.withLock {
          $0 = .none
        }
        return .none

      case .selectEndpoint(let endpointID):
        state.$selection.withLock {
          $0 = .overview(endpointID: endpointID)
        }
        return .none

      case .receiveBridgeNotification(let endpointID, let title, let body, let tag):
        guard state.endpoints.contains(where: { $0.id == endpointID }) else {
          return .none
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !(trimmedTitle.isEmpty && trimmedBody.isEmpty) else {
          return .none
        }

        let resolvedTitle: String
        let resolvedBody: String
        if trimmedTitle.isEmpty {
          resolvedTitle = trimmedBody
          resolvedBody = ""
        } else {
          resolvedTitle = trimmedTitle
          resolvedBody = trimmedBody
        }

        let trimmedTag = tag?.trimmingCharacters(in: .whitespacesAndNewlines)
        state.notificationsByEndpointID[endpointID, default: []].insert(
          RemotePageNotification(
            id: uuid(),
            endpointID: endpointID,
            title: resolvedTitle,
            body: resolvedBody,
            tag: trimmedTag?.isEmpty == true ? nil : trimmedTag,
            createdAt: now
          ),
          at: 0
        )

        return .send(
          .delegate(
            .notificationReceived(
              endpointID: endpointID,
              title: resolvedTitle,
              body: resolvedBody
            )
          )
        )

      case .markNotificationRead(let endpointID, let notificationID):
        guard var notifications = state.notificationsByEndpointID[endpointID] else {
          return .none
        }
        guard let index = notifications.firstIndex(where: { $0.id == notificationID }) else {
          return .none
        }
        notifications[index].isRead = true
        state.notificationsByEndpointID[endpointID] = notifications
        return .none

      case .dismissAllNotifications:
        state.notificationsByEndpointID = [:]
        return .none

      case .delegate:
        return .none
      }
    }
  }
}

private extension RemoteSelection {
  func matches(endpointID: UUID) -> Bool {
    switch self {
    case .none:
      return false
    case .overview(let selectedEndpointID):
      return selectedEndpointID == endpointID
    case .group(let selectedEndpointID, _):
      return selectedEndpointID == endpointID
    }
  }
}
