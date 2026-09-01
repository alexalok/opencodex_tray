# Notification Center Widget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add small and medium macOS Notification Center widgets that fetch OpenCodex quota independently while preserving tray-only pause behavior.

**Architecture:** Split quota reads from pause mutation in `PauseWorkerCore`, then make a shared concurrent snapshot loader serve both tray and widget. A sandboxed WidgetKit extension resolves live, partial, stale, and unavailable states from that snapshot; a checked-in Xcode project embeds it, while SwiftPM remains authoritative for core, CLI, and existing tests.

**Tech Stack:** Swift 6.2, SwiftUI, WidgetKit, AppKit, Foundation, XCTest, Swift Package Manager, Xcode 26.6 build system, zsh, macOS App Sandbox, codesign, notarytool, and pluginkit.

**Spec:** `docs/superpowers/specs/2026-09-01-notification-center-widget-design.md`

## Global Constraints

- Support macOS 14 and later.
- Register only `.systemSmall` and `.systemMedium` widget families.
- Widget performs quota GET requests only; no widget type may consume `OpenCodexPausing`.
- Request next widget refresh exactly 30 minutes after each live timeline entry; WidgetKit controls actual execution.
- Replace cache only when both Codex and Claude succeed.
- Read only `~/.config/opencodex-quota-tray/` and `~/.opencodex/` through extension entitlements; custom paths outside them remain tray-only.
- Keep `Package.swift` authoritative for `PauseWorkerCore`, `pause-worker-once`, `OpenCodexTray` SwiftPM workflows, and core tests.
- Add no third-party runtime or package dependency.
- Local `./scripts/build-app.sh` stays offline and ad-hoc.
- Sign `OpenCodexWidget.appex` before `OpenCodexTray.app` in local and Developer ID flows.
- Preserve current notarization environment precedence and fail-closed behavior.
- Never stage or modify the user's existing `Sources/OpenCodexTray/Resources/CodexBar-LICENSE.txt` edit.
- Keep `.superpowers/` unstaged. Do not push or publish.

## Planned File Map

### Shared core

- Modify `Sources/PauseWorkerCore/OpenCodexClient.swift` — split read and mutation protocols/clients while sharing HTTP transport.
- Modify `Sources/PauseWorkerCore/Quota.swift` — make cache payload types codable.
- Create `Sources/PauseWorkerCore/QuotaSnapshotLoader.swift` — concurrent provider loading and provider-specific results.
- Modify `Sources/PauseWorkerCore/PauseWorker.swift` — consume snapshot loader, retain pause policy, and coalesce refreshes.
- Modify `Sources/PauseWorkerCore/DisplayFormatter.swift` — expose value-only widget formatting without duplicating percentage rules.

### Tray integration

- Modify `Sources/OpenCodexTray/OpenCodexTrayApp.swift` — bootstrap split clients/loader, map snapshots, and load icons from either SwiftPM resource bundle or app main bundle.

### Widget extension

- Create `Sources/OpenCodexWidget/OpenCodexWidgetBundle.swift` — WidgetKit entry point and configuration.
- Create `Sources/OpenCodexWidget/QuotaWidgetState.swift` — pure live/partial/stale/unavailable resolution and view models.
- Create `Sources/OpenCodexWidget/WidgetSnapshotCache.swift` — atomic extension-container JSON cache.
- Create `Sources/OpenCodexWidget/QuotaWidgetTimelineProvider.swift` — config/token bootstrap and 30-minute timeline.
- Create `Sources/OpenCodexWidget/QuotaWidgetView.swift` — provider-split small and medium SwiftUI views.
- Create `Resources/OpenCodexWidget-Info.plist` — WidgetKit extension metadata.
- Create `Resources/OpenCodexWidget.entitlements` — sandbox, network, and two read-only home-relative exceptions.

### Xcode and build

- Create `OpenCodexTray.xcodeproj/project.pbxproj` — app, widget extension, and widget unit-test targets.
- Create `OpenCodexTray.xcodeproj/xcshareddata/xcschemes/OpenCodexTray.xcscheme` — shared build/test scheme.
- Modify `scripts/build-app.sh` — offline Xcode build, nested signing, existing notarization.
- Create `tests/xcode-project-tests.sh` — target graph, embedding, plist, and entitlement checks.
- Modify `tests/build-app-tests.sh` — fake Xcode product and sign-order assertions.
- Modify `tests/release-artifact-tests.sh` — embedded extension and resource verification.

### Tests and docs

- Modify `tests/PauseWorkerCoreTests/OpenCodexClientTests.swift`.
- Create `tests/PauseWorkerCoreTests/QuotaSnapshotLoaderTests.swift`.
- Modify `tests/PauseWorkerCoreTests/WorkerTests.swift`.
- Modify `tests/PauseWorkerCoreTests/DisplayFormatterTests.swift`.
- Create `tests/OpenCodexWidgetTests/QuotaWidgetStateTests.swift`.
- Create `tests/OpenCodexWidgetTests/WidgetSnapshotCacheTests.swift`.
- Create `tests/OpenCodexWidgetTests/QuotaWidgetTimelineTests.swift`.
- Create `tests/OpenCodexWidgetTests/WidgetTestFixtures.swift`.
- Modify `README.md` — widget behavior, refresh semantics, and default-path limitation.

---

### Task 1: Split Quota Reads from Pause Mutation

**Files:**
- Modify: `Sources/PauseWorkerCore/OpenCodexClient.swift`
- Modify: `tests/PauseWorkerCoreTests/OpenCodexClientTests.swift`

**Interfaces:**
- Produces: `OpenCodexQuotaServing.fetchAccounts()` and `fetchClaudeAccounts()`.
- Produces: `OpenCodexPausing.pauseAccount(id:)`.
- Produces: fetch-only `OpenCodexQuotaClient` and mutation-only `OpenCodexPauseClient`.
- Temporarily preserves current `OpenCodexServing` and `OpenCodexClient` so the pre-refactor worker remains green until Task 3.

- [ ] **Step 1: Add failing client-boundary tests**

Extend `OpenCodexClientTests` with exact request assertions and a negative protocol-conformance check:

```swift
func testQuotaClientDoesNotExposePauseCapability() {
    let client = OpenCodexQuotaClient(
        baseURL: URL(string: "https://opencodex.example")!,
        adminToken: "admin-secret",
        timeout: 5,
        session: URLSession(configuration: .ephemeral)
    )

    XCTAssertFalse(client is any OpenCodexPausing)
}

func testQuotaClientUsesCodexRefreshEndpoint() async throws {
    let session = stubSession()
    StubURLProtocol.handler = { request in
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/api/codex-auth/accounts")
        XCTAssertEqual(request.url?.query, "refresh=1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer admin-secret")
        return (
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
            Data(#"{"accounts":[{"id":"codex-a","alias":"workmate","plan":"prolite","paused":false,"quota":{"weeklyPercent":53}}]}"#.utf8)
        )
    }
    let client = OpenCodexQuotaClient(
        baseURL: URL(string: "https://opencodex.example")!,
        adminToken: "admin-secret",
        timeout: 5,
        session: session
    )

    let accounts = try await client.fetchAccounts()

    XCTAssertEqual(accounts, [
        OpenCodexAccount(
            id: "codex-a",
            alias: "workmate",
            plan: "prolite",
            isMain: false,
            paused: false,
            weeklyUsedPercent: 53
        ),
    ])
}

func testPauseClientUsesPauseEndpoint() async throws {
    let session = stubSession()
    StubURLProtocol.handler = { request in
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path, "/api/codex-auth/accounts/pause")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer admin-secret")
        XCTAssertEqual(
            try JSONSerialization.jsonObject(with: request.httpBody!) as? NSDictionary,
            ["id": "account-1", "paused": true]
        )
        return (
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
            Data(#"{"ok":true,"id":"account-1","paused":true}"#.utf8)
        )
    }

    let client = OpenCodexPauseClient(
        baseURL: URL(string: "https://opencodex.example")!,
        adminToken: "admin-secret",
        timeout: 5,
        session: session
    )
    try await client.pauseAccount(id: "account-1")
}

private func stubSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: configuration)
}
```

Move existing Claude endpoint test to `OpenCodexQuotaClient` and use the same `stubSession()` helper.

- [ ] **Step 2: Run focused tests and verify red state**

Run:

```bash
swift test --filter OpenCodexClientTests
```

Expected: compile failure containing `cannot find 'OpenCodexQuotaClient' in scope` or `cannot find type 'OpenCodexPausing' in scope`.

- [ ] **Step 3: Implement protocol and client split**

Keep response DTOs and decoders in the same file. Introduce these exact public interfaces:

```swift
public protocol OpenCodexQuotaServing: Sendable {
    func fetchAccounts() async throws -> [OpenCodexAccount]
    func fetchClaudeAccounts() async throws -> [ClaudeAccount]
}

public protocol OpenCodexPausing: Sendable {
    func pauseAccount(id: String) async throws
}

public protocol OpenCodexServing: OpenCodexQuotaServing, OpenCodexPausing {}

public actor OpenCodexQuotaClient: OpenCodexQuotaServing {
    private let transport: OpenCodexTransport

    public init(baseURL: URL, adminToken: String, timeout: TimeInterval, session: URLSession? = nil) {
        transport = OpenCodexTransport(
            baseURL: baseURL,
            adminToken: adminToken,
            timeout: timeout,
            session: session
        )
    }

    public func fetchAccounts() async throws -> [OpenCodexAccount] {
        let data = try await transport.send(
            path: "/api/codex-auth/accounts?refresh=1",
            method: "GET",
            operation: "accounts"
        )
        do {
            return try OpenCodexResponseDecoder.decodeAccounts(data)
        } catch {
            throw OpenCodexClientError.invalidResponse("OpenCodex returned an invalid account response")
        }
    }

    public func fetchClaudeAccounts() async throws -> [ClaudeAccount] {
        let data = try await transport.send(
            path: "/api/oauth/accounts?provider=anthropic&quota=1&refresh=1",
            method: "GET",
            operation: "Claude accounts"
        )
        do {
            return try OpenCodexResponseDecoder.decodeClaudeAccounts(data)
        } catch {
            throw OpenCodexClientError.invalidResponse("OpenCodex returned an invalid Claude account response")
        }
    }
}

public actor OpenCodexPauseClient: OpenCodexPausing {
    private let transport: OpenCodexTransport

    public init(baseURL: URL, adminToken: String, timeout: TimeInterval, session: URLSession? = nil) {
        transport = OpenCodexTransport(
            baseURL: baseURL,
            adminToken: adminToken,
            timeout: timeout,
            session: session
        )
    }

    public func pauseAccount(id: String) async throws {
        let data = try await transport.send(
            path: "/api/codex-auth/accounts/pause",
            method: "PUT",
            operation: "pause",
            body: try JSONEncoder().encode(PauseRequest(id: id, paused: true))
        )
        guard let response = try? JSONDecoder().decode(PauseResponse.self, from: data),
              response.ok, response.id == id, response.paused else {
            throw OpenCodexClientError.invalidResponse("OpenCodex returned an invalid pause response")
        }
    }
}
```

