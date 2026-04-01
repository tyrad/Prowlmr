import ComposableArchitecture
import Foundation
import Testing

@testable import supacode

@MainActor
struct RemoteGroupsFeatureTests {
  @Test func submit_endpoint_adds_and_selects_endpoint() async throws {
    let store = TestStore(initialState: RemoteGroupsFeature.State()) {
      RemoteGroupsFeature()
    }

    await store.send(.submitEndpoint(urlText: "https://example.com/mini-terminal/"))

    let endpointID = try #require(store.state.endpoints.first?.id)
    #expect(store.state.selection == .overview(endpointID: endpointID))
  }

  @Test func remove_endpoint_cleans_state_and_selection() async {
    let endpointID = UUID()
    let otherEndpointID = UUID()

    let state = RemoteGroupsFeature.State()
    state.$endpoints.withLock {
      $0 = [
        RemoteEndpoint(id: endpointID, baseURL: URL(string: "https://example.com/mini-terminal/")!),
        RemoteEndpoint(id: otherEndpointID, baseURL: URL(string: "https://other.example.com/mini-terminal/")!),
      ]
    }
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
      $0.$selection.withLock {
        $0 = .none
      }
    }
  }
}
