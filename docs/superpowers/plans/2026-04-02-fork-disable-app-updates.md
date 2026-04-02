# Fork Disable App Updates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Disable in-app updates for fork releases without affecting unrelated app behavior, while preserving the existing Sparkle integration for future re-enablement.

**Architecture:** Introduce a single app-update policy object backed by `Info.plist`, use it to short-circuit runtime update behavior, and drive UI visibility from the same flag. Keep Sparkle and release infrastructure in place, but make the shipped app behave as if updates are not a supported capability.

**Tech Stack:** Swift 6.2, SwiftUI, The Composable Architecture, swift-dependencies, Swift Testing, Sparkle

---

## File Structure

### New Files
- `supacode/Features/Updates/Models/AppUpdatePolicy.swift`
  - Encapsulates `isEnabled` and reads `ProwlUpdatesEnabled` from an info dictionary.
  - Exposes the default live policy and a dependency value for reducers/tests.
- `supacodeTests/AppUpdatePolicyTests.swift`
  - Covers parsing rules for the new policy object.
- `supacodeTests/UpdatesFeatureTests.swift`
  - Covers reducer behavior when updates are enabled vs disabled.
- `supacodeTests/SettingsSectionTests.swift`
  - Covers update-section visibility and selection fallback logic.

### Modified Files
- `supacode/Info.plist`
  - Adds `ProwlUpdatesEnabled` with `false` for fork builds.
- `supacode/Clients/Updates/UpdaterClient.swift`
  - Returns no-op behavior when app updates are disabled.
- `supacode/Features/Updates/Reducer/UpdatesFeature.swift`
  - Reads the update policy dependency and short-circuits update actions.
- `supacode/Features/Settings/Models/GlobalSettings.swift`
  - Changes the default for automatic update checks to `false`.
- `supacode/Features/Settings/Views/SettingsSection.swift`
  - Adds helper APIs to describe visible sections when updates are disabled.
- `supacode/Features/Settings/Views/SettingsView.swift`
  - Uses policy-aware section helpers and falls back away from `.updates`.
- `supacode/Features/CommandPalette/Reducer/CommandPaletteFeature.swift`
  - Removes the global update action when app updates are disabled.
- `supacode/App/ContentView.swift`
  - Passes the update-policy flag into command-palette item generation.
- `supacode/Commands/UpdateCommands.swift`
  - Hides the app-menu update command when app updates are disabled.
- `supacode/App/supacodeApp.swift`
  - Passes the update-policy flag into `UpdateCommands`.
- `supacodeTests/CommandPaletteFeatureTests.swift`
  - Updates global item expectations and adds coverage for disabled updates.
- `supacodeTests/SettingsFilePersistenceTests.swift`
  - Confirms legacy settings still decode and do not rely on update capability.
- `doc-onevcat/fork-sync-and-release.md`
  - States that current fork releases disable in-app updates.

## Task 1: Add the App Update Policy

**Files:**
- Create: `supacode/Features/Updates/Models/AppUpdatePolicy.swift`
- Create: `supacodeTests/AppUpdatePolicyTests.swift`
- Modify: `supacode/Info.plist`

- [ ] **Step 1: Write the failing policy parsing tests**

```swift
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
```

- [ ] **Step 2: Run the policy tests to verify they fail**

Run:

```bash
xcodebuild test -project supacode.xcodeproj -scheme supacode -destination "platform=macOS" \
  -only-testing:supacodeTests/AppUpdatePolicyTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation
```

Expected:

```text
Testing failed:
  Cannot find 'AppUpdatePolicy' in scope
```

- [ ] **Step 3: Implement the policy model and dependency**

```swift
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
```

Update `supacode/Info.plist` near the existing Sparkle keys:

```xml
<key>ProwlUpdatesEnabled</key>
<false/>
```

- [ ] **Step 4: Re-run the policy tests to verify they pass**

Run:

```bash
xcodebuild test -project supacode.xcodeproj -scheme supacode -destination "platform=macOS" \
  -only-testing:supacodeTests/AppUpdatePolicyTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation
```

Expected:

```text
Test Suite 'Selected tests' passed
```

- [ ] **Step 5: Commit the policy scaffold**

```bash
git add supacode/Info.plist \
  supacode/Features/Updates/Models/AppUpdatePolicy.swift \
  supacodeTests/AppUpdatePolicyTests.swift
git commit -m "feat: add app update policy"
```

## Task 2: Gate Runtime Update Behavior