Implement private `OpenCodexTransport.send(path:method:operation:body:)` by moving the current endpoint construction, bearer and Accept headers, optional JSON Content-Type/body, `URLSession.data(for:)` call, 2xx check, and sanitized network-error mapping unchanged. Keep `OpenCodexClient` as a transitional combined adapter that owns one quota client and one pause client and forwards all three protocol methods, so no caller breaks in this commit.

- [ ] **Step 4: Run focused and full tests**

Run:

```bash
swift test --filter OpenCodexClientTests
swift test
```

Expected: both commands exit 0; existing endpoint/decoder/worker tests remain green.

- [ ] **Step 5: Review and commit**

Confirm `git diff --check` is clean and staged files exclude the license edit:

```bash
git add Sources/PauseWorkerCore/OpenCodexClient.swift tests/PauseWorkerCoreTests/OpenCodexClientTests.swift
git diff --cached --check
git commit -m "refactor: split quota fetch and pause clients"
```

### Task 2: Add Concurrent Shared Snapshot Loader

**Files:**
- Modify: `Sources/PauseWorkerCore/Quota.swift`
- Create: `Sources/PauseWorkerCore/QuotaSnapshotLoader.swift`
- Create: `tests/PauseWorkerCoreTests/QuotaSnapshotLoaderTests.swift`

**Interfaces:**
- Consumes: `OpenCodexQuotaServing` from Task 1.
- Produces: codable `QuotaSnapshot`.
- Produces: `QuotaSnapshotLoad` with optional raw Codex accounts.
- Produces: `QuotaSnapshotLoading.load() async -> QuotaSnapshotLoad`.
- Produces: concrete `QuotaSnapshotLoader` with injectable `now` closure.

- [ ] **Step 1: Write failing loader tests**

Create tests for complete success, each partial failure, total failure, target-alias validation, preserved API order, and concurrent start. Use deterministic errors:

```swift
private enum FakeQuotaError: LocalizedError, Sendable {
    case codex
    case claude

    var errorDescription: String? {
        switch self {
        case .codex: "Codex unavailable"
        case .claude: "Claude unavailable"
        }
    }
}

private enum FakeOutcome<Value: Sendable>: Sendable {
    case success(Value)
    case failure(FakeQuotaError)
}

private actor ConcurrentFetchProbe {
    private var active = 0
    private var maximum = 0

    func enter() {
        active += 1
        maximum = max(maximum, active)
    }

    func leave() {
        active -= 1
    }

    func maximumActive() -> Int { maximum }
}

private actor FakeQuotaClient: OpenCodexQuotaServing {
    let codexResult: FakeOutcome<[OpenCodexAccount]>
    let claudeResult: FakeOutcome<[ClaudeAccount]>
    let probe: ConcurrentFetchProbe?

    init(
        codexResult: FakeOutcome<[OpenCodexAccount]>,
        claudeResult: FakeOutcome<[ClaudeAccount]>,
        probe: ConcurrentFetchProbe? = nil
    ) {
        self.codexResult = codexResult
        self.claudeResult = claudeResult
        self.probe = probe
    }

    func fetchAccounts() async throws -> [OpenCodexAccount] {
        await probe?.enter()
        if probe != nil { try? await Task.sleep(for: .milliseconds(50)) }
        await probe?.leave()
        switch codexResult {
        case let .success(accounts): return accounts
        case let .failure(error): throw error
        }
    }

    func fetchClaudeAccounts() async throws -> [ClaudeAccount] {
        await probe?.enter()
        if probe != nil { try? await Task.sleep(for: .milliseconds(50)) }
        await probe?.leave()
        switch claudeResult {
        case let .success(accounts): return accounts
        case let .failure(error): throw error
        }
    }
}

private let codexAccounts = [
    OpenCodexAccount(
        id: "friend-id",
        alias: "workmate",
        plan: "prolite",
        isMain: false,
        paused: false,
        weeklyUsedPercent: 53
    ),
]

private let claudeAccounts = [
    ClaudeAccount(
        id: "claude-a",
        alias: "work",
        email: "w***@example.com",
        fiveHourUsedPercent: 50,
        weeklyUsedPercent: 20
    ),
    ClaudeAccount(
        id: "claude-b",
        alias: "personal",
        email: "p***@example.com",
        fiveHourUsedPercent: 10,
        weeklyUsedPercent: 60
    ),
]

func testClaudeFailureKeepsCodexSnapshot() async {
    let timestamp = Date(timeIntervalSince1970: 1_788_231_600)
    let loader = QuotaSnapshotLoader(
        client: FakeQuotaClient(
            codexResult: .success(codexAccounts),
            claudeResult: .failure(FakeQuotaError.claude)
        ),
        targetAlias: "workmate",
        thresholdPercent: 70,
        now: { timestamp }
    )

    let load = await loader.load()

    XCTAssertEqual(load.snapshot.fetchedAt, timestamp)
    XCTAssertNotNil(load.snapshot.codexSummary)
    XCTAssertNil(load.snapshot.codexErrorMessage)
    XCTAssertNil(load.snapshot.claudeSummary)
    XCTAssertEqual(load.snapshot.claudeErrorMessage, "Claude unavailable")
    XCTAssertEqual(load.codexAccounts, codexAccounts)
}
```

Add these named cases with exact assertions:

| Test | Fake results | Assertions |
| --- | --- | --- |
| `testCompleteLoadReturnsBothSummariesAndRawCodexAccounts` | `codexAccounts` + `claudeAccounts` | Codex aggregate `4`; Claude aggregates `140` and `120`; both errors nil; raw Codex accounts equal input |
| `testCodexFailureKeepsClaudeSnapshot` | Codex `.failure(.codex)` + Claude success | Codex summary/accounts nil; Codex error `Codex unavailable`; Claude summary non-nil |
| `testBothFailuresReturnTimestampedEmptySnapshot` | both failures | `hasProviderData == false`; both exact error strings; raw accounts nil |
| `testMissingTargetAliasIsCodexOnlyFailure` | Codex success without `workmate` + Claude success | Codex error equals `Target account alias \"workmate\" was not returned by OpenCodex`; Claude summary remains available |
| `testDuplicateTargetAliasIsCodexOnlyFailure` | two Codex accounts aliased `workmate` + Claude success | Codex error equals `Target account alias \"workmate\" matched multiple OpenCodex accounts`; Claude summary remains available |
| `testRowsPreserveAPIOrder` | two Codex and two Claude accounts in known order | resulting row labels equal input order for each provider |

Add this concurrency test; the overlap probe avoids wall-clock threshold assertions:

```swift
func testLoadStartsProviderRequestsConcurrently() async {
    let probe = ConcurrentFetchProbe()
    let loader = QuotaSnapshotLoader(
        client: FakeQuotaClient(
            codexResult: .success(codexAccounts),
            claudeResult: .success([]),
            probe: probe
        ),
        targetAlias: "workmate",
        thresholdPercent: 70
    )

    _ = await loader.load()
    let maximumActive = await probe.maximumActive()

    XCTAssertEqual(maximumActive, 2)
}
```

- [ ] **Step 2: Run loader tests and verify red state**

Run:

```bash
swift test --filter QuotaSnapshotLoaderTests
```

Expected: compile failure containing `cannot find 'QuotaSnapshotLoader' in scope`.

- [ ] **Step 3: Make snapshot payloads codable**

Add `Codable` to cache payload types only by changing these conformance clauses:

```diff
-public struct AccountAllowance: Equatable, Sendable, Identifiable {
+public struct AccountAllowance: Codable, Equatable, Sendable, Identifiable {
-public struct QuotaSummary: Equatable, Sendable {
+public struct QuotaSummary: Codable, Equatable, Sendable {
-public struct ClaudeAccountAllowance: Equatable, Sendable, Identifiable {
+public struct ClaudeAccountAllowance: Codable, Equatable, Sendable, Identifiable {
-public struct ClaudeQuotaSummary: Equatable, Sendable {
+public struct ClaudeQuotaSummary: Codable, Equatable, Sendable {
```

Raw account models do not need `Codable` because the extension cache stores summaries, not API payloads. Add a public initializer to `QuotaSummary` so widget placeholder/test code outside `PauseWorkerCore` can construct it:

```swift
public init(trayPercentage: Int?, rows: [AccountAllowance]) {
    self.trayPercentage = trayPercentage
    self.rows = rows
}
```

- [ ] **Step 4: Implement snapshot types and concurrent loader**

Use these exact shapes:

```swift
import Foundation

public struct QuotaSnapshot: Codable, Equatable, Sendable {
    public let fetchedAt: Date
    public let codexSummary: QuotaSummary?
    public let codexErrorMessage: String?
    public let claudeSummary: ClaudeQuotaSummary?
    public let claudeErrorMessage: String?

    public init(
        fetchedAt: Date,
        codexSummary: QuotaSummary?,
        codexErrorMessage: String?,
        claudeSummary: ClaudeQuotaSummary?,
        claudeErrorMessage: String?
    ) {
        self.fetchedAt = fetchedAt
        self.codexSummary = codexSummary
        self.codexErrorMessage = codexErrorMessage
        self.claudeSummary = claudeSummary
        self.claudeErrorMessage = claudeErrorMessage
    }

    public var isComplete: Bool {
        codexSummary != nil && claudeSummary != nil
    }

    public var hasProviderData: Bool {
        codexSummary != nil || claudeSummary != nil
    }
}

public struct QuotaSnapshotLoad: Equatable, Sendable {
    public let snapshot: QuotaSnapshot
    public let codexAccounts: [OpenCodexAccount]?

    public init(snapshot: QuotaSnapshot, codexAccounts: [OpenCodexAccount]?) {
        self.snapshot = snapshot
        self.codexAccounts = codexAccounts
    }
}

public protocol QuotaSnapshotLoading: Sendable {
    func load() async -> QuotaSnapshotLoad
}

public struct QuotaSnapshotLoader: QuotaSnapshotLoading {
    private let client: any OpenCodexQuotaServing
    private let targetAlias: String
    private let thresholdPercent: Double
    private let now: @Sendable () -> Date

    public init(
        client: any OpenCodexQuotaServing,
        targetAlias: String,
        thresholdPercent: Double,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.client = client
        self.targetAlias = targetAlias
        self.thresholdPercent = thresholdPercent
        self.now = now
    }

    public func load() async -> QuotaSnapshotLoad {
        async let codex = loadCodex()
        async let claude = loadClaude()
        let (codexResult, claudeResult) = await (codex, claude)
        return QuotaSnapshotLoad(
            snapshot: QuotaSnapshot(
                fetchedAt: now(),
                codexSummary: codexResult.summary,
                codexErrorMessage: codexResult.errorMessage,
                claudeSummary: claudeResult.summary,
                claudeErrorMessage: claudeResult.errorMessage
            ),
            codexAccounts: codexResult.accounts
        )
    }

    private func loadCodex() async -> CodexLoadResult {
        do {
            let accounts = try await client.fetchAccounts()
            let summary = try QuotaCalculator.summarize(
                accounts: accounts,
                targetAlias: targetAlias,
                thresholdPercent: thresholdPercent
            )
            return CodexLoadResult(summary: summary, accounts: accounts, errorMessage: nil)
        } catch {
            return CodexLoadResult(summary: nil, accounts: nil, errorMessage: error.localizedDescription)
        }
    }

    private func loadClaude() async -> ClaudeLoadResult {
        do {
            let accounts = try await client.fetchClaudeAccounts()
            return ClaudeLoadResult(
                summary: ClaudeQuotaCalculator.summarize(accounts: accounts),
                errorMessage: nil
            )
        } catch {
            return ClaudeLoadResult(summary: nil, errorMessage: error.localizedDescription)
        }
    }
}

private struct CodexLoadResult: Sendable {
    let summary: QuotaSummary?
    let accounts: [OpenCodexAccount]?
    let errorMessage: String?
}

private struct ClaudeLoadResult: Sendable {
    let summary: ClaudeQuotaSummary?
    let errorMessage: String?
}
```

