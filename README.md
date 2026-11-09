<p align="center">
  <img src="assets/app-icon.png" width="160" alt="OpenCodex Quota Tray icon">
</p>

# OpenCodex Quota Tray

Native macOS 14+ menu-bar app. Polls OpenCodex, pauses one exact Codex account
alias at its configured weekly threshold, and shows Codex and Claude pool
allowances.

[OpenCodex](https://github.com/lidge-jun/opencodex) is a local proxy that
multiplexes several Codex and Claude accounts behind one endpoint and tracks
their quota usage. This app sits in the macOS menu bar, polls that proxy, and
turns its per-account quota data into at-a-glance pool totals.

![Menu-bar dropdown showing Codex and Claude pool percentages with per-account rows](assets/tray-screenshot.png)

## Quota math

Target alias native allowance equals `PAUSE_THRESHOLD_PERCENT` (default `70`).
Every other account has `100` native allowance. Choose the subscription that
counts as `100%` in **Settings → Codex: 100% equals** or
**Settings → Claude: 100% equals**. Choices persist across app launches and
redraw the latest snapshot immediately, without another network request.

Defaults use Codex Pro $200 units and Claude native
percentages per account. Pause thresholds always use native percentages.
The headless `pause-worker-once` command retains these defaults; menu preferences
apply to the tray app only.

```text
native remaining = max(native allowance - usage, 0)
normalized remaining = native remaining × account capacity / baseline capacity
tray = floor(sum(normalized remaining))
```

Codex baselines are Plus, Pro $100, Pro $200, Pro $500, and
**Each account (native)**. The upstream IDs `plus`, `prolite`, `pro`, and
`promax` have current relative capacities `1 : 10 : 20 : 50`.
Native mode adds unscaled account percentages.

For example, Pro $100 at 53% used with a 70% pause threshold contributes 8.5%
in Pro $200 units, 17% in Pro $100/native units, or 170% in Plus units.
Missing quota or unsupported plans show `—`. All Pro tiers have no five-hour
limit, so their absence of session quota does not prevent hiding a healthy
Pro-only pool. Limited accounts still need known, comparable session quota.

Claude baselines are Pro, Max, Ultra (formerly Max 20×), and
**Each account (native)**. Weekly capacities are `1 : 5 : 10`; Pro and Max
5-hour capacities are `1 : 5`. Rows and tray show **5-hour / 1-week** remaining.
Ultra has no 5-hour cap for verified accounts, and its temporary unverified
cap has no published conversion. Any normalized session comparison involving
Ultra therefore shows `—`; the tray does not guess verification status or
infinite capacity. Native mode keeps the raw window percentages where available.
Missing or ambiguous plan metadata cannot be normalized.

Pool totals can exceed `100%`. Providers disappear from the menu-bar label
when both 5-hour and weekly remaining totals exceed `95%` in the selected
baseline units. They remain in the dropdown. Unknown windows and refresh
errors keep the provider visible. If both providers are hidden, a chart icon
keeps the menu accessible.

See [subscription identifiers and evidence](docs/subscription-baselines.md)
for mappings and limits of these comparisons.

## Configure

Finder-launched apps do not reliably inherit shell environment. Create:

```text
~/.config/opencodex-quota-tray/config.json
```

```json
{
  "targetAccountAlias": "workmate",
  "pauseThresholdPercent": 70
}
```

Environment variables remain supported and override config-file values.

Optional env:

| Variable | Default |
| --- | --- |
| `PAUSE_THRESHOLD_PERCENT` | `70` |
| `POLL_INTERVAL_MS` | `60000` |
| `REQUEST_TIMEOUT_MS` | `30000` |
| `OPENCODEX_BASE_URL` | `http://127.0.0.1:10100` |
| `OPENCODEX_HOME` | `$HOME/.opencodex` |

Alias matching is exact and case-sensitive. Missing or duplicate target alias
fails closed: no pause request is sent. Admin token is read once from
`${OPENCODEX_HOME:-$HOME/.opencodex}/admin-api-token`.

## Develop

```bash
swift test
swift run OpenCodexTray
```

Headless single check:

```bash
swift run pause-worker-once
```

## Build app

Local builds use an ad-hoc signature and do not contact Apple:

```bash
./scripts/build-app.sh
open dist/OpenCodexTray.app
```

Trusted direct distribution requires the local Developer ID identity and a
one-time Notary service Keychain profile:

```bash
xcrun notarytool store-credentials "YOUR_NOTARY_PROFILE" \
  --apple-id "YOUR_APPLE_ACCOUNT" \
  --team-id "YOUR_TEAM_ID"
```

Enter an app-specific password when prompted. Copy `.env.example` to `.env`
and replace its placeholders with your local signing identity and Keychain
profile. `.env` is ignored by Git.

The build reads only `SIGNING_IDENTITY` and `NOTARY_PROFILE` from `.env` as
literal values; it does not execute the file as shell code.

```bash
cp .env.example .env
NOTARIZE=1 ./scripts/build-app.sh
```

This signs, notarizes, staples, and verifies the release. The distributable
artifact is `dist/OpenCodexTray.zip`. Environment variables override values
loaded from `.env`.

Tray title shows Claude icon + remaining Claude pool `5h/1w` allowance, then
Codex icon + normalized Codex pool percentage. Click it for separate
`Codex Pool` and `Claude Pool (5h/1w)` sections with per-account rows,
`Refresh Now`, errors, and `Quit`. `Launch at Login` registers the app through
macOS Service Management. If macOS requires approval, use
`Open Login Items Settings` from the tray menu. App has no Dock icon.

## License

MIT, see [LICENSE](LICENSE).

Bundled CodexBar provider icons are MIT-licensed by Peter Steinberger, see
[Sources/OpenCodexTray/Resources/CodexBar-LICENSE.txt](Sources/OpenCodexTray/Resources/CodexBar-LICENSE.txt).
