import SwiftUI

struct ToolbarNotificationsPopoverView: View {
  let groups: [ToolbarNotificationGroup]
  let onSelectNotification: (ToolbarNotificationItem) -> Void
  let onDismissAll: () -> Void

  var body: some View {
    let notificationCount = groups.reduce(0) { count, group in
      count + group.notificationCount
    }
    let notificationLabel = notificationCount == 1 ? "notification" : "notifications"

    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text("Notifications")
              .font(.headline)
            Text("\(notificationCount) \(notificationLabel)")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Button("Dismiss All") {
            onDismissAll()
          }
          .disabled(notificationCount == 0)
          .help("Dismiss all notifications")
        }

        ForEach(groups) { group in
          VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text(group.name)
              .font(.subheadline)
            ForEach(group.sources) { source in
              VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                  Text(source.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                  if source.hasUnseenNotifications {
                    Circle()
                      .fill(.orange)
                      .frame(width: 6, height: 6)
                      .accessibilityHidden(true)
                  }
                }
                ForEach(source.items) { item in
                  Button {
                    onSelectNotification(item)
                  } label: {
                    HStack(alignment: .top, spacing: 8) {
                      Image(systemName: item.iconName)
                        .foregroundStyle(item.isRead ? Color.secondary : Color.orange)
                        .accessibilityHidden(true)
                      Text(item.content)
                        .font(.caption)
                        .foregroundStyle(item.isRead ? Color.secondary : Color.primary)
                        .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                  }
                  .buttonStyle(.plain)
                  .help(
                    item.content.isEmpty ? "Open notification target" : item.content
                  )
                }
              }
            }
          }
        }
      }
      .padding()
    }
    .frame(minWidth: 320, maxWidth: 520, maxHeight: 440)
  }
}