This calls `now()` once after both child results resolve, so one timestamp describes the complete load attempt.

- [ ] **Step 5: Run focused and full tests**

Run:

```bash
swift test --filter QuotaSnapshotLoaderTests
swift test
```

Expected: both commands exit 0, including the provider-overlap test.

- [ ] **Step 6: Review and commit**

```bash
git add Sources/PauseWorkerCore/Quota.swift Sources/PauseWorkerCore/QuotaSnapshotLoader.swift tests/PauseWorkerCoreTests/QuotaSnapshotLoaderTests.swift
git diff --cached --check
git commit -m "feat: add shared quota snapshot loader"
```

### Task 3: Route Tray Refresh Through Shared Loader

**Files:**
- Modify: `Sources/PauseWorkerCore/PauseWorker.swift`
- Modify: `Sources/OpenCodexTray/OpenCodexTrayApp.swift`
- Modify: `Sources/PauseWorkerCore/OpenCodexClient.swift`
- Modify: `tests/PauseWorkerCoreTests/WorkerTests.swift`

**Interfaces:**
- Consumes: `QuotaSnapshotLoading` and `OpenCodexPausing`.
- Produces: `WorkerRefresh.snapshot: QuotaSnapshot` and `pausedAccountID: String?`.
- Removes: transitional combined `OpenCodexServing` and `OpenCodexClient`.
- Preserves: one in-flight refresh and exact target/threshold pause behavior.

- [ ] **Step 1: Rewrite worker tests against split fakes**

Use separate loader and pauser actors:

```swift
private actor FakeSnapshotLoader: QuotaSnapshotLoading {
    let result: QuotaSnapshotLoad
    let delay: Duration?
    private(set) var callCount = 0

    init(result: QuotaSnapshotLoad, delay: Duration? = nil) {
        self.result = result
        self.delay = delay
    }

    func load() async -> QuotaSnapshotLoad {
        callCount += 1
        if let delay { try? await Task.sleep(for: delay) }
        return result
    }

    func calls() -> Int { callCount }
}

private actor FakePauser: OpenCodexPausing {
    private(set) var pausedIDs: [String] = []
    func pauseAccount(id: String) async throws { pausedIDs.append(id) }
    func pauses() -> [String] { pausedIDs }
}
```

Cover these exact outcomes:

- Codex success at threshold pauses resolved ID.
- Claude failure does not block Codex pause.
- Codex failure returns Claude data and performs no pause.
- Already-paused target performs no pause.
- Two concurrent refreshes produce one loader call and one pause.

Include these two regression tests:

```swift
func testCodexFailureReturnsClaudeAndDoesNotPause() async throws {
    let snapshot = QuotaSnapshot(
        fetchedAt: Date(timeIntervalSince1970: 1_788_231_600),
        codexSummary: nil,
        codexErrorMessage: "Codex unavailable",
        claudeSummary: ClaudeQuotaSummary(
            fiveHourRemainingPercentage: 97,
            weeklyRemainingPercentage: 88,
            rows: []
        ),
        claudeErrorMessage: nil
    )
    let loader = FakeSnapshotLoader(
        result: QuotaSnapshotLoad(snapshot: snapshot, codexAccounts: nil)
    )
    let pauser = FakePauser()
    let worker = PauseWorker(
        loader: loader,
        pauser: pauser,
        targetAlias: "workmate",
        thresholdPercent: 70
    )

    let result = try await worker.refresh()
    let pauses = await pauser.pauses()

    XCTAssertEqual(result.snapshot, snapshot)
    XCTAssertNil(result.pausedAccountID)
    XCTAssertEqual(pauses, [])
}

func testConcurrentRefreshesCoalesceLoaderAndPause() async throws {
    let accounts = [
        OpenCodexAccount(
            id: "friend-id",
            alias: "workmate",
            plan: "prolite",
            isMain: false,
            paused: false,
            weeklyUsedPercent: 70
        ),
    ]
    let snapshot = QuotaSnapshot(
        fetchedAt: Date(timeIntervalSince1970: 1_788_231_600),
        codexSummary: try QuotaCalculator.summarize(
            accounts: accounts,
            targetAlias: "workmate",
            thresholdPercent: 70
        ),
        codexErrorMessage: nil,
        claudeSummary: ClaudeQuotaCalculator.summarize(accounts: []),
        claudeErrorMessage: nil
    )
    let loader = FakeSnapshotLoader(
        result: QuotaSnapshotLoad(snapshot: snapshot, codexAccounts: accounts),
        delay: .milliseconds(50)
    )
    let pauser = FakePauser()
    let worker = PauseWorker(
        loader: loader,
        pauser: pauser,
        targetAlias: "workmate",
        thresholdPercent: 70
    )

    async let first = worker.refresh()
    async let second = worker.refresh()
    _ = try await (first, second)

    let calls = await loader.calls()
    let pauses = await pauser.pauses()
    XCTAssertEqual(calls, 1)
    XCTAssertEqual(pauses, ["friend-id"])
}
```

- [ ] **Step 2: Run worker tests and verify red state**

Run:

```bash
swift test --filter WorkerTests
```

Expected: compile failures because `PauseWorker` still requires combined `OpenCodexServing` and `WorkerRefresh` lacks `snapshot`.

- [ ] **Step 3: Refactor worker around loader and pauser**

Implement this initializer and result:

```swift
public struct WorkerRefresh: Equatable, Sendable {
    public let snapshot: QuotaSnapshot
    public let pausedAccountID: String?
}

public actor PauseWorker {
    public init(
        loader: any QuotaSnapshotLoading,
        pauser: any OpenCodexPausing,
        targetAlias: String,
        thresholdPercent: Double
    )
}
```

`refresh()` coalesces with the existing `inFlightRefresh` pattern. After `loader.load()`, inspect `codexAccounts` only. Require one exact target alias, skip mutation when already paused or usage is below threshold, and propagate pause-client errors. Always return the loader snapshot when no pause is required.

- [ ] **Step 4: Update tray bootstrap and state mapping**

Construct one `OpenCodexQuotaClient`, one `OpenCodexPauseClient`, and one `QuotaSnapshotLoader` from the same validated config/token:

```swift
let quotaClient = OpenCodexQuotaClient(
    baseURL: config.baseURL,
    adminToken: token,
    timeout: config.requestTimeout
)
let loader = QuotaSnapshotLoader(
    client: quotaClient,
    targetAlias: config.targetAlias,
    thresholdPercent: config.thresholdPercent
)
let worker = PauseWorker(
    loader: loader,
    pauser: OpenCodexPauseClient(
        baseURL: config.baseURL,
        adminToken: token,
        timeout: config.requestTimeout
    ),
    targetAlias: config.targetAlias,
    thresholdPercent: config.thresholdPercent
)
```

Map `result.snapshot.codexSummary` and `claudeSummary` independently. Preserve existing rows on a provider failure, set that provider title to `!`, and show provider-specific error text. Remove transitional combined protocol/client after no caller references them.

- [ ] **Step 5: Run core, executable, and resource checks**

Run:

```bash
swift test
swift build --product OpenCodexTray
swift run OpenCodexTray --verify-resources
```

Expected: all commands exit 0; resource command prints `Resources OK`.

- [ ] **Step 6: Review and commit**

```bash
git add Sources/PauseWorkerCore/PauseWorker.swift Sources/PauseWorkerCore/OpenCodexClient.swift Sources/OpenCodexTray/OpenCodexTrayApp.swift tests/PauseWorkerCoreTests/WorkerTests.swift
git diff --cached --check
git commit -m "refactor: share quota loading with tray"
```

### Task 4: Add Xcode App and Widget Extension Targets

**Files:**
- Create: `OpenCodexTray.xcodeproj/project.pbxproj`
- Create: `OpenCodexTray.xcodeproj/xcshareddata/xcschemes/OpenCodexTray.xcscheme`
- Create: `Resources/OpenCodexWidget-Info.plist`
- Create: `Resources/OpenCodexWidget.entitlements`
- Create: `Sources/OpenCodexWidget/OpenCodexWidgetBundle.swift`
- Create: `tests/xcode-project-tests.sh`

**Interfaces:**
- Consumes: existing app sources and local package product `PauseWorkerCore`.
- Produces: app target `OpenCodexTray`.
- Produces: extension target/module `OpenCodexWidget` embedded at `Contents/PlugIns/OpenCodexWidget.appex`.
- Produces: shared `OpenCodexTray` scheme.

- [ ] **Step 1: Write failing Xcode project contract test**

Create an executable zsh test that uses a temporary DerivedData directory and removes only that exact directory in its trap:

```zsh
#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$(mktemp -d /tmp/opencodex-xcode-tests.XXXXXX)"
trap 'rm -rf "$DERIVED"' EXIT

xcodebuild \
  -project "$ROOT/OpenCodexTray.xcodeproj" \
  -scheme OpenCodexTray \
  -configuration Release \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED" \
  -disableAutomaticPackageResolution \
  CODE_SIGNING_ALLOWED=NO \
  build

APP="$DERIVED/Build/Products/Release/OpenCodexTray.app"
WIDGET="$APP/Contents/PlugIns/OpenCodexWidget.appex"
test -x "$APP/Contents/MacOS/OpenCodexTray"
test -d "$WIDGET"
test -x "$WIDGET/Contents/MacOS/OpenCodexWidget"
test "$(plutil -extract NSExtension.NSExtensionPointIdentifier raw -o - "$WIDGET/Contents/Info.plist")" = "com.apple.widgetkit-extension"
test -f "$APP/Contents/Resources/ProviderIcon-claude.svg"
test -f "$APP/Contents/Resources/ProviderIcon-codex.svg"
test -f "$APP/Contents/Resources/CodexBar-LICENSE.txt"
test -f "$WIDGET/Contents/Resources/ProviderIcon-claude.svg"
test -f "$WIDGET/Contents/Resources/ProviderIcon-codex.svg"
test -f "$WIDGET/Contents/Resources/CodexBar-LICENSE.txt"
test "$(plutil -extract com.apple.security.app-sandbox raw -o - "$ROOT/Resources/OpenCodexWidget.entitlements")" = "true"
test "$(plutil -extract com.apple.security.network.client raw -o - "$ROOT/Resources/OpenCodexWidget.entitlements")" = "true"
if rg -n 'OpenCodexPausing|OpenCodexPauseClient|pauseAccount|/pause' "$ROOT/Sources/OpenCodexWidget"; then
  print -u2 -- "FAIL: widget source contains pause capability"
  exit 1
fi

print -- "PASS: Xcode app embeds WidgetKit extension"
```

