# Remote Mini-Terminal Group WebView Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new app-level Remote Groups flow that discovers `mini-terminal` groups from remote endpoints and opens selected groups in a `WKWebView` detail pane.

**Architecture:** Introduce `RemoteGroupsFeature` in `AppFeature` to own endpoint/group discovery and selection. Keep existing `RepositoriesFeature` + Ghostty local terminal flow unchanged. Extend sidebar composition to render a new `Remote Groups` section parallel to repositories, and branch right-pane rendering to either local terminal content or remote WebView content.

**Tech Stack:** SwiftUI, Composable Architecture, Sharing (`@Shared`), URLSession, WebKit, Swift Testing (`Testing`, `TestStore`).

---

## File Structure

### Create
- `supacode/Features/RemoteGroups/BusinessLogic/RemoteGroupParsing.swift`
- `supacode/Features/RemoteGroups/Models/RemoteEndpoint.swift`
- `supacode/Features/RemoteGroups/Models/RemoteGroupRef.swift`
- `supacode/Features/RemoteGroups/Models/RemoteSelection.swift`
- `supacode/Clients/RemoteTerminal/RemoteTerminalClient.swift`
- `supacode/Features/RemoteGroups/Reducer/RemoteGroupsFeature.swift`
- `supacode/Features/RemoteGroups/Views/RemoteGroupsSectionView.swift`
- `supacode/Features/RemoteGroups/Views/RemoteGroupAddPromptView.swift`
- `supacode/Features/RemoteGroups/Views/RemoteGroupDetailView.swift`
- `supacodeTests/RemoteGroupParsingTests.swift`
- `supacodeTests/RemoteTerminalClientTests.swift`
- `supacodeTests/RemoteGroupsFeatureTests.swift`
- `supacodeTests/AppFeatureRemoteGroupsIntegrationTests.swift`

### Modify
- `supacode/Features/App/Reducer/AppFeature.swift`
- `supacode/App/ContentView.swift`
- `supacode/Features/Repositories/Views/SidebarView.swift`
- `supacode/Features/Repositories/Views/SidebarListView.swift`
- `supacode/Features/Repositories/Views/SidebarFooterView.swift`
- `supacode/Features/Repositories/Views/SidebarSelection.swift`
- `supacode/Features/Repositories/Views/WorktreeDetailView.swift`

### Ownership
- Parsing and API concerns stay isolated in RemoteGroups + RemoteTerminal client files.
- Existing repository/worktree terminal behavior is not refactored; only selection and detail branching are extended.

---

### Task 1: Implement mini-terminal-compatible group parsing

**Files:**
- Create: `supacode/Features/RemoteGroups/BusinessLogic/RemoteGroupParsing.swift`
- Test: `supacodeTests/RemoteGroupParsingTests.swift`

- [ ] **Step 1: Write failing parser test**

```swift
import Testing
@testable import supacode

struct RemoteGroupParsingTests {
  @Test func parseGroup_uses_reuse_key_only() {
    #expect(RemoteGroupParsing.parseGroup(from: "multi-tmux:alpha:1") == "alpha")
    #expect(RemoteGroupParsing.parseGroup(from: "multi-tmux:Alpha Team:1") == "alpha-team")
    #expect(RemoteGroupParsing.parseGroup(from: "other:alpha:1") == nil)
    #expect(RemoteGroupParsing.parseGroup(from: "multi-tmux::1") == nil)
  }
}
```

- [ ] **Step 2: Run the test and confirm failure**

Run:
```bash
xcodebuild test -project supacode.xcodeproj -scheme supacode -destination "platform=macOS" \
  -only-testing:supacodeTests/RemoteGroupParsingTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation
```
Expected: FAIL because `RemoteGroupParsing` does not exist.

- [ ] **Step 3: Add parser implementation**

```swift
import Foundation

nonisolated enum RemoteGroupParsing {
  static let scope = "multi-tmux"
  private static let prefix = "multi-tmux:"

  static func parseGroup(from reuseKey: String) -> String? {
    let text = reuseKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard text.hasPrefix(prefix) else { return nil }
    let suffix = String(text.dropFirst(prefix.count))
    let firstSegment = String(
      suffix.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
    )
    let slug = slugify(firstSegment)
    return slug.isEmpty ? nil : slug
  }

  static func slugify(_ text: String) -> String {
    let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let filtered = lower.map { ch -> Character in
      if ch.isLetter || ch.isNumber { return ch }
      return "-"
    }
    let joined = String(filtered)
    return joined
      .split(separator: "-", omittingEmptySubsequences: true)
      .joined(separator: "-")
  }
}
```

