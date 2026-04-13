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
    let rowState = store.state.notificationRowState(for: endpoint.id)

    HStack(spacing: 8) {
      Group {
        if rowState.showsNotificationIndicator {
          RemoteNotificationPopoverButton(
            notifications: rowState.notifications,
            onSelectNotification: { notification in
              store.send(.markNotificationRead(endpointID: endpoint.id, notificationID: notification.id))
              store.send(.selectEndpoint(endpoint.id))
            }
          ) {
            Image(systemName: "bell.fill")
              .font(.caption)
              .foregroundStyle(.orange)
              .accessibilityLabel("Unread notifications")
          }
        } else {
          Image(systemName: "network")
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
      }
      .frame(width: 16, height: 16)
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

private struct RemoteNotificationPopoverButton<Label: View>: View {
  let notifications: [RemotePageNotification]
  let onSelectNotification: (RemotePageNotification) -> Void
  @ViewBuilder let label: () -> Label
  @State private var isPresented = false
  @State private var isHoveringButton = false
  @State private var isHoveringPopover = false
  @State private var closeTask: Task<Void, Never>?

  var body: some View {
    Button {
      isPresented.toggle()
    } label: {
      label()
    }
    .buttonStyle(.plain)
    .contentShape(.rect)
    .help("Unread notifications. Hover to show.")
    .accessibilityLabel("Unread notifications")
    .onHover { hovering in
      isHoveringButton = hovering
      updatePresentation()
    }
    .popover(isPresented: $isPresented) {
      RemoteNotificationPopoverView(
        notifications: notifications,
        onSelectNotification: { notification in
          onSelectNotification(notification)
          isPresented = false
        }
      )
      .onHover { hovering in
        isHoveringPopover = hovering
        updatePresentation()
      }
      .onDisappear {
        isHoveringPopover = false
        updatePresentation()
      }
    }
    .onDisappear {
      closeTask?.cancel()
    }
  }

  private func updatePresentation() {
    if isHoveringButton || isHoveringPopover {
      closeTask?.cancel()
      isPresented = true
      return
    }
    closeTask?.cancel()
    closeTask = Task { @MainActor in
      try? await ContinuousClock().sleep(for: .milliseconds(150))
      if !Task.isCancelled {
        isPresented = false
      }
    }
  }
}

private struct RemoteNotificationPopoverView: View {
  let notifications: [RemotePageNotification]
  let onSelectNotification: (RemotePageNotification) -> Void

  var body: some View {
    let count = notifications.count
    let countLabel = count == 1 ? "notification" : "notifications"

    ScrollView {
      VStack(alignment: .leading) {
        Text("Notifications")
          .font(.headline)
        Text("\(count) \(countLabel)")
          .font(.subheadline)
          .foregroundStyle(.secondary)
        Divider()
        ForEach(notifications) { notification in
          Button {
            onSelectNotification(notification)
          } label: {
            HStack(alignment: .top) {
              Image(systemName: "network")
                .foregroundStyle(notification.isRead ? Color.secondary : Color.orange)
                .accessibilityHidden(true)
              Text(notification.content)
                .foregroundStyle(notification.isRead ? Color.secondary : Color.primary)
                .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
          .buttonStyle(.plain)
          .font(.caption)
          .help(notification.content.isEmpty ? "Open endpoint" : notification.content)
        }
      }
      .padding()
    }
    .frame(minWidth: 260, maxWidth: 480, maxHeight: 400)
  }
}
