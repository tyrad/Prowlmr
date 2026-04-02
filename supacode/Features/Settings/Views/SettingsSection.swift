import Foundation

enum SettingsSection: Hashable {
  case general
  case notifications
  case worktree
  case updates
  case advanced
  case github
  case repository(Repository.ID)

  struct SidebarItem: Equatable {
    let section: SettingsSection
    let title: String
    let systemImage: String
  }

  static func sidebarItems(updatesEnabled: Bool) -> [SidebarItem] {
    var items: [SidebarItem] = [
      SidebarItem(section: .general, title: "General", systemImage: "gearshape"),
      SidebarItem(section: .notifications, title: "Notifications", systemImage: "bell"),
      SidebarItem(section: .worktree, title: "Worktree", systemImage: "archivebox"),
      SidebarItem(section: .updates, title: "Updates", systemImage: "arrow.down.circle"),
      SidebarItem(section: .advanced, title: "Advanced", systemImage: "gearshape.2"),
      SidebarItem(section: .github, title: "GitHub", systemImage: "arrow.triangle.branch"),
    ]
    if !updatesEnabled {
      items.removeAll { $0.section == .updates }
    }
    return items
  }

  static func resolvedSelection(_ selection: SettingsSection, updatesEnabled: Bool) -> SettingsSection {
    guard updatesEnabled || selection != .updates else {
      return .general
    }
    return selection
  }

  static func resolvedSelection(_ selection: SettingsSection?, updatesEnabled: Bool) -> SettingsSection {
    resolvedSelection(selection ?? .general, updatesEnabled: updatesEnabled)
  }
}