- [ ] **Step 4: Re-run test and confirm pass**

Run same command as Step 2.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add supacode/Features/RemoteGroups/BusinessLogic/RemoteGroupParsing.swift supacodeTests/RemoteGroupParsingTests.swift
git commit -m "feat(remote-groups): add mini-terminal group parsing"
```

---

### Task 2: Add remote sessions API client

**Files:**
- Create: `supacode/Clients/RemoteTerminal/RemoteTerminalClient.swift`
- Test: `supacodeTests/RemoteTerminalClientTests.swift`

- [ ] **Step 1: Write failing client tests**

```swift
import Testing
import Foundation
@testable import supacode

struct RemoteTerminalClientTests {
  @Test func listSessions_appends_scope_query() async throws {
    let base = URL(string: "https://example.com/mini-terminal/")!
    let url = RemoteTerminalClient.sessionsURL(for: base)
    #expect(url.absoluteString == "https://example.com/mini-terminal/api/v1/terminal/sessions?scope=multi-tmux")
  }
}
```

- [ ] **Step 2: Run test and confirm failure**

Run:
```bash
xcodebuild test -project supacode.xcodeproj -scheme supacode -destination "platform=macOS" \
  -only-testing:supacodeTests/RemoteTerminalClientTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation
```
Expected: FAIL due to missing client.

- [ ] **Step 3: Implement client**

```swift
import ComposableArchitecture
import Foundation

struct RemoteTerminalSession: Equatable, Sendable, Decodable {
  var id: String
  var scope: String
  var reuseKey: String
  var cwd: String
  var updatedAt: String
}

struct RemoteTerminalClient {
  var listSessions: @Sendable (URL) async throws -> [RemoteTerminalSession]

  static func sessionsURL(for baseURL: URL) -> URL {
    let normalized = baseURL.absoluteString.hasSuffix("/") ? baseURL : baseURL.appending(path: "")
    return normalized
      .appending(path: "api/v1/terminal/sessions")
      .appending(queryItems: [URLQueryItem(name: "scope", value: RemoteGroupParsing.scope)])
  }
}

extension RemoteTerminalClient: DependencyKey {
  static let liveValue = RemoteTerminalClient(
    listSessions: { baseURL in
      let requestURL = sessionsURL(for: baseURL)
      var request = URLRequest(url: requestURL)
      request.setValue("application/json", forHTTPHeaderField: "Accept")
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
        throw URLError(.badServerResponse)
      }
      struct Payload: Decodable {
        var sessions: [RemoteTerminalSession]?
      }
      return try JSONDecoder().decode(Payload.self, from: data).sessions ?? []
    }
  )

  static let testValue = RemoteTerminalClient(listSessions: { _ in [] })
}

extension DependencyValues {
  var remoteTerminalClient: RemoteTerminalClient {
    get { self[RemoteTerminalClient.self] }
    set { self[RemoteTerminalClient.self] = newValue }
  }
}
```

- [ ] **Step 4: Re-run tests and confirm pass**

Run same command as Step 2.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add supacode/Clients/RemoteTerminal/RemoteTerminalClient.swift supacodeTests/RemoteTerminalClientTests.swift
git commit -m "feat(remote-groups): add remote terminal sessions client"
```

---

### Task 3: Implement `RemoteGroupsFeature` reducer and persisted state

**Files:**
- Create: `supacode/Features/RemoteGroups/Models/RemoteEndpoint.swift`
- Create: `supacode/Features/RemoteGroups/Models/RemoteGroupRef.swift`
- Create: `supacode/Features/RemoteGroups/Models/RemoteSelection.swift`
- Create: `supacode/Features/RemoteGroups/Reducer/RemoteGroupsFeature.swift`
- Test: `supacodeTests/RemoteGroupsFeatureTests.swift`

- [ ] **Step 1: Write failing reducer tests**

