import DependenciesTestSupport
import Foundation
import IdentifiedCollections
import Sharing
import Testing

@testable import supacode

@MainActor
struct ToolbarNotificationGroupingTests {
  @Test(.dependencies) func groupsNotificationsByRepositoryAndRemoteEndpointInDisplayOrder() {
    let repoAPath = "/tmp/repo-a"
    let repoBPath = "/tmp/repo-b"
    let remoteEndpointID = UUID()

    let repoAMain = makeWorktree(id: repoAPath, name: "main", repoRoot: repoAPath)
    let repoAOne = makeWorktree(id: "\(repoAPath)/one", name: "one", repoRoot: repoAPath)
    let repoATwo = makeWorktree(id: "\(repoAPath)/two", name: "two", repoRoot: repoAPath)

    let repoBMain = makeWorktree(id: repoBPath, name: "main", repoRoot: repoBPath)
    let repoBOne = makeWorktree(id: "\(repoBPath)/one", name: "one", repoRoot: repoBPath)

    let repoA = makeRepository(id: repoAPath, name: "Repo A", worktrees: [repoAMain, repoAOne, repoATwo])
    let repoB = makeRepository(id: repoBPath, name: "Repo B", worktrees: [repoBMain, repoBOne])
    let remoteState = makeRemoteState(
      endpoints: [
        RemoteEndpoint(
          id: remoteEndpointID,
          baseURL: URL(string: "https://remote.example.com/mini-terminal/")!
        )
      ],
      notificationsByEndpointID: [
        remoteEndpointID: [
          RemotePageNotification(
            id: UUID(),
            endpointID: remoteEndpointID,
            title: "Remote A",
            body: "done",
            createdAt: Date(timeIntervalSince1970: 10)
          )
        ]
      ]
    )

    var state = RepositoriesFeature.State(repositories: [repoA, repoB])
    state.repositoryRoots = [repoA.rootURL, repoB.rootURL]
    state.repositoryOrderIDs = [repoB.id, repoA.id]
    state.worktreeOrderByRepository[repoA.id] = [repoATwo.id, repoAOne.id]

    let manager = WorktreeTerminalManager(runtime: GhosttyRuntime())
    manager.state(for: repoAOne).notifications = [
      WorktreeTerminalNotification(surfaceId: UUID(), title: "A1", body: "done", isRead: true)
    ]
    manager.state(for: repoATwo).notifications = [
      WorktreeTerminalNotification(surfaceId: UUID(), title: "A2", body: "done")
    ]
    manager.state(for: repoBOne).notifications = [
      WorktreeTerminalNotification(surfaceId: UUID(), title: "B1", body: "done", isRead: true)
    ]

    let groups = state.toolbarNotificationGroups(
      terminalManager: manager,
      remoteGroups: remoteState
    )

    #expect(groups.map(\.name) == ["Repo B", "Repo A", "Remote"])
    #expect(groups[0].sources.map(\.name) == ["one"])
    #expect(groups[1].sources.map(\.name) == ["two", "one"])
    #expect(groups[2].sources.map(\.name) == ["remote.example.com"])
    #expect(groups[1].unseenSourceCount == 1)
    #expect(groups[2].sources[0].target == .remote(endpointID: remoteEndpointID))
  }

  @Test(.dependencies) func omitsArchivedAndEmptyNotificationGroups() {
    let repoAPath = "/tmp/repo-a"
    let repoBPath = "/tmp/repo-b"

    let repoAMain = makeWorktree(id: repoAPath, name: "main", repoRoot: repoAPath)
    let repoAArchived = makeWorktree(id: "\(repoAPath)/archived", name: "archived", repoRoot: repoAPath)
    let repoBMain = makeWorktree(id: repoBPath, name: "main", repoRoot: repoBPath)
    let repoBEmpty = makeWorktree(id: "\(repoBPath)/empty", name: "empty", repoRoot: repoBPath)

    let repoA = makeRepository(id: repoAPath, name: "Repo A", worktrees: [repoAMain, repoAArchived])
    let repoB = makeRepository(id: repoBPath, name: "Repo B", worktrees: [repoBMain, repoBEmpty])

    var state = RepositoriesFeature.State(repositories: [repoA, repoB])
    state.repositoryRoots = [repoA.rootURL, repoB.rootURL]
    state.archivedWorktreeIDs = [repoAArchived.id]

    let manager = WorktreeTerminalManager(runtime: GhosttyRuntime())
    manager.state(for: repoAArchived).notifications = [
      WorktreeTerminalNotification(surfaceId: UUID(), title: "Archived", body: "hidden")
    ]

    let groups = state.toolbarNotificationGroups(
      terminalManager: manager,
      remoteGroups: makeRemoteState()
    )

    #expect(groups.isEmpty)
  }

