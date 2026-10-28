# Adaptive Hub Quotas Implementation Plan

> For agentic workers: use executing-plans; server and native client have separate ownership and share the spec wire contract.

**Goal:** Follow the active host OpenCodex quota source in tray and widget.
**Architecture:** Resolve source per refresh; preserve local quota reader; add a versioned remote snapshot reader and narrow server endpoint.
**Tech Stack:** Swift 6/Foundation/SwiftUI/WidgetKit and Bun TypeScript.
**Spec:** ../specs/2026-10-27-adaptive-hub-quotas-design.md

## Global Constraints

No admin-secret forwarding, no automatic local fallback in hub mode, no live changes, no push. Existing percentage/threshold/reset-credit behavior must remain.

## Review Focus

Mode transitions, target/key rotation, malformed hub snapshots, invalid grants, and widgets with stale source configuration.

## Task 1: Server quota read

- [x] Add failing tests for granted/denied keys, provider/model scope, revoked grant during read, write rejection and secret-free projection.
- [x] Implement /v1/hub-quota and per-key allowQuotaRead schema/management support in isolated OpenCodex fork checkout.
- [x] Run focused tests, typecheck, privacy/structure checks required by repo; document endpoint and explicit grant operation.

## Task 2: Adaptive native source

- [x] Add failing resolver tests: local/client, changed target/key, fingerprint mismatch, HTTP remote refusal, invalid config.
- [x] Implement source resolver and read-only hub DTO decoder/loader with bounded requests and redirect refusal.
- [x] Add failing snapshot tests for partial failures and malformed responses; preserve quota math.

## Task 3: Tray and widget wiring

- [x] Resolve on each tray poll and publish source to App Group; read source in widget and guard stale mode.
- [x] Label selected source and disabled supported providers; replace stale totals on source failures.
- [x] Run native suite and widget compile/tests; review both patches against shared contract.

## Completion

- [x] Export reviewable patches and validation notes. No unsolicited commit/push/install/deploy.