```swift
import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import Testing
@testable import supacode

@MainActor
struct RemoteGroupsFeatureTests {
  @Test(.dependencies) func submit_endpoint_fetches_and_groups() async {
    let store = TestStore(initialState: RemoteGroupsFeature.State()) {
      RemoteGroupsFeature()
    } withDependencies: {
      $0.remoteTerminalClient.listSessions = { _ in
        [
          .init(id: "1", scope: "multi-tmux", reuseKey: "multi-tmux:alpha:1", cwd: "~", updatedAt: ""),
          .init(id: "2", scope: "multi-tmux", reuseKey: "multi-tmux:alpha:2", cwd: "~", updatedAt: ""),
        ]
      }
    }

    await store.send(.submitEndpoint(urlText: "https://example.com/mini-terminal/", initialGroup: ""))
    await store.receive(/RemoteGroupsFeature.Action.endpointSessionsResponse)
  }
}
```

- [ ] **Step 2: Run tests and confirm failure**

Run:
```bash
xcodebuild test -project supacode.xcodeproj -scheme supacode -destination "platform=macOS" \
  -only-testing:supacodeTests/RemoteGroupsFeatureTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation
```
Expected: FAIL.

- [ ] **Step 3: Implement feature and aggregation**

```swift
import ComposableArchitecture
import Foundation
import Sharing

struct RemoteEndpoint: Equatable, Codable, Identifiable, Sendable {
  var id: UUID
  var baseURL: URL

  init(id: UUID = UUID(), baseURL: URL) {
    self.id = id
    self.baseURL = baseURL
  }

  var overviewURL: URL { baseURL }

  func groupURL(group: String) -> URL {
    baseURL.appending(queryItems: [URLQueryItem(name: "group", value: group)])
  }
}

enum RemoteSelection: Equatable, Codable, Sendable {
  case none
  case overview(endpointID: UUID)
  case group(endpointID: UUID, group: String)
}

struct RemoteGroupRef: Equatable, Identifiable, Sendable {
  var id: String { group }
  var group: String
  var sessionCount: Int

  static func aggregate(sessions: [RemoteTerminalSession]) -> [RemoteGroupRef] {
    var counts: [String: Int] = [:]
    for session in sessions {
      guard let group = RemoteGroupParsing.parseGroup(from: session.reuseKey) else { continue }
      counts[group, default: 0] += 1
    }
    return counts.keys.sorted().map { RemoteGroupRef(group: $0, sessionCount: counts[$0] ?? 0) }
  }
}

@Reducer
struct RemoteGroupsFeature {
  @ObservableState
  struct State: Equatable {
    @Shared(.appStorage("remoteGroups.endpoints")) var endpoints: [RemoteEndpoint] = []
    @Shared(.appStorage("remoteGroups.selection")) var selection: RemoteSelection = .none
    var groupsByEndpointID: [UUID: [RemoteGroupRef]] = [:]
    var isAddPromptPresented = false
    var addURLDraft = ""
    var addGroupDraft = ""
    var loadingEndpointIDs: Set<UUID> = []
    var errorByEndpointID: [UUID: String] = [:]
  }

  enum Action: Equatable {
    case setAddPromptPresented(Bool)
    case addURLDraftChanged(String)
    case addGroupDraftChanged(String)
    case submitEndpoint(urlText: String, initialGroup: String)
    case fetchEndpointSessions(UUID)
    case endpointSessionsResponse(endpointID: UUID, result: Result<[RemoteTerminalSession], String>)
    case selectOverview(UUID)
    case selectGroup(endpointID: UUID, group: String)
  }

  @Dependency(\.remoteTerminalClient) var remoteTerminalClient

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .setAddPromptPresented(let presented):
        state.isAddPromptPresented = presented
        return .none
      case .addURLDraftChanged(let value):
        state.addURLDraft = value
        return .none
      case .addGroupDraftChanged(let value):
        state.addGroupDraft = value
        return .none
      case .submitEndpoint(let urlText, let initialGroup):
        guard let url = URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)),
          url.scheme != nil,
          url.host != nil
        else { return .none }
        let endpoint = RemoteEndpoint(baseURL: url)
        state.$endpoints.withLock { $0.append(endpoint) }
        state.isAddPromptPresented = false
        if initialGroup.isEmpty {
          state.$selection.withLock { $0 = .overview(endpointID: endpoint.id) }
        } else {
          state.$selection.withLock {
            $0 = .group(endpointID: endpoint.id, group: RemoteGroupParsing.slugify(initialGroup))
          }
        }
        return .send(.fetchEndpointSessions(endpoint.id))
      case .fetchEndpointSessions(let endpointID):
        guard let endpoint = state.endpoints.first(where: { $0.id == endpointID }) else { return .none }
        state.loadingEndpointIDs.insert(endpointID)
        return .run { send in
          do {
            let sessions = try await remoteTerminalClient.listSessions(endpoint.baseURL)
            await send(.endpointSessionsResponse(endpointID: endpointID, result: .success(sessions)))
          } catch {
            await send(.endpointSessionsResponse(endpointID: endpointID, result: .failure(error.localizedDescription)))
          }
        }
      case .endpointSessionsResponse(let endpointID, let result):
        state.loadingEndpointIDs.remove(endpointID)
        switch result {
        case .success(let sessions):
          state.groupsByEndpointID[endpointID] = RemoteGroupRef.aggregate(sessions: sessions)
          state.errorByEndpointID[endpointID] = nil
        case .failure(let message):
          state.groupsByEndpointID[endpointID] = []
          state.errorByEndpointID[endpointID] = message
        }
        return .none
      case .selectOverview(let endpointID):
        state.$selection.withLock { $0 = .overview(endpointID: endpointID) }
        return .none
      case .selectGroup(let endpointID, let group):
        state.$selection.withLock { $0 = .group(endpointID: endpointID, group: group) }
        return .none
      }
    }
  }
}
```