**Files:**
- Modify: `supacode/Clients/Updates/UpdaterClient.swift`
- Modify: `supacode/Features/Updates/Reducer/UpdatesFeature.swift`
- Modify: `supacode/Features/Settings/Models/GlobalSettings.swift`
- Create: `supacodeTests/UpdatesFeatureTests.swift`
- Modify: `supacodeTests/SettingsFilePersistenceTests.swift`

- [ ] **Step 1: Write the failing reducer tests**

```swift
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
```

Add one settings-default assertion to `SettingsFilePersistenceTests.swift`:

```swift
#expect(SettingsFile.default.global.updatesAutomaticallyCheckForUpdates == false)
```

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run:

```bash
xcodebuild test -project supacode.xcodeproj -scheme supacode -destination "platform=macOS" \
  -only-testing:supacodeTests/UpdatesFeatureTests \
  -only-testing:supacodeTests/SettingsFilePersistenceTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation
```

Expected:

```text
Testing failed:
  UpdatesFeature still invoked UpdaterClient while policy was disabled
  Settings default still enables automatic update checks
```

- [ ] **Step 3: Implement runtime gating and safer defaults**

Update `supacode/Features/Updates/Reducer/UpdatesFeature.swift`:

```swift
@Dependency(\.appUpdatePolicy) private var appUpdatePolicy

case .applySettings(let channel, let checks, let downloads):
  let checkInBackground = !state.didConfigureUpdates
  state.didConfigureUpdates = true
  guard appUpdatePolicy.isEnabled else { return .none }
  return .run { _ in
    await updaterClient.setUpdateChannel(channel)
    await updaterClient.configure(checks, downloads, checkInBackground)
  }

case .checkForUpdates:
  guard appUpdatePolicy.isEnabled else { return .none }
  analyticsClient.capture("update_checked", nil)
  return .run { _ in
    await updaterClient.checkForUpdates()
  }
```

Update `supacode/Clients/Updates/UpdaterClient.swift`:

```swift
extension UpdaterClient: DependencyKey {
  static let liveValue: UpdaterClient = {
    guard AppUpdatePolicy.current.isEnabled else {
      return UpdaterClient(
        configure: { _, _, _ in },
        setUpdateChannel: { _ in },
        checkForUpdates: {}
      )
    }

    let delegate = SparkleUpdateDelegate()
    let controller = SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: delegate,
      userDriverDelegate: nil
    )
    let updater = controller.updater
    return UpdaterClient(
      configure: { checks, downloads, checkInBackground in
        _ = controller
        updater.automaticallyChecksForUpdates = checks
        updater.automaticallyDownloadsUpdates = downloads
        if checkInBackground, checks {
          updater.checkForUpdatesInBackground()
        }
      },
      setUpdateChannel: { channel in
        _ = controller
        delegate.updateChannel = channel
        updater.updateCheckInterval = 3600
        if updater.automaticallyChecksForUpdates {
          updater.checkForUpdatesInBackground()
        }
      },
      checkForUpdates: {
        _ = controller
        updater.checkForUpdates()
      }
    )
  }()
}
```

Update `supacode/Features/Settings/Models/GlobalSettings.swift`:

```swift
static let `default` = GlobalSettings(
  appearanceMode: .dark,
  defaultEditorID: OpenWorktreeAction.automaticSettingsID,
  confirmBeforeQuit: true,
  updateChannel: .stable,
  updatesAutomaticallyCheckForUpdates: false,
  updatesAutomaticallyDownloadUpdates: false,
  ...
)
```

- [ ] **Step 4: Re-run the targeted tests to verify they pass**

Run:

```bash
xcodebuild test -project supacode.xcodeproj -scheme supacode -destination "platform=macOS" \
  -only-testing:supacodeTests/UpdatesFeatureTests \
  -only-testing:supacodeTests/SettingsFilePersistenceTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation
```

Expected:

```text
Test Suite 'Selected tests' passed
```

- [ ] **Step 5: Commit the runtime gating**

```bash
git add supacode/Clients/Updates/UpdaterClient.swift \
  supacode/Features/Updates/Reducer/UpdatesFeature.swift \
  supacode/Features/Settings/Models/GlobalSettings.swift \
  supacodeTests/UpdatesFeatureTests.swift \
  supacodeTests/SettingsFilePersistenceTests.swift
git commit -m "feat: disable runtime app updates"
```

## Task 3: Remove Update UI Entry Points

**Files:**
- Modify: `supacode/Features/Settings/Views/SettingsSection.swift`
- Modify: `supacode/Features/Settings/Views/SettingsView.swift`
- Modify: `supacode/Features/CommandPalette/Reducer/CommandPaletteFeature.swift`
- Modify: `supacode/App/ContentView.swift`
- Modify: `supacode/Commands/UpdateCommands.swift`
- Modify: `supacode/App/supacodeApp.swift`
- Modify: `supacodeTests/CommandPaletteFeatureTests.swift`
- Create: `supacodeTests/SettingsSectionTests.swift`

