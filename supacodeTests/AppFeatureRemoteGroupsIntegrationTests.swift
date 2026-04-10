import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import Testing

@testable import supacode

@MainActor
struct AppFeatureRemoteGroupsIntegrationTests {
  @Test(.dependencies) func app_routes_remote_groups_actions() async {
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    }

    await store.send(.remoteGroups(.setAddPromptPresented(true))) {
      $0.remoteGroups.isAddPromptPresented = true
    }
  }

  @Test(.dependencies) func selectingRemoteEndpointClearsSelectedTerminalWorktree() async {
    let worktree = makeWorktree()
    let settingsStorage = SettingsTestStorage()
    let settingsFileURL = URL(
      fileURLWithPath: "/tmp/supacode-settings-\(UUID().uuidString).json"
    )
    let terminalCommands = LockIsolated<[TerminalClient.Command]>([])
    let endpointID = UUID()
    let store = TestStore(
      initialState: AppFeature.State(
        repositories: makeRepositoriesState(worktree: worktree),
        settings: SettingsFeature.State()
      )
    ) {
      AppFeature()
    } withDependencies: {
      $0.settingsFileStorage = settingsStorage.storage
      $0.settingsFileURL = settingsFileURL
      $0.terminalClient.send = { command in
        terminalCommands.withValue { $0.append(command) }
      }
    }

    await store.send(.remoteGroups(.selectEndpoint(endpointID))) {
      $0.remoteGroups.$selection.withLock {
        $0 = .overview(endpointID: endpointID)
      }
    }
    await store.finish()

    #expect(terminalCommands.value == [.setSelectedWorktreeID(nil)])
  }

  @Test(.dependencies) func clearingRemoteSelectionRestoresSelectedTerminalWorktree() async {
    let worktree = makeWorktree()
    let endpointID = UUID()
    let settingsStorage = SettingsTestStorage()
    let settingsFileURL = URL(
      fileURLWithPath: "/tmp/supacode-settings-\(UUID().uuidString).json"
    )
    let terminalCommands = LockIsolated<[TerminalClient.Command]>([])
    let state = AppFeature.State(
      repositories: makeRepositoriesState(worktree: worktree),
      settings: SettingsFeature.State()
    )
    state.remoteGroups.$selection.withLock {
      $0 = .overview(endpointID: endpointID)
    }
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.settingsFileStorage = settingsStorage.storage
      $0.settingsFileURL = settingsFileURL
      $0.terminalClient.send = { command in
        terminalCommands.withValue { $0.append(command) }
      }
    }

    await store.send(.remoteGroups(.clearSelection)) {
      $0.remoteGroups.$selection.withLock {
        $0 = .none
      }
    }
    await store.finish()

    #expect(terminalCommands.value == [.setSelectedWorktreeID(worktree.id)])
  }

  private func makeWorktree() -> Worktree {
    let repositoryRootURL = URL(fileURLWithPath: "/tmp/repo-\(UUID().uuidString)")
    let worktreeURL = repositoryRootURL.appending(path: "wt-1")
    return Worktree(
      id: worktreeURL.path(percentEncoded: false),
      name: "wt-1",
      detail: "detail",
      workingDirectory: worktreeURL,
      repositoryRootURL: repositoryRootURL
    )
  }

  private func makeRepositoriesState(worktree: Worktree) -> RepositoriesFeature.State {
    let repository = Repository(
      id: worktree.repositoryRootURL.path(percentEncoded: false),
      rootURL: worktree.repositoryRootURL,
      name: "repo",
      worktrees: [worktree]
    )
    var repositoriesState = RepositoriesFeature.State()
    repositoriesState.repositories = [repository]
    repositoriesState.selection = .worktree(worktree.id)
    return repositoriesState
  }
}