- [ ] **Step 4: Re-run reducer tests and confirm pass**

Run same command as Step 2.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add supacode/Features/RemoteGroups/Models/RemoteEndpoint.swift supacode/Features/RemoteGroups/Models/RemoteGroupRef.swift supacode/Features/RemoteGroups/Models/RemoteSelection.swift supacode/Features/RemoteGroups/Reducer/RemoteGroupsFeature.swift supacodeTests/RemoteGroupsFeatureTests.swift
git commit -m "feat(remote-groups): add remote groups reducer and persisted state"
```

---

### Task 4: Scope remote groups in `AppFeature`

**Files:**
- Modify: `supacode/Features/App/Reducer/AppFeature.swift`
- Test: `supacodeTests/AppFeatureRemoteGroupsIntegrationTests.swift`

- [ ] **Step 1: Write failing integration test**

```swift
import ComposableArchitecture
import Testing
@testable import supacode

@MainActor
struct AppFeatureRemoteGroupsIntegrationTests {
  @Test func app_routes_remote_groups_actions() async {
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    }

    await store.send(.remoteGroups(.setAddPromptPresented(true))) {
      $0.remoteGroups.isAddPromptPresented = true
    }
  }
}
```

- [ ] **Step 2: Run test and confirm failure**

Run:
```bash
xcodebuild test -project supacode.xcodeproj -scheme supacode -destination "platform=macOS" \
  -only-testing:supacodeTests/AppFeatureRemoteGroupsIntegrationTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation
```
Expected: FAIL.

- [ ] **Step 3: Add app state/action/scope**

```swift
@ObservableState
struct State: Equatable {
  var repositories: RepositoriesFeature.State
  var remoteGroups = RemoteGroupsFeature.State()
  var settings: SettingsFeature.State
  // existing fields
}

enum Action {
  case appLaunched
  case repositories(RepositoriesFeature.Action)
  case remoteGroups(RemoteGroupsFeature.Action)
  case settings(SettingsFeature.Action)
  // existing actions
}

var body: some Reducer<State, Action> {
  Reduce<State, Action> { state, action in
    switch action {
    // existing logic
    default:
      return .none
    }
  }
  Scope(state: \.repositories, action: \.repositories) { RepositoriesFeature() }
  Scope(state: \.remoteGroups, action: \.remoteGroups) { RemoteGroupsFeature() }
  Scope(state: \.settings, action: \.settings) { SettingsFeature() }
  // existing scopes
}
```

- [ ] **Step 4: Re-run test and confirm pass**

Run same command as Step 2.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add supacode/Features/App/Reducer/AppFeature.swift supacodeTests/AppFeatureRemoteGroupsIntegrationTests.swift
git commit -m "feat(remote-groups): integrate remote groups into app feature"
```

---

### Task 5: Sidebar UI integration + icon-only add entry