- [ ] **Step 2: Run project contract test and verify red state**

Run:

```bash
chmod +x tests/xcode-project-tests.sh
./tests/xcode-project-tests.sh
```

Expected: failure containing `The project 'OpenCodexTray.xcodeproj' does not exist`.

- [ ] **Step 3: Add exact widget metadata and entitlements**

`Resources/OpenCodexWidget-Info.plist` must contain:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>OpenCodex Quota</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$(PRODUCT_NAME)</string>
    <key>CFBundlePackageType</key>
    <string>XPC!</string>
    <key>CFBundleShortVersionString</key>
    <string>$(MARKETING_VERSION)</string>
    <key>CFBundleVersion</key>
    <string>$(CURRENT_PROJECT_VERSION)</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.widgetkit-extension</string>
    </dict>
</dict>
</plist>
```

`Resources/OpenCodexWidget.entitlements` must contain only:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.temporary-exception.files.home-relative-path.read-only</key>
    <array>
        <string>/.config/opencodex-quota-tray/</string>
        <string>/.opencodex/</string>
    </array>
</dict>
</plist>
```

- [ ] **Step 4: Add minimal compilable WidgetKit entry point**

Create a temporary static entry used only to establish target wiring:

```swift
import SwiftUI
import WidgetKit

private struct WiringEntry: TimelineEntry {
    let date: Date
}

private struct WiringProvider: TimelineProvider {
    func placeholder(in context: Context) -> WiringEntry { WiringEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (WiringEntry) -> Void) {
        completion(WiringEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WiringEntry>) -> Void) {
        completion(Timeline(entries: [WiringEntry(date: .now)], policy: .never))
    }
}

@main
struct OpenCodexWidgetBundle: WidgetBundle {
    var body: some Widget {
        StaticConfiguration(kind: "OpenCodexQuota", provider: WiringProvider()) { _ in
            Text("OpenCodex Quota")
        }
        .configurationDisplayName("OpenCodex Quota")
        .description("Codex and Claude quota remaining.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
```

Task 6 replaces `WiringEntry` and `WiringProvider` with production types.

- [ ] **Step 5: Create exact Xcode target graph**

Create `project.pbxproj` with three products/dependencies:

| Target | Product | Sources | Resources | Dependencies |
| --- | --- | --- | --- | --- |
| `OpenCodexTray` | application | `Sources/OpenCodexTray/OpenCodexTrayApp.swift` | `Resources/AppIcon.icns`, both provider SVG files, and `CodexBar-LICENSE.txt` | local package `PauseWorkerCore`; embeds `OpenCodexWidget` |
| `OpenCodexWidget` | app extension | `Sources/OpenCodexWidget/OpenCodexWidgetBundle.swift` | both provider SVG files and `CodexBar-LICENSE.txt` | local package `PauseWorkerCore` |
| `OpenCodexWidgetTests` | XCTest bundle | no source until Task 5 | none | local package `PauseWorkerCore` |

Use these exact build settings:

| Setting | App | Widget | Tests |
| --- | --- | --- | --- |
| `MACOSX_DEPLOYMENT_TARGET` | `14.0` | `14.0` | `14.0` |
| `SWIFT_VERSION` | `6.0` | `6.0` | `6.0` |
| `PRODUCT_BUNDLE_IDENTIFIER` | `local.opencodex.quota-tray` | `local.opencodex.quota-tray.widget` | `local.opencodex.quota-tray.widget-tests` |
| `INFOPLIST_FILE` | `Resources/Info.plist` | `Resources/OpenCodexWidget-Info.plist` | generated |
| `CODE_SIGN_ENTITLEMENTS` | unset | `Resources/OpenCodexWidget.entitlements` | unset |
| `APPLICATION_EXTENSION_API_ONLY` | unset | `YES` | unset |
| `SKIP_INSTALL` | `NO` | `YES` | `YES` |
| `MARKETING_VERSION` | `0.2.1` | `0.2.1` | `0.2.1` |
| `CURRENT_PROJECT_VERSION` | `3` | `3` | `3` |

Use stable target IDs `A10000000000000000000001` for app, `A10000000000000000000002` for widget, and `A10000000000000000000003` for tests in both project and scheme. The app's Copy Files phase uses destination `PlugIns`, has `CodeSignOnCopy` and `RemoveHeadersOnCopy` attributes, and contains `OpenCodexWidget.appex`. Add the repository root as an `XCLocalSwiftPackageReference` and link only `PauseWorkerCore`.

Write the shared scheme with this target wiring:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2660" version="1.7">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
    <BuildActionEntries>
      <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
        <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="A10000000000000000000001" BuildableName="OpenCodexTray.app" BlueprintName="OpenCodexTray" ReferencedContainer="container:OpenCodexTray.xcodeproj"/>
      </BuildActionEntry>
      <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
        <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="A10000000000000000000002" BuildableName="OpenCodexWidget.appex" BlueprintName="OpenCodexWidget" ReferencedContainer="container:OpenCodexTray.xcodeproj"/>
      </BuildActionEntry>
    </BuildActionEntries>
  </BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
    <Testables>
      <TestableReference skipped="NO">
        <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="A10000000000000000000003" BuildableName="OpenCodexWidgetTests.xctest" BlueprintName="OpenCodexWidgetTests" ReferencedContainer="container:OpenCodexTray.xcodeproj"/>
      </TestableReference>
    </Testables>
  </TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES">
    <BuildableProductRunnable runnableDebuggingMode="0">
      <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="A10000000000000000000001" BuildableName="OpenCodexTray.app" BlueprintName="OpenCodexTray" ReferencedContainer="container:OpenCodexTray.xcodeproj"/>
    </BuildableProductRunnable>
  </LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">
    <BuildableProductRunnable runnableDebuggingMode="0">
      <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="A10000000000000000000001" BuildableName="OpenCodexTray.app" BlueprintName="OpenCodexTray" ReferencedContainer="container:OpenCodexTray.xcodeproj"/>
    </BuildableProductRunnable>
  </ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
```

- [ ] **Step 6: Run project and SwiftPM checks**

Run:

```bash
./tests/xcode-project-tests.sh
xcodebuild -project OpenCodexTray.xcodeproj -list
swift test
```

Expected: contract script prints its PASS line; project lists all three targets and shared scheme; Swift tests exit 0.

- [ ] **Step 7: Review and commit**

```bash
git add OpenCodexTray.xcodeproj Resources/OpenCodexWidget-Info.plist Resources/OpenCodexWidget.entitlements Sources/OpenCodexWidget/OpenCodexWidgetBundle.swift tests/xcode-project-tests.sh
git diff --cached --check
git commit -m "build: add WidgetKit extension target"
```

### Task 5: Implement Widget State Resolution and Cache

**Files:**
- Create: `Sources/OpenCodexWidget/QuotaWidgetState.swift`
- Create: `Sources/OpenCodexWidget/WidgetSnapshotCache.swift`
- Create: `tests/OpenCodexWidgetTests/QuotaWidgetStateTests.swift`
- Create: `tests/OpenCodexWidgetTests/WidgetSnapshotCacheTests.swift`
- Create: `tests/OpenCodexWidgetTests/WidgetTestFixtures.swift`
- Modify: `OpenCodexTray.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `QuotaSnapshot` and `QuotaSnapshotLoad`.
- Produces: `QuotaWidgetContent`, `QuotaWidgetResolution`, and `QuotaWidgetStateResolver.resolve(load:cached:)`.
- Produces: async `WidgetSnapshotCaching` and actor `WidgetSnapshotCache`.

- [ ] **Step 1: Write failing state-resolution tests**

Add `QuotaWidgetState.swift` and `WidgetSnapshotCache.swift` to both widget and widget-test target membership. Add `WidgetTestFixtures.swift` to widget-test target membership only. Create these exact shared fixtures:

```swift
import Foundation
import PauseWorkerCore

let widgetTestDate = Date(timeIntervalSince1970: 1_788_231_600)

func makeCodexSummary(
    rows: [AccountAllowance] = [
        AccountAllowance(
            accountId: "codex-main",
            label: "main",
            remainingPercent: 68,
            totalPercent: 100
        ),
    ]
) -> QuotaSummary {
    QuotaSummary(trayPercentage: 68, rows: rows)
}

func makeClaudeSummary(
    rows: [ClaudeAccountAllowance] = [
        ClaudeAccountAllowance(
            accountId: "claude-work",
            label: "work",
            fiveHourRemainingPercent: 97,
            weeklyRemainingPercent: 88
        ),
    ]
) -> ClaudeQuotaSummary {
    ClaudeQuotaSummary(
        fiveHourRemainingPercentage: 97,
        weeklyRemainingPercentage: 88,
        rows: rows
    )
}

func makeSnapshot(
    codex: QuotaSummary?,
    codexError: String? = nil,
    claude: ClaudeQuotaSummary?,
    claudeError: String? = nil,
    fetchedAt: Date = widgetTestDate
) -> QuotaSnapshot {
    QuotaSnapshot(
        fetchedAt: fetchedAt,
        codexSummary: codex,
        codexErrorMessage: codexError,
        claudeSummary: claude,
        claudeErrorMessage: claudeError
    )
}

func makeCompleteSnapshot() -> QuotaSnapshot {
    makeSnapshot(codex: makeCodexSummary(), claude: makeClaudeSummary())
}

func makeCompleteLoad() -> QuotaSnapshotLoad {
    QuotaSnapshotLoad(snapshot: makeCompleteSnapshot(), codexAccounts: [])
}

actor FakeSnapshotLoader: QuotaSnapshotLoading {
    let result: QuotaSnapshotLoad
    init(result: QuotaSnapshotLoad) { self.result = result }
    func load() async -> QuotaSnapshotLoad { result }
}

actor FakeWidgetCache: WidgetSnapshotCaching {
    private var snapshot: QuotaSnapshot?
    private var savedSnapshots: [QuotaSnapshot] = []

    init(snapshot: QuotaSnapshot? = nil) {
        self.snapshot = snapshot
    }

    func load() async -> QuotaSnapshot? { snapshot }

    func save(_ snapshot: QuotaSnapshot) async throws {
        self.snapshot = snapshot
        savedSnapshots.append(snapshot)
    }

    func saves() -> [QuotaSnapshot] { savedSnapshots }
}
```

Then write:

