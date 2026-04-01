import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import Testing

@testable import supacode

@MainActor
struct RemoteGroupsFeatureTests {
  @Test(.dependencies) func submit_endpoint_fetches_and_groups() async throws {
    let store = TestStore(initialState: RemoteGroupsFeature.State()) {
      RemoteGroupsFeature()
    } withDependencies: {
      $0.remoteTerminalClient.listSessions = { _ in
        [
          .init(id: "1", scope: "multi-tmux", reuseKey: "multi-tmux:alpha:1", cwd: "~", updatedAt: ""),
          .init(id: "2", scope: "multi-tmux", reuseKey: "multi-tmux:alpha:2", cwd: "~", updatedAt: ""),
          .init(id: "3", scope: "other", reuseKey: "other:ignored:1", cwd: "~", updatedAt: ""),
        ]
      }
    }
    store.exhaustivity = .off

    await store.send(.submitEndpoint(urlText: "https://example.com/mini-terminal/", initialGroup: ""))

    let endpointID = try #require(store.state.endpoints.first?.id)
    #expect(store.state.selection == .overview(endpointID: endpointID))

    await store.receive(\.fetchEndpointSessions)
    #expect(store.state.loadingEndpointIDs.contains(endpointID))

    await store.receive(/RemoteGroupsFeature.Action.endpointSessionsResponse)
    #expect(!store.state.loadingEndpointIDs.contains(endpointID))
    #expect(
      store.state.groupsByEndpointID[endpointID] == [
        RemoteGroupRef(group: "alpha", sessionCount: 2)
      ]
    )
    #expect(store.state.errorByEndpointID[endpointID] == nil)
  }

  @Test func remove_endpoint_cleans_state_and_selection() async {
    let endpointID = UUID()
    let otherEndpointID = UUID()

    var state = RemoteGroupsFeature.State()
    state.$endpoints.withLock {
      $0 = [
        RemoteEndpoint(id: endpointID, baseURL: URL(string: "https://example.com/mini-terminal/")!),
        RemoteEndpoint(id: otherEndpointID, baseURL: URL(string: "https://other.example.com/mini-terminal/")!),
      ]
    }
    state.groupsByEndpointID = [
      endpointID: [RemoteGroupRef(group: "alpha", sessionCount: 2)],
      otherEndpointID: [RemoteGroupRef(group: "beta", sessionCount: 1)],
    ]
    state.loadingEndpointIDs = [endpointID]
    state.errorByEndpointID = [endpointID: "boom"]
    state.$selection.withLock {
      $0 = .group(endpointID: endpointID, group: "alpha")
    }

    let store = TestStore(initialState: state) {
      RemoteGroupsFeature()
    }

    store.exhaustivity = .off
    await store.send(.removeEndpoint(endpointID)) {
      $0.$endpoints.withLock {
        $0 = [
          RemoteEndpoint(
            id: otherEndpointID,
            baseURL: URL(string: "https://other.example.com/mini-terminal/")!
          ),
        ]
      }
      $0.groupsByEndpointID = [otherEndpointID: [RemoteGroupRef(group: "beta", sessionCount: 1)]]
      $0.loadingEndpointIDs = []
      $0.errorByEndpointID = [:]
      $0.$selection.withLock {
        $0 = .none
      }
    }
  }
}