**Files:**
- Create: `supacode/Features/RemoteGroups/Views/RemoteGroupsSectionView.swift`
- Modify: `supacode/App/ContentView.swift`
- Modify: `supacode/Features/Repositories/Views/SidebarView.swift`
- Modify: `supacode/Features/Repositories/Views/SidebarListView.swift`
- Modify: `supacode/Features/Repositories/Views/SidebarFooterView.swift`
- Modify: `supacode/Features/Repositories/Views/SidebarSelection.swift`

- [ ] **Step 1: Add remote cases to `SidebarSelection`**

```swift
enum SidebarSelection: Hashable {
  case worktree(Worktree.ID)
  case archivedWorktrees
  case repository(Repository.ID)
  case canvas
  case remoteOverview(endpointID: UUID)
  case remoteGroup(endpointID: UUID, group: String)
}
```

- [ ] **Step 2: Build `RemoteGroupsSectionView`**

```swift
import ComposableArchitecture
import SwiftUI

struct RemoteGroupsSectionView: View {
  @Bindable var store: StoreOf<RemoteGroupsFeature>

  var body: some View {
    Section("Remote Groups") {
      ForEach(store.endpoints) { endpoint in
        Text(endpoint.baseURL.host ?? endpoint.baseURL.absoluteString)
          .tag(SidebarSelection.remoteOverview(endpointID: endpoint.id))
        ForEach(store.groupsByEndpointID[endpoint.id] ?? []) { group in
          Text("\(group.group) (\(group.sessionCount))")
            .tag(SidebarSelection.remoteGroup(endpointID: endpoint.id, group: group.group))
        }
      }
    }
  }
}
```

- [ ] **Step 3: Make footer add button icon-only and route to remote add prompt**

```swift
Button {
  onAddRemote()
} label: {
  Image(systemName: "link.badge.plus")
    .accessibilityLabel("Add Remote Group")
}
.help("Add Remote Group")
```

- [ ] **Step 4: Wire stores in `ContentView` and sidebar constructors**

```swift
SidebarView(
  repositoriesStore: store.scope(state: \.repositories, action: \.repositories),
  remoteGroupsStore: store.scope(state: \.remoteGroups, action: \.remoteGroups),
  terminalManager: terminalManager,
  onAddRemote: { store.send(.remoteGroups(.setAddPromptPresented(true))) }
)
```

- [ ] **Step 5: Run sidebar-related tests**

Run:
```bash
xcodebuild test -project supacode.xcodeproj -scheme supacode -destination "platform=macOS" \
  -only-testing:supacodeTests/RepositorySectionViewTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add supacode/App/ContentView.swift supacode/Features/Repositories/Views/SidebarView.swift supacode/Features/Repositories/Views/SidebarListView.swift supacode/Features/Repositories/Views/SidebarFooterView.swift supacode/Features/Repositories/Views/SidebarSelection.swift supacode/Features/RemoteGroups/Views/RemoteGroupsSectionView.swift
git commit -m "feat(remote-groups): add sidebar section and icon-only add action"
```

---

### Task 6: Remote add prompt and WebView detail branch

**Files:**
- Create: `supacode/Features/RemoteGroups/Views/RemoteGroupAddPromptView.swift`
- Create: `supacode/Features/RemoteGroups/Views/RemoteGroupDetailView.swift`
- Modify: `supacode/App/ContentView.swift`
- Modify: `supacode/Features/Repositories/Views/WorktreeDetailView.swift`

- [ ] **Step 1: Add prompt view**

```swift
import SwiftUI
import ComposableArchitecture

struct RemoteGroupAddPromptView: View {
  @Bindable var store: StoreOf<RemoteGroupsFeature>

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      TextField("https://host/mini-terminal/", text: $store.addURLDraft.sending(\.addURLDraftChanged))
      TextField("group (optional)", text: $store.addGroupDraft.sending(\.addGroupDraftChanged))
      HStack {
        Button("Cancel") { store.send(.setAddPromptPresented(false)) }
        Button("Save") {
          store.send(.submitEndpoint(urlText: store.addURLDraft, initialGroup: store.addGroupDraft))
        }
      }
    }
    .padding(20)
    .frame(minWidth: 520)
  }
}
```

- [ ] **Step 2: Add `WKWebView` detail wrapper**