```swift
func testCompleteLoadDisplaysLiveAndRequestsCacheReplacement() {
    let snapshot = makeCompleteSnapshot()
    let load = QuotaSnapshotLoad(snapshot: snapshot, codexAccounts: [])

    let result = QuotaWidgetStateResolver.resolve(load: load, cached: nil)

    XCTAssertEqual(result.content, .snapshot(snapshot, stale: false))
    XCTAssertEqual(result.snapshotToCache, snapshot)
}

func testPartialLoadDisplaysUnavailableProviderAndPreservesCache() {
    let cached = makeCompleteSnapshot()
    let partial = makeSnapshot(
        codex: makeCodexSummary(),
        codexError: nil,
        claude: nil,
        claudeError: "Claude unavailable"
    )

    let result = QuotaWidgetStateResolver.resolve(
        load: QuotaSnapshotLoad(snapshot: partial, codexAccounts: []),
        cached: cached
    )

    XCTAssertEqual(result.content, .snapshot(partial, stale: false))
    XCTAssertNil(result.snapshotToCache)
}

func testTotalFailureUsesStaleCache() {
    let cached = makeCompleteSnapshot()
    let failed = makeSnapshot(
        codex: nil,
        codexError: "Codex unavailable",
        claude: nil,
        claudeError: "Claude unavailable"
    )

    let result = QuotaWidgetStateResolver.resolve(
        load: QuotaSnapshotLoad(snapshot: failed, codexAccounts: nil),
        cached: cached
    )

    XCTAssertEqual(result.content, .snapshot(cached, stale: true))
    XCTAssertNil(result.snapshotToCache)
}

func testTotalFailureWithoutCacheIsUnavailable() {
    let failed = makeSnapshot(
        codex: nil,
        codexError: "Codex unavailable",
        claude: nil,
        claudeError: "Claude unavailable"
    )

    XCTAssertEqual(
        QuotaWidgetStateResolver.resolve(
            load: QuotaSnapshotLoad(snapshot: failed, codexAccounts: nil),
            cached: nil
        ).content,
        .unavailable
    )
}

func testConfigurationFailureWithoutCacheIsUnavailable() {
    XCTAssertEqual(
        QuotaWidgetStateResolver.resolve(load: nil, cached: nil).content,
        .unavailable
    )
}
```

- [ ] **Step 2: Run state tests and verify red state**

Run:

```bash
xcodebuild test \
  -project OpenCodexTray.xcodeproj \
  -scheme OpenCodexTray \
  -destination "platform=macOS" \
  -only-testing:OpenCodexWidgetTests/QuotaWidgetStateTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: compile failure containing `cannot find 'QuotaWidgetStateResolver' in scope`.

- [ ] **Step 3: Implement exact state types**

Start `QuotaWidgetState.swift` with `import Foundation` and `import PauseWorkerCore`, then add:

```swift
enum QuotaWidgetContent: Equatable, Sendable {
    case snapshot(QuotaSnapshot, stale: Bool)
    case unavailable
}

struct QuotaWidgetResolution: Equatable, Sendable {
    let content: QuotaWidgetContent
    let snapshotToCache: QuotaSnapshot?
}

enum QuotaWidgetStateResolver {
    static func resolve(
        load: QuotaSnapshotLoad?,
        cached: QuotaSnapshot?
    ) -> QuotaWidgetResolution {
        guard let snapshot = load?.snapshot, snapshot.hasProviderData else {
            return QuotaWidgetResolution(
                content: cached.map { .snapshot($0, stale: true) } ?? .unavailable,
                snapshotToCache: nil
            )
        }
        return QuotaWidgetResolution(
            content: .snapshot(snapshot, stale: false),
            snapshotToCache: snapshot.isComplete ? snapshot : nil
        )
    }
}
```

- [ ] **Step 4: Write failing atomic-cache tests**

Use a test-owned temporary directory and exact cache URL:

```swift
private var temporaryDirectory: URL!

override func setUpWithError() throws {
    temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: temporaryDirectory,
        withIntermediateDirectories: true
    )
}

override func tearDownWithError() throws {
    try FileManager.default.removeItem(at: temporaryDirectory)
    temporaryDirectory = nil
}

func testSaveThenLoadRoundTripsCompleteSnapshot() async throws {
    let cache = WidgetSnapshotCache(fileURL: temporaryDirectory.appendingPathComponent("quota.json"))
    let snapshot = makeCompleteSnapshot()

    try await cache.save(snapshot)
    let loaded = await cache.load()

    XCTAssertEqual(loaded, snapshot)
}

func testCorruptCacheIsMiss() async throws {
    let url = temporaryDirectory.appendingPathComponent("quota.json")
    try Data("not json".utf8).write(to: url)
    let cache = WidgetSnapshotCache(fileURL: url)
    let loaded = await cache.load()

    XCTAssertNil(loaded)
}
```

- [ ] **Step 5: Run cache tests and verify red state**

Run:

```bash
xcodebuild test \
  -project OpenCodexTray.xcodeproj \
  -scheme OpenCodexTray \
  -destination "platform=macOS" \
  -only-testing:OpenCodexWidgetTests/WidgetSnapshotCacheTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: compile failure containing `cannot find 'WidgetSnapshotCache' in scope`.

- [ ] **Step 6: Implement extension-local JSON cache**

Start `WidgetSnapshotCache.swift` with `import Foundation` and `import PauseWorkerCore`, then add:

```swift
protocol WidgetSnapshotCaching: Sendable {
    func load() async -> QuotaSnapshot?
    func save(_ snapshot: QuotaSnapshot) async throws
}

actor WidgetSnapshotCache: WidgetSnapshotCaching {
    private let fileURL: URL

    init(fileURL: URL = Self.defaultFileURL()) {
        self.fileURL = fileURL
    }

    func load() async -> QuotaSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(QuotaSnapshot.self, from: data)
    }

    func save(_ snapshot: QuotaSnapshot) async throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
    }

    private static func defaultFileURL() -> URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent("OpenCodexWidget", isDirectory: true)
        .appendingPathComponent("quota-snapshot.json")
    }
}
```

The cache must not read or write config/token paths.

- [ ] **Step 7: Run widget and core tests**

Run:

```bash
xcodebuild test -project OpenCodexTray.xcodeproj -scheme OpenCodexTray -destination "platform=macOS" -only-testing:OpenCodexWidgetTests CODE_SIGNING_ALLOWED=NO
swift test
```

Expected: both commands exit 0.

- [ ] **Step 8: Review and commit**

```bash
git add Sources/OpenCodexWidget/QuotaWidgetState.swift Sources/OpenCodexWidget/WidgetSnapshotCache.swift tests/OpenCodexWidgetTests/WidgetTestFixtures.swift tests/OpenCodexWidgetTests/QuotaWidgetStateTests.swift tests/OpenCodexWidgetTests/WidgetSnapshotCacheTests.swift OpenCodexTray.xcodeproj/project.pbxproj
git diff --cached --check
git commit -m "feat: add widget snapshot state and cache"
```

### Task 6: Add Production Timeline Loading

**Files:**
- Create: `Sources/OpenCodexWidget/QuotaWidgetTimelineProvider.swift`
- Create: `tests/OpenCodexWidgetTests/QuotaWidgetTimelineTests.swift`
- Modify: `Sources/OpenCodexWidget/OpenCodexWidgetBundle.swift`
- Modify: `OpenCodexTray.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `QuotaSnapshotLoading`, `WidgetSnapshotCaching`, and `QuotaWidgetStateResolver`.
- Produces: `QuotaWidgetEntry: TimelineEntry`.
- Produces: testable `QuotaWidgetTimelineService.makeEntry()` with `nextRefresh` exactly 30 minutes after entry date.
- Produces: `QuotaWidgetTimelineProvider` with production config/token loader factory.

- [ ] **Step 1: Write failing timeline-service tests**

Add `QuotaWidgetTimelineProvider.swift` to both widget and widget-test target membership. Cover complete load/cache save, partial load/cache preservation, loader-factory failure, stale fallback, and exact refresh interval:

```swift
func testNextRefreshIsThirtyMinutesAfterEntryDate() async {
    let now = Date(timeIntervalSince1970: 1_788_231_600)
    let service = QuotaWidgetTimelineService(
        makeLoader: { FakeSnapshotLoader(result: makeCompleteLoad()) },
        cache: FakeWidgetCache(),
        now: { now }
    )

    let result = await service.makeEntry()

    XCTAssertEqual(result.entry.date, now)
    XCTAssertEqual(result.nextRefresh, now.addingTimeInterval(30 * 60))
}

func testFactoryFailureUsesCachedSnapshotAsStale() async {
    let cached = makeCompleteSnapshot()
    let service = QuotaWidgetTimelineService(
        makeLoader: { throw ConfigurationError.invalid("Config unavailable") },
        cache: FakeWidgetCache(snapshot: cached),
        now: { widgetTestDate }
    )

    let result = await service.makeEntry()

    XCTAssertEqual(result.entry.content, .snapshot(cached, stale: true))
}

func testCompleteLoadWritesLastCompleteCache() async {
    let snapshot = makeCompleteSnapshot()
    let cache = FakeWidgetCache()
    let service = QuotaWidgetTimelineService(
        makeLoader: {
            FakeSnapshotLoader(
                result: QuotaSnapshotLoad(snapshot: snapshot, codexAccounts: [])
            )
        },
        cache: cache,
        now: { widgetTestDate }
    )

    let result = await service.makeEntry()
    let saves = await cache.saves()

    XCTAssertEqual(result.entry.content, .snapshot(snapshot, stale: false))
    XCTAssertEqual(saves, [snapshot])
}

func testPartialLoadDoesNotReplaceLastCompleteCache() async {
    let cached = makeCompleteSnapshot()
    let partial = makeSnapshot(
        codex: makeCodexSummary(),
        claude: nil,
        claudeError: "Claude unavailable"
    )
    let cache = FakeWidgetCache(snapshot: cached)
    let service = QuotaWidgetTimelineService(
        makeLoader: {
            FakeSnapshotLoader(
                result: QuotaSnapshotLoad(snapshot: partial, codexAccounts: [])
            )
        },
        cache: cache,
        now: { widgetTestDate }
    )

    let result = await service.makeEntry()
    let saves = await cache.saves()

    XCTAssertEqual(result.entry.content, .snapshot(partial, stale: false))
    XCTAssertEqual(saves, [])
}
```

- [ ] **Step 2: Run timeline tests and verify red state**

Run:

```bash
xcodebuild test \
  -project OpenCodexTray.xcodeproj \
  -scheme OpenCodexTray \
  -destination "platform=macOS" \
  -only-testing:OpenCodexWidgetTests/QuotaWidgetTimelineTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: compile failure containing `cannot find 'QuotaWidgetTimelineService' in scope`.

- [ ] **Step 3: Implement timeline service and entry**

Start `QuotaWidgetTimelineProvider.swift` with `import Foundation`, `import PauseWorkerCore`, and `import WidgetKit`. Use exact result shapes:

```swift
struct QuotaWidgetEntry: TimelineEntry, Equatable {
    let date: Date
    let content: QuotaWidgetContent
    let isPlaceholder: Bool
}

struct QuotaWidgetTimelineResult: Equatable {
    let entry: QuotaWidgetEntry
    let nextRefresh: Date
}

struct QuotaWidgetTimelineService {
    let makeLoader: @Sendable () throws -> any QuotaSnapshotLoading
    let cache: any WidgetSnapshotCaching
    let now: @Sendable () -> Date

    func makeEntry() async -> QuotaWidgetTimelineResult {
        let date = now()
        let cached = await cache.load()
        let load: QuotaSnapshotLoad?
        do {
            let loader = try makeLoader()
            load = await loader.load()
        } catch {
            load = nil
        }
        let resolution = QuotaWidgetStateResolver.resolve(load: load, cached: cached)
        if let snapshot = resolution.snapshotToCache {
            try? await cache.save(snapshot)
        }
        return QuotaWidgetTimelineResult(
            entry: QuotaWidgetEntry(date: date, content: resolution.content, isPlaceholder: false),
            nextRefresh: date.addingTimeInterval(30 * 60)
        )
    }
}
```

