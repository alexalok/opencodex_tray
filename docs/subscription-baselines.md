# Subscription baseline evidence

Checked 2026-11-09. Fable reconciled OpenCodex payload identifiers and provider
allowances; current provider pages take precedence over old tier names.

## Claude

| OpenCodex `accounts[].plan` | Current subscription | 5-hour capacity vs Pro | Weekly capacity vs Pro |
| --- | --- | --- | --- |
| `pro` | Pro | 1 | 1 |
| `max_5x` | Max | 5 | 5 |
| `max_20x` | Ultra (formerly Max 20×) | No fixed comparable capacity | 10 |
| Missing, `max`, unknown IDs | Unresolved | Unknown | Unknown |

[Anthropic's Max article](https://support.claude.com/en/articles/11049741-what-is-the-max-plan)
confirms five times Pro usage for both windows.
[Its Ultra article](https://support.claude.com/en/articles/17728952-what-is-the-ultra-plan)
confirms automatic migration from Max 20×, ten times Pro weekly usage, and
removal of the session cap for verified accounts. Unverified accounts have a
temporary cap whose ratio is not specified. The old `20x` identifier is not a
current weekly multiplier.

The tray cannot infer verification from a missing quota field. Normalized
5-hour values involving Ultra stay unknown, even if a cached raw percentage
exists. Native mode can display raw percentages when supplied. Weekly
normalization uses 1:5:10, and excludes separate model-specific windows and API
credits. These are plan-relative allowance units, not guarantees of identical
message counts across models or workloads.

## Codex

| OpenCodex/Codex plan ID | Subscription | Capacity vs Plus |
| --- | --- | --- |
| `plus` | Plus | 1 |
| `prolite` | Pro $100 | 10 |
| `pro` | Pro $200 | 20 |
| `promax` | Pro $500 | 50 |

[Official Codex auth source](https://github.com/openai/codex/blob/e54a5713caf331f42a6eef0166186df5f7563c29/codex-rs/protocol/src/auth.rs#L135)
maps the personal tiers to display names and wire IDs: ProLite → Pro / `prolite`,
Pro → Pro (More) / `pro`, ProMax → Pro (Max) / `promax`.
[Generated PlanType](https://github.com/openai/codex/blob/e54a5713caf331f42a6eef0166186df5f7563c29/codex-rs/app-server-protocol/schema/typescript/PlanType.ts)
confirms all four wire strings. The local ChatGPT provider's
`src/adapters/chatgpt-web/limits.ts` independently maps `prolite` to Pro $100
and `pro` to Pro $200.

[Tibo's November 8 clarification](https://x.com/thsottiaux/status/2119296267545419987)
supplies the current 10/20/50 usage multiples and states that all Pro plans
have no five-hour limit. The old local OpenCodex weights in
`src/providers/codex-capacity.ts` still say `prolite: 5`, `pro: 20`, with no
`promax` entry. Those weights are stale, not evidence of ambiguous tier IDs.
The tray now uses the current ratios and includes Pro $500 in settings.

Pro $200 remains the default. Pro $100 therefore contributes half as much
capacity, rather than the previous quarter. Unknown organizational, Free/Go,
and future tier conversions remain unknown; native mode is available.

Pro accounts do not need a five-hour reading to pass the tray's visibility
check. Limited accounts still require known session quota. A mixed pool with
a Pro baseline stays visible when the remaining limited accounts have no
comparable finite session baseline; Plus/native baselines compare their
finite session windows. Missing session data is never treated as unlimited
unless the source tier explicitly identifies a Pro plan.

## Payload evidence and behavior

Inspected local OpenCodex source at revision `409026b1b`:

- `src/oauth/anthropic-identity.ts` derives Claude plan IDs from the profile's
  `organization.rate_limit_tier`, stripping `default_claude_`; organization type
  is a fallback. `src/oauth/plan.ts` validates metadata without guessing capacity.
- `src/codex/auth-api/account-list.ts` carries Codex plan/quota data.
- `src/cli/account-api.ts` distinguishes Codex `shortPercent` from Claude
  `fiveHourPercent`. The tray supports both Codex forms for compatibility;
  an explicit non-18000-second short window is not treated as five hours.

Settings apply only to display math and the 95% tray visibility cutoff. The
pause decision remains in the target account's native weekly percentages.
Settings redraw cached raw accounts without requests; unknown windows keep
providers visible. Refresh errors clear affected rows to avoid showing old
units under a new baseline label.
