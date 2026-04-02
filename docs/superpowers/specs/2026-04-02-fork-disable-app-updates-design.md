# Fork Disable App Updates Design

## Background
This fork currently ships with Sparkle auto-update wiring enabled:
- `supacode/Info.plist` provides `SUFeedURL` and `SUPublicEDKey`.
- `UpdatesFeature` configures update behavior at launch from persisted settings.
- Manual update entry points exist in the app menu, Settings, and command palette.

For the current fork release policy, in-app updates should be disabled for all shipped builds without disturbing the rest of the app.

## Goals
- Disable in-app update behavior for all fork releases.
- Remove update-related UI so users are not presented with unavailable actions.
- Preserve the existing Sparkle integration code and release infrastructure for possible future re-enablement.
- Avoid any impact on unrelated app behavior.

## Non-Goals
- Removing the Sparkle package dependency.
- Deleting appcast or release script infrastructure.
- Changing notarization, signing, archive, or install flows.
- Migrating existing settings files to a new schema.

## Chosen Approach
Implement a fork-level update policy switch and treat it as the single source of truth for whether in-app updates are available.

The policy is driven by app configuration, not by user settings. For this fork, it is disabled in shipped builds. When disabled:
- launch-time update configuration becomes a no-op
- manual "check for updates" actions become no-ops or are removed from the UI
- update settings UI is hidden

This is a runtime shutdown of the update subsystem, not a codebase-wide removal.

## Configuration Model

### Single Source of Truth
Add a lightweight app update policy layer, for example `AppUpdatePolicy`, with:
- `isEnabled: Bool`

The value is read from app configuration such as `Info.plist` via a fork-specific key like:
- `ProwlUpdatesEnabled = NO`

No other part of the app should infer update availability from `GlobalSettings`.

### Why Configuration Instead of User Settings
User settings currently control Sparkle preferences such as update channel and automatic checks. Those settings are per-user preferences, not product capability flags.

If update support is disabled for the fork, user preferences must not override that product decision. Existing stored values remain readable for compatibility, but they no longer activate any update behavior.

## Runtime Behavior

### UpdatesFeature
`UpdatesFeature` remains in the reducer tree, but when the update policy is disabled:
- `.applySettings(...)` does not call `UpdaterClient`
- `.checkForUpdates` does not call `UpdaterClient`

This prevents both startup configuration and user-triggered checks from reaching Sparkle.

### UpdaterClient
`UpdaterClient.liveValue` should also honor the same policy and provide no-op behavior when updates are disabled.

This gives a second line of defense in case a future caller bypasses current reducer assumptions.

### Existing Settings Compatibility
`GlobalSettings` keeps its existing update-related fields:
- `updateChannel`
- `updatesAutomaticallyCheckForUpdates`
- `updatesAutomaticallyDownloadUpdates`

The default for automatic update checks should be changed to `false` for new settings files, but correctness does not depend on that default. Old settings with `true` values must remain harmless because the runtime policy blocks update activity.

No settings file migration is required.

## UI Behavior

### Remove User-Facing Update Entry Points
When the update policy is disabled, the app should not present update actions:
- remove "Check for Updates..." from the app menu
- remove "Check for Updates" from the command palette
- hide the Updates settings section content, or remove the section entirely if the surrounding settings structure allows it cleanly

The preferred behavior is removal rather than showing disabled controls, because the fork is intentionally not offering this capability.

### Settings Window
The rest of Settings remains unchanged. Hiding update-specific controls must not affect navigation or behavior of:
- General
- Notifications
- Worktree
- Advanced
- GitHub
- Repository settings

## Release and Documentation Impact
Do not remove existing Sparkle release infrastructure yet.

Update fork documentation to state that current fork releases have in-app updates disabled. Release artifacts may still be built using the existing release flow, but app-side upgrade discovery and installation are not offered to users.

This keeps future restoration cheap while making the current product behavior explicit.

## Testing Strategy

### Unit Tests
Add reducer tests covering:
- `UpdatesFeature` does not call `UpdaterClient.configure` when disabled
- `UpdatesFeature` does not call `UpdaterClient.checkForUpdates` when disabled
- legacy settings values with automatic checks enabled still result in no update activity

### UI/Behavior Tests
Add tests covering:
- command palette item list excludes the update action when disabled
- update menu command is not added when disabled
- updates settings UI is hidden or omitted when disabled

### Regression Boundary
Verification should confirm no behavior changes in unrelated features such as repository management, terminal handling, notifications, and GitHub integration.

## Risks
- A future code path may call Sparkle directly and bypass current reducers.
- UI hiding could leave behind an empty or awkward Settings navigation state if applied inconsistently.

## Mitigations
- Enforce the policy in both `UpdatesFeature` and `UpdaterClient`.
- Keep update capability checks centralized instead of scattering booleans across views.
- Add focused tests for both reducer behavior and user-visible entry points.

## Recovery Path
If the fork later wants to restore in-app updates:
1. Set the policy configuration back to enabled.
2. Restore update-related UI visibility.
3. Keep existing Sparkle and release infrastructure as-is.

No major reintegration work should be required.