Do not replace cache when `save` fails; still return live content.

- [ ] **Step 4: Implement production loader factory and TimelineProvider**

Give `QuotaWidgetTimelineProvider` two initializers: production `init()` creates one `WidgetSnapshotCache` and passes that same actor to both the service and provider; internal `init(service:cache:)` accepts test doubles. Production factory is:

```swift
private static func makeProductionLoader() throws -> any QuotaSnapshotLoading {
    let config = try WorkerConfiguration.load(
        environment: ProcessInfo.processInfo.environment
    )
    let token = try AdminTokenReader.read(path: config.adminTokenPath)
    let client = OpenCodexQuotaClient(
        baseURL: config.baseURL,
        adminToken: token,
        timeout: config.requestTimeout
    )
    return QuotaSnapshotLoader(
        client: client,
        targetAlias: config.targetAlias,
        thresholdPercent: config.thresholdPercent
    )
}
```

Use this exact injection and preview boundary:

```swift
private let service: QuotaWidgetTimelineService
private let cache: any WidgetSnapshotCaching

init() {
    let cache = WidgetSnapshotCache()
    self.init(
        service: QuotaWidgetTimelineService(
            makeLoader: { try Self.makeProductionLoader() },
            cache: cache,
            now: { Date() }
        ),
        cache: cache
    )
}

init(service: QuotaWidgetTimelineService, cache: any WidgetSnapshotCaching) {
    self.service = service
    self.cache = cache
}

static func placeholderEntry(at date: Date) -> QuotaWidgetEntry {
    let snapshot = QuotaSnapshot(
        fetchedAt: date,
        codexSummary: QuotaSummary(
            trayPercentage: 68,
            rows: [
                AccountAllowance(
                    accountId: "codex-main",
                    label: "main",
                    remainingPercent: 68,
                    totalPercent: 100
                ),
            ]
        ),
        codexErrorMessage: nil,
        claudeSummary: ClaudeQuotaSummary(
            fiveHourRemainingPercentage: 97,
            weeklyRemainingPercentage: 88,
            rows: [
                ClaudeAccountAllowance(
                    accountId: "claude-work",
                    label: "work",
                    fiveHourRemainingPercent: 97,
                    weeklyRemainingPercent: 88
                ),
            ]
        ),
        claudeErrorMessage: nil
    )
    return QuotaWidgetEntry(
        date: date,
        content: .snapshot(snapshot, stale: false),
        isPlaceholder: true
    )
}

func snapshotEntry(at date: Date) async -> QuotaWidgetEntry {
    guard let cached = await cache.load() else {
        return Self.placeholderEntry(at: date)
    }
    return QuotaWidgetEntry(
        date: date,
        content: .snapshot(cached, stale: true),
        isPlaceholder: false
    )
}
```

`placeholder(in:)` returns `Self.placeholderEntry(at: .now)` directly and never creates a loader. `getSnapshot` calls only `snapshotEntry`; it never calls the live service. `getTimeline` starts a `Task`, calls the service, and returns one entry with `.after(result.nextRefresh)`.

Add these gallery-path tests:

```swift
func testGallerySnapshotUsesCachedDataAsStale() async {
    let cached = makeCompleteSnapshot()
    let cache = FakeWidgetCache(snapshot: cached)
    let provider = QuotaWidgetTimelineProvider(
        service: QuotaWidgetTimelineService(
            makeLoader: { throw ConfigurationError.invalid("must not run") },
            cache: cache,
            now: { widgetTestDate }
        ),
        cache: cache
    )

    let entry = await provider.snapshotEntry(at: widgetTestDate)

    XCTAssertEqual(entry.content, .snapshot(cached, stale: true))
    XCTAssertFalse(entry.isPlaceholder)
}

func testGallerySnapshotWithoutCacheUsesStaticPlaceholder() async {
    let cache = FakeWidgetCache()
    let provider = QuotaWidgetTimelineProvider(
        service: QuotaWidgetTimelineService(
            makeLoader: { throw ConfigurationError.invalid("must not run") },
            cache: cache,
            now: { widgetTestDate }
        ),
        cache: cache
    )

    let entry = await provider.snapshotEntry(at: widgetTestDate)

    XCTAssertTrue(entry.isPlaceholder)
    guard case let .snapshot(snapshot, stale) = entry.content else {
        return XCTFail("Expected representative placeholder snapshot")
    }
    XCTAssertFalse(stale)
    XCTAssertEqual(snapshot.codexSummary?.trayPercentage, 68)
    XCTAssertEqual(snapshot.claudeSummary?.fiveHourRemainingPercentage, 97)
    XCTAssertEqual(snapshot.claudeSummary?.weeklyRemainingPercentage, 88)
}
```

- [ ] **Step 5: Replace wiring provider in widget bundle**

Keep kind string `OpenCodexQuota` and replace `WiringProvider` with `QuotaWidgetTimelineProvider`. For this task, render a compile-only text view that switches between `OpenCodex Quota` and `Unable to load`; Task 7 adds final layouts.

- [ ] **Step 6: Run timeline, project, and core checks**

Run:

```bash
xcodebuild test -project OpenCodexTray.xcodeproj -scheme OpenCodexTray -destination "platform=macOS" -only-testing:OpenCodexWidgetTests CODE_SIGNING_ALLOWED=NO
./tests/xcode-project-tests.sh
swift test
```

Expected: all commands exit 0.

- [ ] **Step 7: Review and commit**

```bash
git add Sources/OpenCodexWidget/QuotaWidgetTimelineProvider.swift Sources/OpenCodexWidget/OpenCodexWidgetBundle.swift tests/OpenCodexWidgetTests/QuotaWidgetTimelineTests.swift OpenCodexTray.xcodeproj/project.pbxproj
git diff --cached --check
git commit -m "feat: add widget quota timeline"
```

### Task 7: Build Provider-Split Small and Medium Views

**Files:**
- Modify: `Sources/PauseWorkerCore/DisplayFormatter.swift`
- Modify: `tests/PauseWorkerCoreTests/DisplayFormatterTests.swift`
- Modify: `Sources/OpenCodexWidget/QuotaWidgetState.swift`
- Create: `Sources/OpenCodexWidget/QuotaWidgetView.swift`
- Modify: `Sources/OpenCodexWidget/OpenCodexWidgetBundle.swift`
- Modify: `Sources/OpenCodexTray/OpenCodexTrayApp.swift`
- Modify: `tests/OpenCodexWidgetTests/QuotaWidgetStateTests.swift`
- Modify: `tests/OpenCodexWidgetTests/WidgetTestFixtures.swift`
- Modify: `OpenCodexTray.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `DisplayFormatter.codexAllowance(_:)` and `claudeAllowance(_:)` for value-only rows.
- Produces: `QuotaWidgetViewModel` with provider totals, at most two rows, overflow counts, timestamp, and stale state.
- Produces: `QuotaWidgetView` with approved provider-split layouts.
- Preserves: SwiftPM provider resource verification and Xcode main-bundle loading.

- [ ] **Step 1: Write failing formatter and view-model tests**

Add formatter assertions:

```swift
func testFormatsWidgetValuesWithoutLabelsAndKeepsUnknownAsDash() {
    XCTAssertEqual(DisplayFormatter.codexAllowance(AccountAllowance(
        accountId: "codex-a",
        label: "main",
        remainingPercent: 68,
        totalPercent: 100
    )), "68% / 100%")
    XCTAssertEqual(DisplayFormatter.codexAllowance(AccountAllowance(
        accountId: "codex-b",
        label: "workmate",
        remainingPercent: nil,
        totalPercent: 17.5
    )), "— / 17.5%")
    XCTAssertEqual(DisplayFormatter.claudeAllowance(ClaudeAccountAllowance(
        accountId: "claude-a",
        label: "work",
        fiveHourRemainingPercent: 97,
        weeklyRemainingPercent: 88
    )), "97% / 88%")
}
```

Add the two fixture builders below to `WidgetTestFixtures.swift`, then add the view-model assertions to `QuotaWidgetStateTests.swift`:

```swift
func makeThreeAccountSnapshot() -> QuotaSnapshot {
    let codexRows = [
        AccountAllowance(accountId: "codex-main", label: "main", remainingPercent: 68, totalPercent: 100),
        AccountAllowance(accountId: "codex-work", label: "workmate", remainingPercent: 16, totalPercent: 17.5),
        AccountAllowance(accountId: "codex-third", label: "third", remainingPercent: 10, totalPercent: 25),
    ]
    let claudeRows = [
        ClaudeAccountAllowance(accountId: "claude-work", label: "work", fiveHourRemainingPercent: 97, weeklyRemainingPercent: 88),
        ClaudeAccountAllowance(accountId: "claude-personal", label: "personal", fiveHourRemainingPercent: 94, weeklyRemainingPercent: 88),
        ClaudeAccountAllowance(accountId: "claude-third", label: "third", fiveHourRemainingPercent: 90, weeklyRemainingPercent: 80),
    ]
    return makeSnapshot(
        codex: QuotaSummary(trayPercentage: 94, rows: codexRows),
        claude: ClaudeQuotaSummary(
            fiveHourRemainingPercentage: 281,
            weeklyRemainingPercentage: 256,
            rows: claudeRows
        )
    )
}

func makeCodexOnlySnapshot() -> QuotaSnapshot {
    makeSnapshot(
        codex: makeCodexSummary(),
        claude: nil,
        claudeError: "Claude unavailable"
    )
}

func testMediumModelCapsRowsAtTwoAndReportsOverflow() {
    let model = QuotaWidgetViewModel(content: .snapshot(makeThreeAccountSnapshot(), stale: false))

    XCTAssertEqual(model.claude.total, "281%/256%")
    XCTAssertEqual(model.claude.rows.map(\.label), ["work", "personal"])
    XCTAssertEqual(model.claude.rows.map(\.value), ["97% / 88%", "94% / 88%"])
    XCTAssertEqual(model.claude.overflowCount, 1)
    XCTAssertEqual(model.codex.total, "94%")
    XCTAssertEqual(model.codex.rows.map(\.label), ["main", "workmate"])
    XCTAssertEqual(model.codex.rows.map(\.value), ["68% / 100%", "16% / 17.5%"])
    XCTAssertEqual(model.codex.overflowCount, 1)
}

func testPartialModelMarksOnlyMissingProviderUnavailable() {
    let model = QuotaWidgetViewModel(content: .snapshot(makeCodexOnlySnapshot(), stale: false))

    XCTAssertFalse(model.codex.isUnavailable)
    XCTAssertTrue(model.claude.isUnavailable)
}

func testSnapshotModelPreservesTimestampAndStaleMarker() {
    let snapshot = makeCompleteSnapshot()

    let model = QuotaWidgetViewModel(content: .snapshot(snapshot, stale: true))

    XCTAssertEqual(model.updatedAt, widgetTestDate)
    XCTAssertTrue(model.isStale)
    XCTAssertFalse(model.isUnavailable)
}

