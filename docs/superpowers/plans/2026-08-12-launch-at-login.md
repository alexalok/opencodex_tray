# Launch at Login Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add configurable launch-at-login from tray menu.

**Architecture:** Testable controller lives in `PauseWorkerCore`; app adapter wraps `SMAppService.mainApp`. SwiftUI toggle synchronizes status when menu appears and after mutations.

**Tech Stack:** Swift 6.2, SwiftUI, ServiceManagement, Swift Testing.

## Global Constraints

- Support macOS 14+.
- Default remains disabled.
- Use no third-party dependency or helper executable.
- Preserve unrelated untracked `.vscode/` content.

---

### Task 1: Testable launch-at-login controller

**Files:**
- Create: `Sources/PauseWorkerCore/LaunchAtLogin.swift`
- Create: `tests/PauseWorkerCoreTests/LaunchAtLoginTests.swift`

**Interfaces:**
- Produces: `LaunchAtLoginStatus`, `LaunchAtLoginService`, and `LaunchAtLoginController`.

- [ ] Write tests using an in-memory service for disabled, enabled, approval-required, and throwing transitions.
- [ ] Run `swift test --filter LaunchAtLoginTests`; verify compile failure because interfaces do not exist.
- [ ] Implement minimal controller and rerun focused tests.

### Task 2: Service Management adapter and menu toggle

**Files:**
- Modify: `Sources/OpenCodexTray/OpenCodexTrayApp.swift`

**Interfaces:**
- Consumes: `LaunchAtLoginService` and `LaunchAtLoginController`.
- Produces: `SMAppService.mainApp` adapter and `Launch at Login` tray toggle.

- [ ] Add adapter status mapping and register/unregister calls.
- [ ] Add toggle, status refresh, approval notice, and error output.
- [ ] Run `swift test` and `./scripts/build-app.sh`.

### Task 3: User documentation and acceptance

**Files:**
- Modify: `README.md`

- [ ] Document tray toggle and System Settings approval behavior.
- [ ] Review diff for scope and run fresh full verification.
- [ ] Ask Fable Max to inspect requirements, diff, tests, and build evidence; fix all blocking findings.
