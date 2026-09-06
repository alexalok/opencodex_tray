# Notification Center Widget Design

> **Status: Obsolete (2026-09-04).** Superseded by read-only `OpenCodexQuotaCore`. Pause-related architecture and old package/target names below are historical only.

## Goal

Add native macOS Notification Center widgets for OpenCodex quota visibility. The widget must refresh quota data while the menu bar app is not running, support small and medium families, and remain unable to pause or otherwise mutate OpenCodex accounts.

## Scope

The feature includes:

- a WidgetKit extension for macOS 14 and later;
- small and medium provider-split layouts;
- direct read-only quota refresh from OpenCodex;
- shared quota-loading and calculation code in `PauseWorkerCore`;
- extension-local caching for total-fetch failures;
- an Xcode project that builds the app and embeds the extension;
- offline ad-hoc builds and the existing Developer ID/notarization release flow.

The feature excludes large widgets, interactive pause/resume controls, configuration UI, backend changes, and Mac App Store packaging.

## User Experience

### Small widget

The small widget is titled `OpenCodex Quota` and shows two provider rows:

- Claude aggregate remaining quota as `5h / 1w`;
- Codex aggregate remaining Pro-equivalent allowance;
- last-updated age in the footer.

Aggregates retain current semantics and may exceed 100% because they sum allowance across accounts. Unknown values render as an em dash rather than as zero.

### Medium widget

The medium widget uses two provider columns. Each column shows its aggregate at the top and up to two account rows below it, preserving API order. If a provider has more than two accounts, the column shows `+N more`. Claude account rows show `5h / 1w`; Codex account rows show `remaining / total`.

Both layouts reuse the existing Claude and Codex provider artwork and use monospaced digits for stable quota alignment. Only `.systemSmall` and `.systemMedium` are registered as supported families.

### Loading and failure states

WidgetKit placeholders use representative static data and never issue network requests. Gallery snapshots use cached data when available and otherwise use the placeholder.

Live timeline behavior is provider-specific:

- both providers succeed: display both and replace the last-complete cache;
- one provider fails: display the successful provider and `Unavailable` for the failed provider; do not replace the last-complete cache;
- both providers fail: display the last complete cached snapshot with a stale marker and its original update age;
- both providers fail and no cache exists: display `Unable to load`.

Configuration or token-loading errors count as a total failure because no provider request can start.

## Architecture

### Shared fetch-only boundary

Add `OpenCodexQuotaServing` to `PauseWorkerCore` with only these operations:

- fetch Codex accounts;
- fetch Claude accounts.

Separate pause mutation behind `OpenCodexPausing`. A fetch-only `OpenCodexQuotaClient` implements the quota protocol. A separate pause client implements `OpenCodexPausing`. `WorkerConfiguration` retains base URL validation; shared HTTP transport code handles bearer authentication, timeouts, response status checks, and decoding without duplicating request mechanics.

The widget constructs only `OpenCodexQuotaClient`; no widget component receives `OpenCodexPausing`. The tray's `PauseWorker` receives both the shared quota loader and the pause dependency. This is an API boundary against accidental mutation, not a replacement for server-side authorization.

### Shared snapshot loader

Add `QuotaSnapshotLoader` to `PauseWorkerCore`. It accepts `OpenCodexQuotaServing`, target alias, and threshold. It starts Codex and Claude requests concurrently, handles each result independently, and applies the existing `QuotaCalculator` and `ClaudeQuotaCalculator` rules.

The loader returns a `QuotaSnapshotLoad` containing:

- a timestamped, codable `QuotaSnapshot` with optional provider summaries and provider-specific error messages;
- successfully fetched Codex accounts for the tray's pause policy.

The loader itself performs no mutation. `PauseWorker.refresh()` delegates fetching and summarization to the loader, then evaluates the successfully fetched target account and invokes `OpenCodexPausing` only when the existing threshold rule requires it. The tray maps the resulting snapshot to its current menu and status-item state. The widget calls the loader directly and ignores pause-policy data.

This keeps calculation, partial-failure handling, and provider fetch concurrency identical between the tray and widget while preserving the tray's current automatic-pause behavior.

### Widget timeline and cache

Add a WidgetKit timeline provider in a new `OpenCodexWidget` source directory. Its production path:

1. loads validated connection settings from the Team-ID App Group;
2. constructs no direct home-directory file access;
3. creates the fetch-only client and `QuotaSnapshotLoader`;
4. loads a snapshot;
5. applies the failure/cache rules above;
6. returns one timeline entry and requests another refresh 30 minutes later.

WidgetKit may coalesce or defer that requested refresh. The UI therefore always reports actual snapshot age and never promises an exact polling interval.

`WidgetSnapshotCache` stores only the last snapshot where both providers succeeded. Storage lives in the extension's own Application Support container. It contains quota values, account labels, and timestamps, but never the admin token or request headers. Cache corruption is treated as a cache miss.

## Sandbox and File Access