func testUnavailableModelHasNoTimestampOrRows() {
    let model = QuotaWidgetViewModel(content: .unavailable)

    XCTAssertNil(model.updatedAt)
    XCTAssertTrue(model.isUnavailable)
    XCTAssertTrue(model.codex.rows.isEmpty)
    XCTAssertTrue(model.claude.rows.isEmpty)
}
```

- [ ] **Step 2: Run focused tests and verify red state**

Run:

```bash
swift test --filter DisplayFormatterTests
xcodebuild test \
  -project OpenCodexTray.xcodeproj \
  -scheme OpenCodexTray \
  -destination "platform=macOS" \
  -only-testing:OpenCodexWidgetTests/QuotaWidgetStateTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: compile failures for missing formatter methods and `QuotaWidgetViewModel`.

- [ ] **Step 3: Implement shared value formatting**

Keep existing tray/dropdown methods unchanged and add:

```swift
public static func codexAllowance(_ allowance: AccountAllowance) -> String {
    "\(percentage(allowance.remainingPercent)) / \(percentage(allowance.totalPercent))"
}

public static func claudeAllowance(_ allowance: ClaudeAccountAllowance) -> String {
    "\(percentage(allowance.fiveHourRemainingPercent)) / \(percentage(allowance.weeklyRemainingPercent))"
}
```

Both helpers return `—` without a percent sign when input is nil.

- [ ] **Step 4: Implement bounded widget view model**

Use focused internal models:

```swift
struct QuotaWidgetRowModel: Equatable, Identifiable {
    let id: String
    let label: String
    let value: String
}

struct QuotaWidgetProviderModel: Equatable {
    let total: String
    let rows: [QuotaWidgetRowModel]
    let overflowCount: Int
    let isUnavailable: Bool
}

struct QuotaWidgetViewModel: Equatable {
    let codex: QuotaWidgetProviderModel
    let claude: QuotaWidgetProviderModel
    let updatedAt: Date?
    let isStale: Bool
    let isUnavailable: Bool

    init(content: QuotaWidgetContent) {
        switch content {
        case .unavailable:
            codex = Self.unavailableProvider
            claude = Self.unavailableProvider
            updatedAt = nil
            isStale = false
            isUnavailable = true
        case let .snapshot(snapshot, stale):
            codex = snapshot.codexSummary.map(Self.codexProvider) ?? Self.unavailableProvider
            claude = snapshot.claudeSummary.map(Self.claudeProvider) ?? Self.unavailableProvider
            updatedAt = snapshot.fetchedAt
            isStale = stale
            isUnavailable = false
        }
    }

    private static let unavailableProvider = QuotaWidgetProviderModel(
        total: "Unavailable",
        rows: [],
        overflowCount: 0,
        isUnavailable: true
    )

    private static func codexProvider(_ summary: QuotaSummary) -> QuotaWidgetProviderModel {
        QuotaWidgetProviderModel(
            total: DisplayFormatter.trayTitle(summary.trayPercentage),
            rows: summary.rows.prefix(2).map {
                QuotaWidgetRowModel(
                    id: $0.id,
                    label: $0.label,
                    value: DisplayFormatter.codexAllowance($0)
                )
            },
            overflowCount: max(summary.rows.count - 2, 0),
            isUnavailable: false
        )
    }

    private static func claudeProvider(_ summary: ClaudeQuotaSummary) -> QuotaWidgetProviderModel {
        QuotaWidgetProviderModel(
            total: DisplayFormatter.claudeTrayTitle(summary),
            rows: summary.rows.prefix(2).map {
                QuotaWidgetRowModel(
                    id: $0.id,
                    label: $0.label,
                    value: DisplayFormatter.claudeAllowance($0)
                )
            },
            overflowCount: max(summary.rows.count - 2, 0),
            isUnavailable: false
        )
    }
}
```

This preserves API order, caps rows at two, and keeps partial-provider failure distinct from global unavailability.

- [ ] **Step 5: Implement provider icons and approved SwiftUI layouts**

Start `QuotaWidgetView.swift` with `import AppKit`, `import PauseWorkerCore`, `import SwiftUI`, and `import WidgetKit`. `QuotaWidgetView` reads `widgetFamily`:

```swift
@Environment(\.widgetFamily) private var family

var body: some View {
    Group {
        switch family {
        case .systemMedium:
            mediumLayout
        default:
            smallLayout
        }
    }
    .containerBackground(for: .widget) {
        Color(nsColor: .windowBackgroundColor)
    }
}
```

Small layout contains title, a Claude icon/name row with `5h / 1w` and aggregate, a Codex icon/name row with aggregate, and relative update age. Medium layout contains title/update age and an `HStack` of Claude and Codex columns; apply `.frame(maxWidth: .infinity, alignment: .leading)` to each column. Each column renders provider icon/name, aggregate, two label/value rows, and `+N more` when overflow is positive. Render age with `Text(updatedAt, style: .relative)` so it reflects actual snapshot time. Add `Stale` beside age when `isStale`. Render only `Unable to load` when global state is unavailable.

Load `ProviderIcon-claude.svg` and `ProviderIcon-codex.svg` from `Bundle.main` using `NSImage(contentsOf:)`; use `Text("C")` and `Text("O")` fallback marks when a resource cannot decode. Hide decorative icons from accessibility. Apply `.monospacedDigit()` to all quota values and accessibility labels that name provider and value.

- [ ] **Step 6: Wire final widget configuration**

`OpenCodexWidgetBundle` renders `QuotaWidgetView(entry:)` and keeps:

```swift
.configurationDisplayName("OpenCodex Quota")
.description("Codex and Claude quota remaining.")
.supportedFamilies([.systemSmall, .systemMedium])
```

Add `QuotaWidgetView.swift` to widget target only. Keep `QuotaWidgetState.swift` in widget and widget-test targets.

- [ ] **Step 7: Preserve app resource loading in both build systems**

In `ProviderIconStore.resourceBundle`, keep SwiftPM generated-bundle lookup first, then return `Bundle.main` when provider SVGs are direct Xcode app resources. `--verify-resources` must still pass for both the SwiftPM executable and Xcode app.

- [ ] **Step 8: Run focused and complete UI/build checks**

Run:

```bash
swift test --filter DisplayFormatterTests
xcodebuild test -project OpenCodexTray.xcodeproj -scheme OpenCodexTray -destination "platform=macOS" -only-testing:OpenCodexWidgetTests CODE_SIGNING_ALLOWED=NO
./tests/xcode-project-tests.sh
swift test
```

Expected: all commands exit 0.

- [ ] **Step 9: Review and commit**

```bash
git add Sources/PauseWorkerCore/DisplayFormatter.swift tests/PauseWorkerCoreTests/DisplayFormatterTests.swift Sources/OpenCodexWidget/QuotaWidgetState.swift Sources/OpenCodexWidget/QuotaWidgetView.swift Sources/OpenCodexWidget/OpenCodexWidgetBundle.swift Sources/OpenCodexTray/OpenCodexTrayApp.swift tests/OpenCodexWidgetTests/WidgetTestFixtures.swift tests/OpenCodexWidgetTests/QuotaWidgetStateTests.swift OpenCodexTray.xcodeproj/project.pbxproj
git diff --cached --check
git commit -m "feat: add provider-split quota widget views"
```

### Task 8: Migrate Offline Build and Nested Signing

**Files:**
- Modify: `scripts/build-app.sh`
- Modify: `tests/build-app-tests.sh`
- Modify: `tests/release-artifact-tests.sh`

**Interfaces:**
- Consumes: checked-in `OpenCodexTray.xcodeproj` and `OpenCodexTray` scheme.
- Produces: `dist/OpenCodexTray.app` with embedded `OpenCodexWidget.appex`.
- Preserves: `NOTARIZE`, `SIGNING_IDENTITY`, `NOTARY_PROFILE`, data-only `.env` parsing, archive cleanup, notarization, stapling, assessment, and final ZIP.

- [ ] **Step 1: Convert build fixture to a fake Xcode product**

In `make_fixture`, copy `OpenCodexTray.xcodeproj` recursively and `Resources/OpenCodexWidget.entitlements` into the test root. Replace fake `swift` with this fake `xcodebuild`; it records all arguments, finds the exact DerivedData path, creates executable app/extension binaries, and writes valid bundle identifiers:

```zsh
cat > "$TEST_ROOT/fake-bin/xcodebuild" <<'EOF'
#!/bin/zsh
set -euo pipefail
print -r -- "xcodebuild|$*" >> "$COMMAND_LOG"
if [[ "${FAKE_XCODEBUILD_FAIL:-0}" == "1" ]]; then
  exit 42
fi

derived_data=""
while (( $# > 0 )); do
  if [[ "$1" == "-derivedDataPath" ]]; then
    shift
    derived_data="$1"
    break
  fi
  shift
done
[[ -n "$derived_data" ]] || exit 64

app="$derived_data/Build/Products/Release/OpenCodexTray.app"
widget="$app/Contents/PlugIns/OpenCodexWidget.appex"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$widget/Contents/MacOS" "$widget/Contents/Resources"
touch "$app/Contents/MacOS/OpenCodexTray" "$widget/Contents/MacOS/OpenCodexWidget"
chmod 755 "$app/Contents/MacOS/OpenCodexTray" "$widget/Contents/MacOS/OpenCodexWidget"
cp "$FIXTURE_ROOT/Resources/Info.plist" "$app/Contents/Info.plist"
cp "$FIXTURE_ROOT/Resources/OpenCodexWidget-Info.plist" "$widget/Contents/Info.plist"
cp "$FIXTURE_ROOT/Sources/OpenCodexTray/Resources/ProviderIcon-claude.svg" "$app/Contents/Resources/"
cp "$FIXTURE_ROOT/Sources/OpenCodexTray/Resources/ProviderIcon-codex.svg" "$app/Contents/Resources/"
cp "$FIXTURE_ROOT/Sources/OpenCodexTray/Resources/CodexBar-LICENSE.txt" "$app/Contents/Resources/"
cp "$FIXTURE_ROOT/Sources/OpenCodexTray/Resources/ProviderIcon-claude.svg" "$widget/Contents/Resources/"
cp "$FIXTURE_ROOT/Sources/OpenCodexTray/Resources/ProviderIcon-codex.svg" "$widget/Contents/Resources/"
cp "$FIXTURE_ROOT/Sources/OpenCodexTray/Resources/CodexBar-LICENSE.txt" "$widget/Contents/Resources/"
EOF
```

Replace the fixture setup copies with:

