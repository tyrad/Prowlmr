import ComposableArchitecture
import SwiftUI

extension View {
  @ViewBuilder
  fileprivate func removingSidebarToggle() -> some View {
    if #available(macOS 14.0, *) {
      toolbar(removing: .sidebarToggle)
    } else {
      self
    }
  }
}

struct SettingsView: View {
  @Bindable var store: StoreOf<AppFeature>
  @Bindable var settingsStore: StoreOf<SettingsFeature>

  init(store: StoreOf<AppFeature>) {
    self.store = store
    settingsStore = store.scope(state: \.settings, action: \.settings)
  }

  var body: some View {
    let updatesStore = store.scope(state: \.updates, action: \.updates)
    let repositories = store.repositories.repositories
    let isUpdatesEnabled = AppUpdatePolicy.current.isEnabled
    let selection = SettingsSection.resolvedSelection(settingsStore.selection, updatesEnabled: isUpdatesEnabled)
    let sidebarSelection = Binding<SettingsSection?>(
      get: {
        SettingsSection.resolvedSelection(settingsStore.selection, updatesEnabled: isUpdatesEnabled)
      },
      set: { newValue in
        settingsStore.send(.setSelection(newValue))
      }
    )

    NavigationSplitView(columnVisibility: .constant(.all)) {
      VStack(spacing: 0) {
        List(selection: sidebarSelection) {
          ForEach(SettingsSection.sidebarItems(updatesEnabled: isUpdatesEnabled), id: \.section) { item in
            Label(item.title, systemImage: item.systemImage)
              .tag(item.section)
          }

          Section("Repositories") {
            ForEach(repositories) { repository in
              Text(repository.name)
                .tag(SettingsSection.repository(repository.id))
            }
          }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 220, maxHeight: .infinity)
        .navigationSplitViewColumnWidth(220)
        .removingSidebarToggle()
      }
    } detail: {
      switch selection {
      case .general:
        SettingsDetailView {
          AppearanceSettingsView(store: settingsStore)
            .navigationTitle("General")
            .navigationSubtitle("Appearance and preferences")
        }
      case .notifications:
        SettingsDetailView {
          NotificationsSettingsView(store: settingsStore)
            .navigationTitle("Notifications")
            .navigationSubtitle("In-app alerts and delivery")
        }
      case .worktree:
        SettingsDetailView {
          WorktreeSettingsView(store: settingsStore)
            .navigationTitle("Worktree")
            .navigationSubtitle("Archive behavior")
        }
      case .updates:
        SettingsDetailView {
          UpdatesSettingsView(settingsStore: settingsStore, updatesStore: updatesStore)
            .navigationTitle("Updates")
            .navigationSubtitle("Update preferences")
        }
      case .advanced:
        SettingsDetailView {
          AdvancedSettingsView(store: settingsStore)
            .navigationTitle("Advanced")
            .navigationSubtitle("Analytics and diagnostics")
        }
      case .github:
        SettingsDetailView {
          GithubSettingsView(store: settingsStore)
            .navigationTitle("GitHub")
            .navigationSubtitle("GitHub CLI integration")
        }
      case .repository(let repositoryID):
        if let repository = repositories[id: repositoryID] {
          SettingsDetailView {
            IfLetStore(
              settingsStore.scope(state: \.repositorySettings, action: \.repositorySettings)
            ) { repositorySettingsStore in
              RepositorySettingsView(store: repositorySettingsStore)
                .id(repository.id)
                .navigationTitle(repository.name)
                .navigationSubtitle(repository.rootURL.path(percentEncoded: false))
            }
          }
        } else {
          SettingsDetailView {
            Text("Repository not found.")
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
              .navigationTitle("Repositories")
          }
        }
      }
    }
    .navigationSplitViewStyle(.balanced)
    .alert(store: settingsStore.scope(state: \.$alert, action: \.alert))
    .alert(store: store.scope(state: \.$alert, action: \.alert))
    .frame(minWidth: 750, minHeight: 500)
    .background {
      WindowAppearanceSetter(colorScheme: settingsStore.appearanceMode.colorScheme)
      WindowLevelSetter(level: .normal)
    }
    .ignoresSafeArea(.container, edges: .top)
  }
}
