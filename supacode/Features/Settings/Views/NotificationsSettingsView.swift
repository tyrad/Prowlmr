import ComposableArchitecture
import SwiftUI

struct NotificationsSettingsView: View {
  @Bindable var store: StoreOf<SettingsFeature>

  var body: some View {
    VStack(alignment: .leading) {
      Form {
        Section("Notifications") {
          Toggle(
            "Show bell icon next to worktree",
            isOn: $store.inAppNotificationsEnabled
          )
          .help("Show bell icon next to worktree")
          Toggle(
            "Play notification sound",
            isOn: $store.notificationSoundEnabled
          )
          .help("Play a sound when a notification is received")
          Toggle(
            "System notifications",
            isOn: $store.systemNotificationsEnabled
          )
          .help("Show macOS system notifications")
          Toggle(
            "Move notified worktree to top",
            isOn: $store.moveNotifiedWorktreeToTop
          )
          .help("Bring the worktree to the top when the terminal receives a notification")
        }
        Section("Command Finished") {
          Toggle(
            "Notify when long-running commands finish",
            isOn: $store.commandFinishedNotificationEnabled
          )
          .help("Show a notification when a command exceeds the duration threshold")
          if store.commandFinishedNotificationEnabled {
            Stepper(
              "Duration threshold: \(store.commandFinishedNotificationThreshold)s",
              value: $store.commandFinishedNotificationThreshold,
              in: 1...600,
              step: 5
            )
            .help("Minimum command duration in seconds before a notification is shown")
          }
        }
      }
      .formStyle(.grouped)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}