```zsh
mkdir -p \
  "$TEST_ROOT/Resources" \
  "$TEST_ROOT/Sources/OpenCodexTray/Resources"
cp -R "$PROJECT_ROOT/OpenCodexTray.xcodeproj" "$TEST_ROOT/OpenCodexTray.xcodeproj"
cp "$PROJECT_ROOT/Resources/Info.plist" "$TEST_ROOT/Resources/Info.plist"
cp "$PROJECT_ROOT/Resources/OpenCodexWidget-Info.plist" "$TEST_ROOT/Resources/OpenCodexWidget-Info.plist"
cp "$PROJECT_ROOT/Resources/OpenCodexWidget.entitlements" "$TEST_ROOT/Resources/OpenCodexWidget.entitlements"
cp "$PROJECT_ROOT/Sources/OpenCodexTray/Resources/ProviderIcon-claude.svg" "$TEST_ROOT/Sources/OpenCodexTray/Resources/"
cp "$PROJECT_ROOT/Sources/OpenCodexTray/Resources/ProviderIcon-codex.svg" "$TEST_ROOT/Sources/OpenCodexTray/Resources/"
cp "$PROJECT_ROOT/Sources/OpenCodexTray/Resources/CodexBar-LICENSE.txt" "$TEST_ROOT/Sources/OpenCodexTray/Resources/"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier local.opencodex.quota-tray.widget" "$TEST_ROOT/Resources/OpenCodexWidget-Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable OpenCodexWidget" "$TEST_ROOT/Resources/OpenCodexWidget-Info.plist"
```

The resulting fake product tree is:

```text
Build/Products/Release/OpenCodexTray.app/
  Contents/
    Info.plist
    MacOS/OpenCodexTray
    PlugIns/OpenCodexWidget.appex/
      Contents/
        Info.plist
        MacOS/OpenCodexWidget
        Resources/
          CodexBar-LICENSE.txt
          ProviderIcon-claude.svg
          ProviderIcon-codex.svg
    Resources/
      CodexBar-LICENSE.txt
      ProviderIcon-claude.svg
      ProviderIcon-codex.svg
```

Pass `FIXTURE_ROOT="$TEST_ROOT"` from `run_build`. Remove `FAKE_SWIFT_BIN` and all fake-Swift setup.

- [ ] **Step 2: Add failing local nested-sign tests**

Update local build assertions:

```zsh
assert_contains "$command_log" "xcodebuild|-project $TEST_ROOT/OpenCodexTray.xcodeproj"
assert_contains "$command_log" "-disableAutomaticPackageResolution"
assert_contains "$command_log" "codesign|--force --sign - --entitlements $TEST_ROOT/Resources/OpenCodexWidget.entitlements $TEST_ROOT/dist/OpenCodexTray.app/Contents/PlugIns/OpenCodexWidget.appex"
assert_contains "$command_log" "codesign|--force --sign - $TEST_ROOT/dist/OpenCodexTray.app"
assert_not_contains "$command_log" "notarytool"
```

Add this helper and exact order assertion:

```zsh
assert_before() {
  local first="$1"
  local second="$2"
  local first_line="$(grep -nF -- "$first" "$TEST_ROOT/commands.log" | head -1 | cut -d: -f1)"
  local second_line="$(grep -nF -- "$second" "$TEST_ROOT/commands.log" | head -1 | cut -d: -f1)"
  [[ -n "$first_line" ]] || fail "missing earlier command: $first"
  [[ -n "$second_line" ]] || fail "missing later command: $second"
  (( first_line < second_line )) || fail "command order invalid: $first must precede $second"
}

local widget_sign="codesign|--force --sign - --entitlements $TEST_ROOT/Resources/OpenCodexWidget.entitlements $TEST_ROOT/dist/OpenCodexTray.app/Contents/PlugIns/OpenCodexWidget.appex"
local app_sign="codesign|--force --sign - $TEST_ROOT/dist/OpenCodexTray.app"
assert_before "$widget_sign" "$app_sign"
```

- [ ] **Step 3: Run build tests and verify red state**

Run:

```bash
./tests/build-app-tests.sh
```

Expected: failure because current script invokes `swift build` and never signs an extension.

- [ ] **Step 4: Replace manual SwiftPM app assembly with offline Xcode build**

Preserve existing config parsing, release guards, and archive trap. Replace app assembly with:

```zsh
DERIVED_DATA="$ROOT/.build/xcode-derived-data"
PRODUCT_APP="$DERIVED_DATA/Build/Products/Release/OpenCodexTray.app"
WIDGET="$APP/Contents/PlugIns/OpenCodexWidget.appex"
WIDGET_ENTITLEMENTS="$ROOT/Resources/OpenCodexWidget.entitlements"

rm -rf "$APP" "$DERIVED_DATA"
mkdir -p "$ROOT/dist"
xcodebuild \
  -project "$ROOT/OpenCodexTray.xcodeproj" \
  -scheme OpenCodexTray \
  -configuration Release \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" \
  -disableAutomaticPackageResolution \
  CODE_SIGNING_ALLOWED=NO \
  build
cp -R "$PRODUCT_APP" "$APP"
```

Do not invoke `xcodebuild -resolvePackageDependencies` and do not change package-manager security policy.

- [ ] **Step 5: Implement exact inside-out signing**

Local branch:

```zsh
codesign --force --sign - --entitlements "$WIDGET_ENTITLEMENTS" "$WIDGET"
codesign --force --sign - "$APP"
codesign --verify --deep --strict --verbose=4 "$APP"
```

Release branch:

```zsh
codesign --force --options runtime --timestamp \
  --entitlements "$WIDGET_ENTITLEMENTS" \
  --sign "$SIGNING_IDENTITY" "$WIDGET"
codesign --force --options runtime --timestamp \
  --sign "$SIGNING_IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=4 "$APP"
```

Leave notarization submission, status parsing, staple/validate, Gatekeeper assessment, and two ZIP operations in their current order after signing.

- [ ] **Step 6: Update release assertions**

In `test_release_build_signs_notarizes_staples_and_repackages`, add these exact assertions before existing notarization/stapling checks:

```zsh
local widget="$app/Contents/PlugIns/OpenCodexWidget.appex"
local widget_sign="codesign|--force --options runtime --timestamp --entitlements $TEST_ROOT/Resources/OpenCodexWidget.entitlements --sign $identity $widget"
local app_sign="codesign|--force --options runtime --timestamp --sign $identity $app"
assert_contains "$command_log" "$widget_sign"
assert_contains "$command_log" "$app_sign"
assert_before "$widget_sign" "$app_sign"
assert_contains "$command_log" "codesign|--verify --deep --strict --verbose=4 $app"
```

Rename `test_release_build_removes_stale_archive_on_early_failure`'s injected variable from `FAKE_SWIFT_FAIL=1` to `FAKE_XCODEBUILD_FAIL=1`, and change its failure message to `release build succeeded when Xcode build failed`. Keep every existing `.env` precedence, rejected-notarization, two-ZIP, staple, Gatekeeper, and stale-output assertion unchanged.

- [ ] **Step 7: Extend artifact checks**

After `build-app.sh`, require:

```zsh
WIDGET="$APP/Contents/PlugIns/OpenCodexWidget.appex"
test -x "$WIDGET/Contents/MacOS/OpenCodexWidget"
test "$(plutil -extract CFBundleIdentifier raw -o - "$WIDGET/Contents/Info.plist")" = "local.opencodex.quota-tray.widget"
test -f "$WIDGET/Contents/Resources/ProviderIcon-claude.svg"
test -f "$WIDGET/Contents/Resources/ProviderIcon-codex.svg"
test -f "$WIDGET/Contents/Resources/CodexBar-LICENSE.txt"
codesign --verify --deep --strict --verbose=4 "$APP"
```

Keep binary local-path scan and run `--verify-resources` against both built Xcode app and SwiftPM executable.

- [ ] **Step 8: Run build, artifact, and core verification**

Run:

```bash
./tests/build-app-tests.sh
./tests/xcode-project-tests.sh
swift test
./tests/release-artifact-tests.sh
```

Expected: both shell suites print PASS, Swift tests exit 0, and `dist/OpenCodexTray.app` contains a strictly verifiable extension.

- [ ] **Step 9: Review and commit**

```bash
git add scripts/build-app.sh tests/build-app-tests.sh tests/release-artifact-tests.sh
git diff --cached --check
git commit -m "build: embed and sign quota widget"
```

### Task 9: Document and Prove Stopped-Tray Refresh

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: final built app and widget bundle.
- Produces: user setup documentation and local acceptance evidence.

- [ ] **Step 1: Document widget behavior and path boundary**

Add a `Notification Center widget` section stating:

```markdown
## Notification Center widget

Build and open `dist/OpenCodexTray.app` once so macOS discovers `OpenCodex Quota`.
Add it from Notification Center's widget gallery in small or medium size. The
widget requests fresh Codex and Claude quota every 30 minutes and works while
the tray app is stopped; macOS may defer refreshes.

The widget reads only the default `~/.config/opencodex-quota-tray/config.json`
and `~/.opencodex/admin-api-token` paths. Custom `XDG_CONFIG_HOME` or
`OPENCODEX_HOME` paths continue working in the tray but are unavailable to the
sandboxed widget.
```

Also update opening description to mention Notification Center without changing quota formulas.

- [ ] **Step 2: Run fresh full automated verification**

Run in this order:

```bash
swift test
xcodebuild test -project OpenCodexTray.xcodeproj -scheme OpenCodexTray -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO
./tests/xcode-project-tests.sh
./tests/build-app-tests.sh
./tests/release-artifact-tests.sh
codesign --verify --deep --strict --verbose=4 dist/OpenCodexTray.app
```

Expected: every command exits 0; XCTest and SwiftPM report zero failures; all shell scripts print PASS.

- [ ] **Step 3: Inspect exact extension metadata and entitlements**

Run:

```bash
WIDGET="dist/OpenCodexTray.app/Contents/PlugIns/OpenCodexWidget.appex"
plutil -p "$WIDGET/Contents/Info.plist"
codesign -d --entitlements :- "$WIDGET"
```

Verify bundle identifier `local.opencodex.quota-tray.widget`, extension point `com.apple.widgetkit-extension`, sandbox enabled, network client enabled, and only the two approved read-only path exceptions.

- [ ] **Step 4: Register and query extension**

Run:

```bash
WIDGET="dist/OpenCodexTray.app/Contents/PlugIns/OpenCodexWidget.appex"
pluginkit -a "$WIDGET"
pluginkit -m -A -D -i local.opencodex.quota-tray.widget
```

Expected: query returns one matching extension at the built app path.

- [ ] **Step 5: Prove live refresh with tray stopped**

Record whether `OpenCodexTray` is running and its exact PID. Open the built app once only if registration requires it. Add the medium `OpenCodex Quota` widget through Notification Center's widget gallery, using the computer-control skill when UI automation is available.

Stop only the recorded/built `OpenCodexTray` process, leave OpenCodex itself running, and confirm:

```bash
pgrep -x OpenCodexTray
```

Expected: exit 1 with no PID while widget shows current Codex and Claude data. Verify the displayed update age advances after a timeline reload. If the tray was running before the test, reopen the same built app afterward to restore prior state.

- [ ] **Step 6: Check final scope and commit docs**

Confirm no pause request was emitted by widget execution, no token appeared in logs/diffs, and only task files differ from the plan base. Then:

```bash
git add README.md
git diff --cached --check
git commit -m "docs: document Notification Center widget"
```

- [ ] **Step 7: Final branch review**

Run:

```bash
git status --short
git log --oneline --decorate -10
git diff --stat 7fd142d..HEAD
git -C /Users/alex/sources/opencodex_tray status --short
```

Expected: implementation worktree is clean when isolation was used; original checkout still shows the user's license edit and `.superpowers/` as unstaged/untracked; feature commits contain only planned paths. Do not push.