- [ ] **Step 1: Write the failing visibility tests**

Create `supacodeTests/SettingsSectionTests.swift`:

```swift
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
```

Append to `supacodeTests/CommandPaletteFeatureTests.swift`:

```swift
  @Test func commandPaletteItems_omitsCheckForUpdatesWhenDisabled() {
    let items = CommandPaletteFeature.commandPaletteItems(
      from: RepositoriesFeature.State(),
      isUpdatesEnabled: false
    )

    #expect(items.contains(where: { $0.id == "global.check-for-updates" }) == false)
  }
```

- [ ] **Step 2: Run the visibility tests to verify they fail**

Run:

```bash
xcodebuild test -project supacode.xcodeproj -scheme supacode -destination "platform=macOS" \
  -only-testing:supacodeTests/SettingsSectionTests \
  -only-testing:supacodeTests/CommandPaletteFeatureTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation
```

Expected:

```text
Testing failed:
  Type 'SettingsSection' has no member 'sidebarItems'
  Extra argument 'isUpdatesEnabled' in call
```

- [ ] **Step 3: Implement policy-aware UI helpers and entry-point removal**

Update `supacode/Features/Settings/Views/SettingsSection.swift`:

```swift
import Foundation

struct SettingsSidebarItem: Equatable, Identifiable {
  let section: SettingsSection
  let title: String
  let systemImage: String

  var id: SettingsSection { section }
}

enum SettingsSection: Hashable {
  case general
  case notifications
  case worktree
  case updates
  case advanced
  case github
  case repository(Repository.ID)

  static func sidebarItems(updatesEnabled: Bool) -> [SettingsSidebarItem] {
    var items: [SettingsSidebarItem] = [
      .init(section: .general, title: "General", systemImage: "gearshape"),
      .init(section: .notifications, title: "Notifications", systemImage: "bell"),
      .init(section: .worktree, title: "Worktree", systemImage: "archivebox"),
      .init(section: .advanced, title: "Advanced", systemImage: "gearshape.2"),
      .init(section: .github, title: "GitHub", systemImage: "arrow.triangle.branch"),
    ]
    if updatesEnabled {
      items.insert(
        .init(section: .updates, title: "Updates", systemImage: "arrow.down.circle"),
        at: 3
      )
    }
    return items
  }

  static func resolvedSelection(_ selection: SettingsSection?, updatesEnabled: Bool) -> SettingsSection {
    switch selection ?? .general {
    case .updates where !updatesEnabled:
      .general
    case let selection:
      selection
    }
  }
}
```

Update `supacode/Features/Settings/Views/SettingsView.swift`:

```swift
  private let updatesEnabled = AppUpdatePolicy.current.isEnabled

  var body: some View {
    let updatesStore = store.scope(state: \.updates, action: \.updates)
    let repositories = store.repositories.repositories
    let selection = SettingsSection.resolvedSelection(
      settingsStore.selection,
      updatesEnabled: updatesEnabled
    )

    NavigationSplitView(columnVisibility: .constant(.all)) {
      VStack(spacing: 0) {
        List(selection: $settingsStore.selection.sending(\.setSelection)) {
          ForEach(SettingsSection.sidebarItems(updatesEnabled: updatesEnabled)) { item in
            Label(item.title, systemImage: item.systemImage)
              .tag(item.section)
          }
          Section("Repositories") {
            ...
          }
        }
      }
    } detail: {
      switch selection {
      ...
      case .updates:
        if updatesEnabled {
          SettingsDetailView {
            UpdatesSettingsView(settingsStore: settingsStore, updatesStore: updatesStore)
              .navigationTitle("Updates")
              .navigationSubtitle("Update preferences")
          }
        }
      ...
      }
    }
  }
```

Update `supacode/Features/CommandPalette/Reducer/CommandPaletteFeature.swift` and `supacode/App/ContentView.swift`:

```swift
static func commandPaletteItems(
  from repositories: RepositoriesFeature.State,
  ghosttyCommands: [GhosttyCommand] = [],
  isUpdatesEnabled: Bool = true
) -> [CommandPaletteItem] {
  var items: [CommandPaletteItem] = []
  if isUpdatesEnabled {
    items.append(
      CommandPaletteItem(
        id: CommandPaletteItemID.globalCheckForUpdates,
        title: "Check for Updates",
        subtitle: nil,
        kind: .checkForUpdates
      )
    )
  }
  items.append(
    contentsOf: [
      CommandPaletteItem(
        id: CommandPaletteItemID.globalOpenSettings,
        title: "Open Settings",
        subtitle: nil,
        kind: .openSettings
      ),
      ...
    ]
  )
  ...
}
```

