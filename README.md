# opendota-bar

Dota 2 stats from OpenDota in the [Omarchy](https://omarchy.org/) status bar.

Shows rank and MMR estimate, per-mode (turbo / ranked / unranked) win rate,
current streak, recent turbo matches, and top turbo heroes. Turbo is the
headline queue because that's where most players spend their time, but the
plugin surfaces ranked and unranked alongside for context.

## Installation

Drop the plugin directory into `~/.config/omarchy/plugins/`:

```sh
git clone https://github.com/drc/opendota-bar \
  ~/.config/omarchy/plugins/drc.opendota
```

Add your OpenDota account id to `~/.config/omarchy/agents/opendota.json`:

```json
{
  "accountId": "83730627"
}
```

The id is the number in your OpenDota profile URL.

Enable the plugin by adding it to `~/.config/omarchy/shell.json`:

```json
{
  "bar": {
    "layout": {
      "right": [
        { "id": "drc.opendota" }
      ]
    }
  }
}
```

Restart the shell:

```sh
omarchy restart shell
```

## Steam privacy

OpenDota only mirrors public Steam data. If your Steam match history is
private, the panel shows a notice and a rank-less profile; the rest of the
sections stay empty until you enable **Expose Public Match Data** under
**Dota 2 → Settings → Social** and wait ~5 minutes for OpenDota to refresh.

## Refresh cadence

- Heavy refresh (default 10 min): walks the 100-match history and rebuilds
  per-mode buckets, top heroes, streak. Editable in the settings panel.
- Light refresh (default 60 s, when the panel opens): only refetches the
  profile and aggregate W/L, reuses cached match buckets.

## Interaction

- Click the bar icon to toggle the panel
- Right-click to force a heavy refresh
- `R` or Enter in the open panel also forces a refresh
- `Esc` closes, arrows scroll, `Tab` jumps to the next bar widget
- `omarchy-shell ipc call drc.opendota refresh` from a terminal works too

## Demo mode

The plugin supports a `demo: true` setting that emits synthetic data
without hitting OpenDota, useful for previewing the layout before your
real data is populated:

```json
{ "id": "drc.opendota", "demo": true }
```

Toggle it back to `false` (or remove the line) to use live data.

## Configuration reference

| key | type | default | meaning |
|-----|------|---------|---------|
| `refreshIntervalSec` | int | 600 | Heavy refresh interval (seconds) |
| `summaryRefreshSec` | int | 60 | Light refresh interval (seconds) |
| `recentMatchesCount` | int | 10 | Recent turbo matches shown |
| `topHeroesCount` | int | 5 | Top turbo heroes shown |
| `urgentStreakMin` | int | 3 | Lose streak length that flags the bar urgent |
| `urgentWinRatePct` | int | 45 | Turbo win rate below which the bar flags urgent (requires ≥20 games) |
| `demo` | bool | false | Emit synthetic demo data |

## Layout

```
manifest.json    plugin metadata + settings schema
Main.qml         data layer (Process + two timers)
Panel.qml        bar icon + popup
bin/collect      python3 collector; prints one JSON record
assets/          bar mark SVGs (tinted at render time)
```

## Attribution

Stats provided by the [OpenDota](https://www.opendota.com/) public API.
Dota 2 is a trademark of Valve Corporation. This project is not affiliated
with or endorsed by Valve.

## License

MIT
</content>
</invoke>