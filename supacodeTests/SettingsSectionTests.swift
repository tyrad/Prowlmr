import Testing

@testable import supacode

struct SettingsSectionTests {
  @Test func sidebarItemsExcludeUpdatesWhenDisabled() {
    let items = SettingsSection.sidebarItems(updatesEnabled: false)
    #expect(items.map(\.section).contains(.updates) == false)
  }

  @Test func resolvedSelectionFallsBackToGeneralWhenUpdatesDisabled() {
    let selection = SettingsSection.resolvedSelection(.updates, updatesEnabled: false)
    #expect(selection == .general)
  }
}