```swift
        items: CommandPaletteFeature.commandPaletteItems(
          from: store.repositories,
          ghosttyCommands: ghosttyShortcuts.commandPaletteEntries,
          isUpdatesEnabled: AppUpdatePolicy.current.isEnabled
        )
```

Update `supacode/Commands/UpdateCommands.swift` and `supacode/App/supacodeApp.swift`:

```swift
struct UpdateCommands: Commands {
  let store: StoreOf<UpdatesFeature>
  let isEnabled: Bool

  var body: some Commands {
    if isEnabled {
      CommandGroup(after: .appInfo) {
        Button("Check for Updates...") {
          store.send(.checkForUpdates)
        }
        .keyboardShortcut(
          AppShortcuts.checkForUpdates.keyEquivalent,
          modifiers: AppShortcuts.checkForUpdates.modifiers
        )
        .help("Check for Updates (\(AppShortcuts.checkForUpdates.display))")
      }
    }
  }
}
```

```swift
      UpdateCommands(
        store: store.scope(state: \.updates, action: \.updates),
        isEnabled: AppUpdatePolicy.current.isEnabled
      )
```

- [ ] **Step 4: Re-run the visibility tests to verify they pass**

Run:

```bash
xcodebuild test -project supacode.xcodeproj -scheme supacode -destination "platform=macOS" \
  -only-testing:supacodeTests/SettingsSectionTests \
  -only-testing:supacodeTests/CommandPaletteFeatureTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation
```

Expected:

```text
Test Suite 'Selected tests' passed
```

- [ ] **Step 5: Commit the UI changes**

```bash
git add supacode/Features/Settings/Views/SettingsSection.swift \
  supacode/Features/Settings/Views/SettingsView.swift \
  supacode/Features/CommandPalette/Reducer/CommandPaletteFeature.swift \
  supacode/App/ContentView.swift \
  supacode/Commands/UpdateCommands.swift \
  supacode/App/supacodeApp.swift \
  supacodeTests/CommandPaletteFeatureTests.swift \
  supacodeTests/SettingsSectionTests.swift
git commit -m "feat: hide update UI when disabled"
```

## Task 4: Update Fork Docs and Verify the App Build

**Files:**
- Modify: `doc-onevcat/fork-sync-and-release.md`

- [ ] **Step 1: Add the fork-release note to the release guide**

Insert a note in `doc-onevcat/fork-sync-and-release.md` near the Sparkle section:

```md
### Current Fork Policy

Fork release artifacts are still produced by the existing release pipeline, but shipped builds currently disable in-app update discovery and installation. Users must install new releases manually until `ProwlUpdatesEnabled` is re-enabled.
```

- [ ] **Step 2: Run the focused test sweep**

Run:

```bash
xcodebuild test -project supacode.xcodeproj -scheme supacode -destination "platform=macOS" \
  -only-testing:supacodeTests/AppUpdatePolicyTests \
  -only-testing:supacodeTests/UpdatesFeatureTests \
  -only-testing:supacodeTests/SettingsSectionTests \
  -only-testing:supacodeTests/CommandPaletteFeatureTests \
  -only-testing:supacodeTests/SettingsFeatureTests \
  -only-testing:supacodeTests/SettingsFilePersistenceTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation
```

Expected:

```text
Test Suite 'Selected tests' passed
```

- [ ] **Step 3: Run the required app build verification**

Run:

```bash
make build-app
```

Expected:

```text
xcodebuild ... BUILD SUCCEEDED
```

- [ ] **Step 4: Commit the docs and verification-ready state**

```bash
git add doc-onevcat/fork-sync-and-release.md
git commit -m "docs: note fork update policy"
```

## Self-Review

### Spec Coverage
- Single-source update flag: Task 1
- Runtime gating in reducer/client: Task 2
- Hidden update UI and no manual entry points: Task 3
- Default compatibility and docs: Tasks 2 and 4
- Verification that unrelated behavior still builds: Task 4

### Placeholder Scan
- No `TODO`, `TBD`, or deferred implementation markers remain.
- Each task includes exact file paths, commands, and concrete code targets.

### Type Consistency
- `AppUpdatePolicy` is the only policy type introduced.
- `SettingsSection.sidebarItems(updatesEnabled:)` and `resolvedSelection(_:updatesEnabled:)` are the only new section helpers referenced later.
- `CommandPaletteFeature.commandPaletteItems(..., isUpdatesEnabled:)` is the only new command-palette API expansion used by the plan.
