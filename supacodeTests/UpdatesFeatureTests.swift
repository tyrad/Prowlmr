import ComposableArchitecture
import Testing

@testable import supacode

@MainActor
struct UpdatesFeatureTests {
  @Test func applySettingsDoesNothingWhenUpdatesDisabled() async {
    var configured = false
    var setChannel = false

    let store = TestStore(initialState: UpdatesFeature.State()) {
      UpdatesFeature()
    } withDependencies: {
      $0.appUpdatePolicy = AppUpdatePolicy(isEnabled: false)
      $0.updaterClient = UpdaterClient(
        configure: { _, _, _ in configured = true },
        setUpdateChannel: { _ in setChannel = true },
        checkForUpdates: {}
      )
    }

    await store.send(
      .applySettings(updateChannel: .stable, automaticallyChecks: true, automaticallyDownloads: false)
    ) {
      $0.didConfigureUpdates = true
    }

    #expect(configured == false)
    #expect(setChannel == false)
  }

  @Test func checkForUpdatesDoesNothingWhenUpdatesDisabled() async {
    var checked = false

    let store = TestStore(initialState: UpdatesFeature.State()) {
      UpdatesFeature()
    } withDependencies: {
      $0.appUpdatePolicy = AppUpdatePolicy(isEnabled: false)
      $0.updaterClient = UpdaterClient(
        configure: { _, _, _ in },
        setUpdateChannel: { _ in },
        checkForUpdates: { checked = true }
      )
    }

    await store.send(.checkForUpdates)
    #expect(checked == false)
  }
}
