import ComposableArchitecture
import Foundation

struct AppUpdatePolicy: Equatable, Sendable {
  static let infoPlistKey = "ProwlUpdatesEnabled"

  var isEnabled: Bool

  init(isEnabled: Bool) {
    self.isEnabled = isEnabled
  }

  init(infoDictionary: [String: Any]) {
    self.isEnabled = infoDictionary[Self.infoPlistKey] as? Bool ?? true
  }

  static let current = AppUpdatePolicy(
    infoDictionary: Bundle.main.infoDictionary ?? [:]
  )
}

extension AppUpdatePolicy: DependencyKey {
  static let liveValue = AppUpdatePolicy.current
  static let testValue = AppUpdatePolicy(isEnabled: true)
}

extension DependencyValues {
  var appUpdatePolicy: AppUpdatePolicy {
    get { self[AppUpdatePolicy.self] }
    set { self[AppUpdatePolicy.self] = newValue }
  }
}