The widget extension enables App Sandbox and outbound network access. Both the
tray and extension carry the macOS App Group entitlement
`KTNPDHXXV3.opencodex.quota-tray.shared`. On successful tray bootstrap, the
unsandboxed host validates its normal config and token inputs, then atomically
writes the minimal widget connection payload to a `0700` directory with a
`0600` file. The extension reads only this shared file; it has no home-directory
temporary exceptions.

The app remains directly distributed rather than Mac App Store packaged. The
shared payload lets custom `XDG_CONFIG_HOME` and `OPENCODEX_HOME` paths work
without granting the extension access to arbitrary home locations. Config or
token changes take effect in the widget after the tray runs again. The payload
persists, so the extension can continue refreshing after the tray stops.

The OpenCodex service must remain reachable independently of the tray process. Loopback HTTP remains valid under current configuration rules; non-loopback endpoints still require HTTPS.

## Project and Build Structure

Add a checked-in `OpenCodexTray.xcodeproj` with:

- `OpenCodexTray`, a macOS app target using the existing app sources and bundle identifier `local.opencodex.quota-tray`;
- `OpenCodexWidget`, a WidgetKit extension target using bundle identifier `local.opencodex.quota-tray.widget`;
- the repository root as a local Swift package dependency so both targets consume `PauseWorkerCore`;
- the widget extension embedded under `OpenCodexTray.app/Contents/PlugIns`.

`Package.swift` remains authoritative for `PauseWorkerCore`, `pause-worker-once`, existing unit tests, and command-line `swift build` workflows. The existing provider icon files under `Sources/OpenCodexTray/Resources` remain single physical files: SwiftPM continues processing them for the executable resource bundle, while both Xcode app and widget targets reference those same files as resources.

Widget-specific metadata and sandbox permissions live in checked-in files under `Resources`, including the extension Info plist and entitlements. Host App Group permissions live in `Resources/OpenCodexTray.entitlements`. Widget implementation files live under `Sources/OpenCodexWidget` and are not added as a SwiftPM target.

Update `scripts/build-app.sh` to build the Release app with offline `xcodebuild`, copy the resulting complete app bundle to `dist/OpenCodexTray.app`, and preserve current environment precedence and notarization controls.

Signing order is always inside-out:

1. sign `Contents/PlugIns/OpenCodexWidget.appex` with widget entitlements;
2. sign `OpenCodexTray.app` with host App Group entitlements;
3. verify the complete bundle with `codesign --verify --deep --strict`.

Local builds use ad-hoc signing and perform no network or notarization calls;
they verify compilation and bundle structure but do not provide a Team ID for
live App Group access. `NOTARIZE=1` uses the configured Developer ID identity
for both nested bundles, enables hardened runtime and timestamps, then
preserves the existing archive, notarization, stapling, Gatekeeper assessment,
and repackaging sequence. That identity's Team ID must match the checked-in App
Group prefix.

## Tests and Verification

### Core tests

Add deterministic fakes for fetch and pause protocols. Unit tests cover:

- concurrent loader success and unchanged aggregate calculations;
- Codex-only and Claude-only success;
- total provider failure;
- target alias validation;
- pause policy after a successful Codex load;
- absence of pause attempts when Codex loading fails;
- in-flight refresh coalescing after the refactor.

### Widget tests

Test timeline-state construction separately from WidgetKit rendering:

- complete live snapshot replaces cache;
- partial result renders one unavailable provider and preserves cache;
- total failure uses stale cache;
- total failure without cache renders empty failure state;
- account rows cap at two and report overflow;
- unknown values render as em dashes;
- next requested refresh is 30 minutes after the entry date.

### Build tests

Update shell build tests with a fake `xcodebuild` product containing an embedded extension. Assert that:

- local build stays offline and ad-hoc;
- stale output is removed;
- extension signing precedes app signing;
- release credentials remain mandatory and environment precedence is unchanged;
- failed release builds do not leave stale archives;
- release signing, notarization, stapling, Gatekeeper assessment, and repackaging remain intact.

Final verification runs:

1. `swift test`;
2. build-script shell tests;
3. release-artifact tests;
4. `./scripts/build-app.sh` without network access;
5. `codesign --verify --deep --strict --verbose=4 dist/OpenCodexTray.app`;
6. inspect `Contents/PlugIns/OpenCodexWidget.appex` metadata and entitlements;
7. register/query the extension with `pluginkit`;
8. confirm a live widget refresh succeeds while the tray process is stopped.

## Acceptance Criteria

- macOS offers `OpenCodex Quota` in small and medium widget families.
- Small widget shows Claude and Codex aggregates in provider-split layout.
- Medium widget adds bounded provider-specific account rows.
- Widget refreshes directly when the tray app is not running.
- Provider failures and stale data are visibly distinguished.
- Widget code has no pause dependency or mutation call path.
- Tray quota output and automatic-pause behavior remain unchanged.
- Swift tests, build tests, offline app build, nested signing verification, extension registration, and stopped-tray refresh checks pass.
