import ComposableArchitecture
import SwiftUI

struct RemoteGroupsSectionView: View {
  @Bindable var store: StoreOf<RemoteGroupsFeature>
  @State private var hoveredEndpointID: UUID?

  var body: some View {
    Section {
      if store.endpoints.isEmpty {
        Text("No remote endpoints")
          .foregroundStyle(.secondary)
      } else {
        ForEach(store.endpoints) { endpoint in
          endpointRow(endpoint)
            .tag(SidebarSelection.remoteEndpoint(endpoint.id))
            .contextMenu {
              Button("Remove Endpoint", role: .destructive) {
                store.send(.removeEndpoint(endpoint.id))
              }
              .help("Remove endpoint")
            }
        }
      }
    } header: {
      Text("Remote Endpoints")
    }
  }

  @ViewBuilder
  private func endpointRow(_ endpoint: RemoteEndpoint) -> some View {
    let host = endpoint.baseURL.host(percentEncoded: false) ?? endpoint.baseURL.absoluteString

    HStack(spacing: 8) {
      Image(systemName: "network")
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(host)
          .lineLimit(1)
        Text(endpoint.baseURL.absoluteString)
          .font(.footnote.monospaced())
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      Spacer()
      if hoveredEndpointID == endpoint.id {
        Button(role: .destructive) {
          store.send(.removeEndpoint(endpoint.id))
        } label: {
          Image(systemName: "trash")
            .accessibilityLabel("Remove Endpoint")
        }
        .buttonStyle(.plain)
        .help("Remove endpoint")
      }
    }
    .contentShape(Rectangle())
    .help(endpoint.baseURL.absoluteString)
    .onHover { isHovering in
      if isHovering {
        hoveredEndpointID = endpoint.id
      } else if hoveredEndpointID == endpoint.id {
        hoveredEndpointID = nil
      }
    }
  }
}
