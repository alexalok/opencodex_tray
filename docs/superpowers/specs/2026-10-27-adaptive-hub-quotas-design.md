# Adaptive OpenCodex quota sources

User intent: show the quota pools belonging to whichever mode the host OpenCodex currently uses, including switching between local and hub-client mode without restarting the tray. Keep existing Codex/Claude quota math and widget behavior.

## Approaches

Selected: a dedicated read-only hub quota API, explicitly opted into per enrolled client key, plus automatic source selection. Copying a hub administrator token was rejected in favor of narrower access. A browser GUI session expires and is not suitable for unattended polling.

## Design

On each tray refresh, resolve the configured host's running role. Local standalone/hub mode keeps existing local account APIs. Client mode reads the connection metadata and enrolled key from the host's OpenCodex home, validates the key fingerprint, and uses HTTPS GET /v1/hub-quota. Never forward the local admin credential to a remote host or follow redirects with credentials. If the running role and saved connection disagree, fail explicitly instead of showing a different pool.

Publish the resolved source configuration to the existing owner-only App Group store for the widget. Widget checks host runtime role before using that stored connection; a stale connection must fail rather than show old local pools. Tray refreshes that record on connection or token changes. Source labels distinguish local from hub. Provider errors remain separate and missing quota is not zero.

## Wire contract

GET /v1/hub-quota; X-OpenCodex-API-Key is the existing enrolled data key. An explicit per-key allowQuotaRead=true grant is required. Default is denied. No write methods. Restrict returned providers to key scope; conservatively deny model-restricted keys. Return no tokens, emails, raw account identifiers or provider URLs.

Response schemaVersion=1, generatedAt=ISO-8601 timestamp, providers={openai, anthropic}. Each provider has enabled:boolean, accounts:[], and optional error:string. Disabled providers have empty accounts. Errors use safe fixed strings, not upstream bodies.

OpenAI account: id:string (opaque), alias?:string, plan?:string, isMain:boolean, paused:boolean, weeklyPercent:number|null, autoSwitchThreshold:number|null, resetCreditExpirations:string[]|null. Anthropic account: id:string (opaque), alias?:string, fiveHourPercent:number|null, weeklyPercent:number|null. Percentages are used percentages. Null is unknown. No account secrets or email fallback. Main-account deduplication must preserve existing tray semantics.

Status: 401 invalid/missing enrolled key; 403 grant absent or unsupported scope; 404 non-hub/old endpoint; 405 non-GET; 503 snapshot unavailable. Bounded output, no-store, permission revalidation after asynchronous reads.

## Boundaries

Prepare and test source patches locally. Do not push, install the tray, update/restart the live hub, or grant a live key quota access without the user's explicit approval of those final actions.