  @Test(.dependencies) func unseenSourceCountUsesUnreadNotificationsOnlyAcrossTerminalAndRemote() {
    let repoPath = "/tmp/repo"
    let remoteEndpointID = UUID()
    let main = makeWorktree(id: repoPath, name: "main", repoRoot: repoPath)
    let readOnly = makeWorktree(id: "\(repoPath)/read-only", name: "read-only", repoRoot: repoPath)
    let mixed = makeWorktree(id: "\(repoPath)/mixed", name: "mixed", repoRoot: repoPath)

    let repo = makeRepository(id: repoPath, name: "Repo", worktrees: [main, readOnly, mixed])
    var state = RepositoriesFeature.State(repositories: [repo])
    state.repositoryRoots = [repo.rootURL]

    let manager = WorktreeTerminalManager(runtime: GhosttyRuntime())
    manager.state(for: readOnly).notifications = [
      WorktreeTerminalNotification(surfaceId: UUID(), title: "Read 1", body: "done", isRead: true)
    ]
    manager.state(for: mixed).notifications = [
      WorktreeTerminalNotification(surfaceId: UUID(), title: "Read 2", body: "done", isRead: true),
      WorktreeTerminalNotification(surfaceId: UUID(), title: "Unread", body: "new", isRead: false),
    ]
    let remoteState = makeRemoteState(
      endpoints: [
        RemoteEndpoint(
          id: remoteEndpointID,
          baseURL: URL(string: "https://remote.example.com/mini-terminal/")!
        )
      ],
      notificationsByEndpointID: [
        remoteEndpointID: [
          RemotePageNotification(
            id: UUID(),
            endpointID: remoteEndpointID,
            title: "Remote read",
            body: "done",
            isRead: true,
            createdAt: Date(timeIntervalSince1970: 10)
          ),
          RemotePageNotification(
            id: UUID(),
            endpointID: remoteEndpointID,
            title: "Remote unread",
            body: "new",
            isRead: false,
            createdAt: Date(timeIntervalSince1970: 20)
          ),
        ]
      ]
    )

    let groups = state.toolbarNotificationGroups(
      terminalManager: manager,
      remoteGroups: remoteState
    )

    #expect(groups.count == 2)
    #expect(groups[0].notificationCount == 3)
    #expect(groups[0].unseenSourceCount == 1)
    #expect(groups[1].notificationCount == 2)
    #expect(groups[1].unseenSourceCount == 1)
  }

  @Test(.dependencies) func keepsReadOnlyNotificationsInTerminalAndRemoteGroups() {
    let repoPath = "/tmp/repo"
    let remoteEndpointID = UUID()
    let main = makeWorktree(id: repoPath, name: "main", repoRoot: repoPath)
    let feature = makeWorktree(id: "\(repoPath)/feature", name: "feature", repoRoot: repoPath)

    let repo = makeRepository(id: repoPath, name: "Repo", worktrees: [main, feature])
    var state = RepositoriesFeature.State(repositories: [repo])
    state.repositoryRoots = [repo.rootURL]

    let manager = WorktreeTerminalManager(runtime: GhosttyRuntime())
    manager.state(for: feature).notifications = [
      WorktreeTerminalNotification(surfaceId: UUID(), title: "Read", body: "kept", isRead: true)
    ]
    let remoteState = makeRemoteState(
      endpoints: [
        RemoteEndpoint(
          id: remoteEndpointID,
          baseURL: URL(string: "https://remote.example.com/mini-terminal/")!
        )
      ],
      notificationsByEndpointID: [
        remoteEndpointID: [
          RemotePageNotification(
            id: UUID(),
            endpointID: remoteEndpointID,
            title: "Remote read",
            body: "kept",
            isRead: true,
            createdAt: Date(timeIntervalSince1970: 10)
          )
        ]
      ]
    )

    let groups = state.toolbarNotificationGroups(
      terminalManager: manager,
      remoteGroups: remoteState
    )

    #expect(groups.map(\.name) == ["Repo", "Remote"])
    #expect(groups[0].sources.map(\.name) == ["feature"])
    #expect(groups[0].sources[0].items.map(\.content) == ["Read - kept"])
    #expect(groups[0].unseenSourceCount == 0)
    #expect(groups[1].sources[0].items.map(\.content) == ["Remote read - kept"])
    #expect(groups[1].unseenSourceCount == 0)
  }

  private func makeWorktree(
    id: String,
    name: String,
    repoRoot: String
  ) -> Worktree {
    Worktree(
      id: id,
      name: name,
      detail: "detail",
      workingDirectory: URL(fileURLWithPath: id),
      repositoryRootURL: URL(fileURLWithPath: repoRoot)
    )
  }

  private func makeRepository(
    id: String,
    name: String,
    worktrees: [Worktree]
  ) -> Repository {
    Repository(
      id: id,
      rootURL: URL(fileURLWithPath: id),
      name: name,
      worktrees: IdentifiedArray(uniqueElements: worktrees)
    )
  }

  private func makeRemoteState(
    endpoints: [RemoteEndpoint] = [],
    notificationsByEndpointID: [UUID: [RemotePageNotification]] = [:]
  ) -> RemoteGroupsFeature.State {
    var state = RemoteGroupsFeature.State()
    state.$endpoints.withLock {
      $0 = endpoints
    }
    state.notificationsByEndpointID = notificationsByEndpointID
    return state
  }
}