```swift
import SwiftUI
import WebKit

private struct RemoteGroupWebView: NSViewRepresentable {
  let url: URL

  func makeNSView(context: Context) -> WKWebView {
    let view = WKWebView()
    view.setValue(false, forKey: "drawsBackground")
    return view
  }

  func updateNSView(_ nsView: WKWebView, context: Context) {
    if nsView.url != url {
      nsView.load(URLRequest(url: url))
    }
  }
}

struct RemoteGroupDetailView: View {
  let url: URL

  var body: some View {
    RemoteGroupWebView(url: url)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
```

- [ ] **Step 3: Attach sheet in `ContentView`**

```swift
.sheet(isPresented: $store.remoteGroups.isAddPromptPresented.sending(\.remoteGroups.setAddPromptPresented)) {
  RemoteGroupAddPromptView(store: store.scope(state: \.remoteGroups, action: \.remoteGroups))
}
```

- [ ] **Step 4: Branch in `WorktreeDetailView`**

```swift
if case .group(let endpointID, let group) = store.remoteGroups.selection,
   let endpoint = store.remoteGroups.endpoints.first(where: { $0.id == endpointID }) {
  RemoteGroupDetailView(url: endpoint.groupURL(group: group))
} else if case .overview(let endpointID) = store.remoteGroups.selection,
          let endpoint = store.remoteGroups.endpoints.first(where: { $0.id == endpointID }) {
  RemoteGroupDetailView(url: endpoint.overviewURL)
} else {
  // existing local rendering
}
```

- [ ] **Step 5: Run focused tests**

Run:
```bash
xcodebuild test -project supacode.xcodeproj -scheme supacode -destination "platform=macOS" \
  -only-testing:supacodeTests/RemoteGroupsFeatureTests \
  -only-testing:supacodeTests/AppFeatureRemoteGroupsIntegrationTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add supacode/Features/RemoteGroups/Views/RemoteGroupAddPromptView.swift supacode/Features/RemoteGroups/Views/RemoteGroupDetailView.swift supacode/App/ContentView.swift supacode/Features/Repositories/Views/WorktreeDetailView.swift
git commit -m "feat(remote-groups): add prompt and webview detail rendering"
```

---

### Task 7: Full verification and build

**Files:**
- Modify as needed from previous tasks.

- [ ] **Step 1: Run formatter and linter**

Run: `make check`
Expected: exit code 0.

- [ ] **Step 2: Run all new/affected tests**

Run:
```bash
xcodebuild test -project supacode.xcodeproj -scheme supacode -destination "platform=macOS" \
  -only-testing:supacodeTests/RemoteGroupParsingTests \
  -only-testing:supacodeTests/RemoteTerminalClientTests \
  -only-testing:supacodeTests/RemoteGroupsFeatureTests \
  -only-testing:supacodeTests/AppFeatureRemoteGroupsIntegrationTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation
```
Expected: PASS.

- [ ] **Step 3: Build app**

Run: `make build-app`
Expected: build succeeds.

- [ ] **Step 4: Final integration commit**

```bash
git add supacode/Clients/RemoteTerminal supacode/Features/RemoteGroups supacode/App/ContentView.swift supacode/Features/App/Reducer/AppFeature.swift supacode/Features/Repositories/Views/SidebarView.swift supacode/Features/Repositories/Views/SidebarListView.swift supacode/Features/Repositories/Views/SidebarFooterView.swift supacode/Features/Repositories/Views/SidebarSelection.swift supacode/Features/Repositories/Views/WorktreeDetailView.swift supacodeTests
git commit -m "feat(remote-groups): integrate remote mini-terminal group webview"
```

---

## Spec Coverage Check
- 多远程地址：Task 3 (`endpoints` persisted list).
- group 识别规则与 mini-terminal 一致：Task 1 + Task 3.
- 左侧平级 `Remote Groups`：Task 5.
- `Add Repository` 文案改为图标点击入口：Task 5.
- 输入远程 Web 地址并可选 group：Task 6.
- 右侧 WebView 展示 group/overview：Task 6.
- 鉴权由 H5/Nginx 处理：Task 2 + Task 6（无原生鉴权逻辑）。

## Placeholder Scan
- 无 `TODO` / `TBD` / “later” 语句。
- 每个代码步骤都给出明确代码片段。
- 每个验证步骤都给出命令与期望结果。

## Type Consistency Check
- `RemoteGroupParsing.scope` 在 client 与 reducer 中复用。
- `RemoteSelection` 为 detail 视图分支唯一来源。
- `RemoteEndpoint.groupURL(group:)` 为 group URL 生成唯一入口。
