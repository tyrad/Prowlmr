import ComposableArchitecture
import Foundation
import Sharing

@Reducer
struct RemoteGroupsFeature {
  @ObservableState
  struct State: Equatable {
    @Shared(.appStorage("remoteGroups_endpoints")) var endpoints: [RemoteEndpoint] = []
    @Shared(.appStorage("remoteGroups_selection")) var selection: RemoteSelection = .none
    var isAddPromptPresented = false
    var addURLDraft = ""
  }

  enum Action: Equatable {
    case setAddPromptPresented(Bool)
    case addURLDraftChanged(String)
    case submitEndpoint(urlText: String)
    case removeEndpoint(UUID)
    case clearSelection
    case selectEndpoint(UUID)
  }

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
