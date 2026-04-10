import Foundation

struct ToolbarNotificationGroup: Identifiable, Equatable {
  let id: String
  let name: String
  let sources: [ToolbarNotificationSourceGroup]

  var notificationCount: Int {
    sources.reduce(0) { count, source in
      count + source.items.count
    }
  }

  var unseenSourceCount: Int {
    sources.reduce(0) { count, source in
      count + (source.hasUnseenNotifications ? 1 : 0)
    }
  }
}

struct ToolbarNotificationSourceGroup: Identifiable, Equatable {
  let id: String
  let name: String
  let target: ToolbarNotificationSourceTarget
  let items: [ToolbarNotificationItem]

  var hasUnseenNotifications: Bool {
    items.contains { !$0.isRead }
  }
}

extension RepositoriesFeature.State {
  func toolbarNotificationGroups(
    terminalManager: WorktreeTerminalManager,
    remoteGroups: RemoteGroupsFeature.State
  ) -> [ToolbarNotificationGroup] {
    let repositoriesByID = Dictionary(uniqueKeysWithValues: repositories.map { ($0.id, $0) })
    var groups: [ToolbarNotificationGroup] = []

    for repositoryID in orderedRepositoryIDs() {
      guard let repository = repositoriesByID[repositoryID] else {
        continue
      }

      let worktreeGroups: [ToolbarNotificationSourceGroup] =
        orderedWorktrees(in: repository).compactMap { worktree -> ToolbarNotificationSourceGroup? in
          guard let state = terminalManager.stateIfExists(for: worktree.id), !state.notifications.isEmpty else {
            return nil
          }
          return ToolbarNotificationSourceGroup(
            id: "terminal:\(worktree.id)",
            name: worktree.name,
            target: .terminal(worktreeID: worktree.id),
            items: state.notifications.map { notification in
              .terminal(worktreeID: worktree.id, notification: notification)
            }
          )
        }

      if !worktreeGroups.isEmpty {
        groups.append(
          ToolbarNotificationGroup(
            id: "repository:\(repository.id)",
            name: repository.name,
            sources: worktreeGroups
          )
        )
      }
    }

    let remoteSources: [ToolbarNotificationSourceGroup] = remoteGroups.endpoints.compactMap { endpoint in
      let notifications = remoteGroups.notifications(for: endpoint.id)
      guard !notifications.isEmpty else {
        return nil
      }

      return ToolbarNotificationSourceGroup(
        id: "remote:\(endpoint.id.uuidString)",
        name: endpoint.displayName,
        target: .remote(endpointID: endpoint.id),
        items: notifications.map { notification in
          .remote(endpointID: endpoint.id, notification: notification)
        }
      )
    }
    if !remoteSources.isEmpty {
      groups.append(
        ToolbarNotificationGroup(
          id: "remote",
          name: "Remote",
          sources: remoteSources
        )
      )
    }

    return groups
  }
}

enum ToolbarNotificationSourceTarget: Equatable {
  case terminal(worktreeID: Worktree.ID)
  case remote(endpointID: UUID)
}

enum ToolbarNotificationItem: Identifiable, Equatable {
  case terminal(worktreeID: Worktree.ID, notification: WorktreeTerminalNotification)
  case remote(endpointID: UUID, notification: RemotePageNotification)

  var id: String {
    switch self {
    case .terminal(let worktreeID, let notification):
      return "terminal:\(worktreeID):\(notification.id.uuidString)"
    case .remote(let endpointID, let notification):
      return "remote:\(endpointID.uuidString):\(notification.id.uuidString)"
    }
  }

  var content: String {
    switch self {
    case .terminal(_, let notification):
      return notification.content
    case .remote(_, let notification):
      return notification.content
    }
  }

  var isRead: Bool {
    switch self {
    case .terminal(_, let notification):
      return notification.isRead
    case .remote(_, let notification):
      return notification.isRead
    }
  }

  var iconName: String {
    switch self {
    case .terminal:
      return "bell"
    case .remote:
      return "network"
    }
  }
}
