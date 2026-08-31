# AGENTS.md

OpenDota bar widget for Omarchy. Quickshell QML plugin + Python
collector that reads Dota 2 stats from OpenDota's public API and
renders them in the status bar.

## Layout

- `manifest.json` — plugin metadata, settings schema. The `id` is the
  marketplace-registered identifier; the directory name in
  `~/.config/omarchy/plugins/` must match.
- `Main.qml` — data layer. Spawns `bin/collect` as a subprocess, owns
  the two refresh timers, parses the JSON record. Reads
  `~/.cache/omarchy/opendota/record.json` via `FileView` on startup
  so the bar icon appears immediately rather than waiting for the
  first network refresh.
- `Panel.qml` — UI. Extends `Panel` from `qs.Ui`, uses
  `BarIconButton` + `KeyboardPanel` + `PanelKeyCatcher` per the
  Omarchy reference pattern. Inline components: `ModeRow`, `StreakRow`,
  `MatchRow`, `HeroRow`.
- `bin/collect` — Python3 collector. Prints one JSON record on stdout;
  exit code 0 even on unconfigured/error paths. The `# omarchy:summary=`,
  `# omarchy:args=`, `# omarchy:hidden=true` header comments are how
  `omarchy-shell-config` discovers the script for the bar's right-click
  catalog. Do not remove them.
- `assets/opendota.svg` + `assets/opendota-light.svg` — bar mark. Single
  fill, tinted at render time via `MultiEffect`. The fill must be a
  hardcoded color (e.g. `#888888`); `fill="currentColor"` renders as
  black through the MultiEffect pipeline and breaks colorization.
- `test/test_account_id.py` — precedence test for account-id resolution.
- `preview.png` — repo-root preview used by the marketplace catalog.

## Commands

```sh
omarchy plugin validate .                      # lint manifest + entry points
python3 test/test_account_id.py                # run precedence tests
bin/collect --demo                             # emit synthetic data, no network
bin/collect --force                            # heavy refresh, all endpoints
bin/collect --summary-only                     # light refresh, cached matches
bin/collect --account-id 83730627              # override at CLI
OPENDOTA_ACCOUNT_ID=... bin/collect           # override at env
```

The collector is invoked by `Main.qml` (no shell wrapper) and lives
in the user's plugin directory at runtime — never edit the source
copy in this repo and expect live changes; edit, then
`omarchy plugin update io.github.drc.opendota` to install.

## Account id resolution

Precedence, highest first:

1. `--account-id` CLI flag
2. `OPENDOTA_ACCOUNT_ID` env var
3. `accountId` field in `~/.config/omarchy/agents/opendota.json`
4. Local Steam install: most-recently-modified entry under
   `~/.steam/steam/userdata/` or `~/.local/share/Steam/userdata/`,
   falling back to the `AutoLogin=1` entry in
   `~/.steam/steam/config/loginusers.vdf`. Steam64 is converted to
   Steam32 (subtract `76561197960265728`).

Adding a new source: extend `resolve_account_id` in `bin/collect` and
add a test case to `test/test_account_id.py`. The test harness runs
`bin/collect --demo` in a subprocess with a fake `HOME`, so test
cases must clean up env vars in `setUp`/`tearDown`.

## OpenDota API quirks

The collector falls back from `/players/{id}/matches?limit=100` to
`/players/{id}/recentMatches` when the former is empty. This
unblocks accounts whose Steam match history was recently flipped to
public — OpenDota populates `/recentMatches` (fast path) before
`/matches` and `/wl` (slow aggregation). When the latter return 0/0
but we have parsed matches, W/L is derived from the match sample so
the panel shows real numbers.

`rank_tier` and `mmr_estimate` on `/players/{id}` are populated by yet
another slow job; expect them to be null for several minutes after a
privacy flip even when matches are visible.

## Omarchy platform notes

- Plugin IDs in the marketplace namespace (`io.github.<user>.<name>`)
  are permanent; renaming is a multi-file coordinated change
  (manifest, `moduleName`/`ipcTarget` in `Panel.qml`, all README
  examples, removal of the old install). Don't rename casually.
- The bar's `moduleName` and IPC `ipcTarget` in `Panel.qml` must
  match the manifest `id`. IPC handlers register when the panel
  mounts; `omarchy restart shell` is required after edits to
  `Main.qml`/`Panel.qml`.
- The collector runs as the user. It reads only the user's
  `~/.steam` and `~/.config`; it does not need or accept elevated
  permissions. It writes to `~/.cache/omarchy/opendota/` (0o700).
- Quickshell hot-reloads QML on save but only within a running shell.
  A QML syntax error leaves the bar widget missing — check
  `qmllint <file>` before restarting.

## Style

- No comments in code files. The `bin/collect` docstring is allowed
  (Python convention) but inline `#` comments inside functions are
  not.
- Match the existing formatting: 2-space indent in QML, 4-space in
  Python, double quotes in JSON, single quotes in Python strings.
- Keep `bin/collect` exit-0 on every code path so the panel never
  has to handle a non-zero subprocess. Errors go to stderr.
