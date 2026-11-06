# Z.ai subscription support

Goal: display Z.ai Coding Plan quota supplied by OpenCodex in tray and widget.

Design: read `/api/provider-quotas` using existing OpenCodex credentials, locally or through Link relay. Select reports by `source == zai:quota-limit`, retaining provider IDs as row identities. Display native 5h/weekly remaining percentages, without plan normalization. Reuse existing two-window allowance math. Never read vendor keys or call Z.ai directly. Hub schema accepts an optional zai provider; absent means unsupported/hidden. Do not mutate OpenCodex infrastructure.

Plan:
- [x] Add decoder tests: source filtering, aliases, missing/invalid windows, duplicate IDs, old snapshots.
- [x] Wire optional Z.ai summary and isolated errors through local/Link/hub loaders.
- [x] Add conditional tray and widget presentation with accessibility labels.
- [x] Verify Swift tests and widget build; document compatibility.

Constraints: preserve existing providers and source validation; no push, deployment, or account mutations. Missing provider reports are not proof of full quota. All new fields remain optional for cached snapshots.

Validation: 76 XCTest core tests + 5 Swift Testing decoder/isolation tests passed. Xcode app/widget build and 25 widget tests passed. Independent read-only review found no actionable issues. Live subscription and visual widget layout were not exercised.
