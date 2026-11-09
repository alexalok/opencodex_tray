# Subscription Baselines Implementation Plan

Goal: persist one display baseline per provider, with subscription identifiers and relative allowances grounded in provider documentation and OpenCodex source.

Design: menu submenus select the subscription representing 100%. Defaults preserve Codex Pro and Claude native-account units. Quota calculators scale remaining capacity and totals; pause decisions stay native. Cache raw refresh data so settings changes redraw without network or pause operations. Unknown plans remain unknown. Label estimates and document evidence limits.

Constraints: preserve existing unrelated edits; no staging, commit, push, install, or live operations. Swift/macOS 14, no dependencies.

- [x] Add failing tests for baseline math, unknown IDs, persistence, decoding and unchanged native pause decisions.
- [x] Implement provider baseline catalog and persisted settings in core; add Claude plan decoding.
- [x] Carry raw accounts in refresh results; recalculate cached display with selected baselines.
- [x] Add menu pickers and baseline labels; document research and limitations.
- [x] Run swift test, build, and independent review.

Review focus: missing Claude tier metadata; ambiguous Pro IDs; differing weekly vs session ratios; settings during in-flight refresh; stale errors after local recalculation.

## Results and rulings

- 40 Swift tests pass after the 2026-11-09 correction. Build succeeds; SwiftPM nested sandbox is unavailable in
  this environment, so verification uses `--disable-sandbox` and temporary caches.
- Independent review found stale baseline labels over cached rows on refresh
  errors. Fixed by clearing affected rows and clearing the full cached snapshot
  on a global refresh failure.
- Current Claude documentation supersedes initial 1:5:20 assumptions: weekly
  1:5:10; session 1:5, with Ultra comparisons unknown because verification and
  temporary caps cannot be established from the payload.
- Superseded on 2026-11-09: official Codex auth source identifies `prolite`,
  `pro`, and `promax`. Combined with Tibo's current clarification, use 10/20/50
  Plus-equivalent capacity. Removed legacy estimate labels and added Pro $500.
  Pro-only pools no longer require a nonexistent five-hour reading.
- Fixed Codex short-window payload decoding after source inspection found the
  actual `shortPercent` key. Regression verified failing then passing.
- No commit, install, launch against live services, or remote write performed.
