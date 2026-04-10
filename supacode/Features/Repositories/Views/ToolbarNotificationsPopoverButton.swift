import SwiftUI

struct ToolbarNotificationsPopoverButton: View {
  let groups: [ToolbarNotificationGroup]
  let unseenSourceCount: Int
  let onSelectNotification: (ToolbarNotificationItem) -> Void
  let onDismissAll: () -> Void
  @State private var isPresented = false
  @State private var isPinnedOpen = false
  @State private var isHoveringButton = false
  @State private var isHoveringPopover = false
  @State private var closeTask: Task<Void, Never>?

  private var notificationCount: Int {
    groups.reduce(0) { count, group in
      count
        + group.sources.reduce(0) { sourceCount, source in
          sourceCount + source.items.filter { !$0.isRead }.count
        }
    }
  }

  var body: some View {
    Button {
      togglePresentation()
    } label: {
      HStack(spacing: 6) {
        Image(systemName: unseenSourceCount > 0 ? "bell.badge.fill" : "bell.fill")
          .foregroundStyle(unseenSourceCount > 0 ? .orange : .secondary)
          .accessibilityHidden(true)
        if notificationCount > 0 {
          Text(notificationCount, format: .number)
            .font(.caption.monospacedDigit())
        }
      }
    }
    .help("Notifications. Hover or click to show all notifications.")
    .accessibilityLabel("Notifications")
    .onHover { hovering in
      isHoveringButton = hovering
      updatePresentation()
    }
    .popover(isPresented: $isPresented) {
      ToolbarNotificationsPopoverView(
        groups: groups,
        onSelectNotification: { item in
          onSelectNotification(item)
          closePopover()
        },
        onDismissAll: {
          onDismissAll()
          closePopover()
        }
      )
      .onHover { hovering in
        isHoveringPopover = hovering
        updatePresentation()
      }
      .onDisappear {
        isHoveringPopover = false
        isPinnedOpen = false
      }
    }
    .onChange(of: groups) { _, newValue in
      if newValue.isEmpty {
        closePopover()
      }
    }
    .onDisappear {
      closeTask?.cancel()
    }
  }

  private func togglePresentation() {
    if isPinnedOpen {
      closePopover()
      return
    }
    closeTask?.cancel()
    isPinnedOpen = true
    isPresented = true
  }

  private func updatePresentation() {
    if isPinnedOpen || isHoveringButton || isHoveringPopover {
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

  private func closePopover() {
    closeTask?.cancel()
    isPinnedOpen = false
    isPresented = false
  }
}
