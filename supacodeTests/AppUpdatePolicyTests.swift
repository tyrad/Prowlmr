import Testing

@testable import supacode

struct AppUpdatePolicyTests {
  @Test func defaultsToEnabledWhenFlagMissing() {
    let policy = AppUpdatePolicy(infoDictionary: [:])
    #expect(policy.isEnabled == true)
  }

  @Test func disablesUpdatesWhenFlagIsFalse() {
    let policy = AppUpdatePolicy(infoDictionary: [
      "ProwlUpdatesEnabled": false,
    ])
    #expect(policy.isEnabled == false)
  }

  @Test func ignoresNonBooleanValues() {
    let policy = AppUpdatePolicy(infoDictionary: [
      "ProwlUpdatesEnabled": "no",
    ])
    #expect(policy.isEnabled == true)
  }
}
