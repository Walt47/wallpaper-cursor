# Wallpaper Cursor

Switch Mango cursor theme when the Noctalia wallpaper changes (per-folder).

| Wallpaper folder | Cursor |
|---|---|
| `Pictures/Wallpapers/Land of the Lustrous/*` | `Phosphophyllite` |
| `Pictures/Wallpapers/Umineko/*` | `Beatrice` |
| everything else | `Adwaita` (default) |

## How it works

The `watcher` service polls `noctalia.wallpaperPath()` per output
(`poll_interval_ms`, default 2000ms) and writes one `cursor_theme=` line to
`~/.config/mango/config.conf` per poll at most. Live-apply is via
`mmsg setoption` (fallback `reload_config`) plus `gsettings` for GTK apps —
no manual `SUPER+SHIFT+r` needed.

Multi-output policy is **last-change-wins**: the most recently changed output
decides the single global `cursor_theme`. Outputs are sorted by connector
name so ties resolve deterministically; the winner is remembered across polls
so steady state doesn't flap.

## Settings

| Key | Type | Default | Notes |
|---|---|---|---|
| `default_cursor` | string | `Adwaita` | Used when no `folder_map` key matches. |
| `folder_map` | string_map | see `plugin.toml` | Wallpaper path substring → cursor theme. |
| `cursor_size` | int | `24` | Applied via `gsettings` (8–96). |
| `enable_notifications` | bool | `true` | `noctalia.notify` on each switch. |
| `enforce_dark_mode` | bool | `true` | Set the theme back to dark on every wallpaper switch. |
| `poll_interval_ms` | int (advanced) | `2000` | Poll cadence (500–10000). |

Requires the cursor themes in `~/.local/share/icons/` and Mango
(`cursor_theme=` in `~/.config/mango/config.conf`).

## Install (local dev)

```
./install-plugin.sh --enable
# switch wallpapers, then check Noctalia logs for "wallpaper-cursor:"
```

This disables the Stage 1 hook (`cursor-wallpaper.toml` moved aside) so only
the plugin writes `cursor_theme`. To go back: `./install-plugin.sh
--uninstall && ./install.sh && noctalia msg config-reload`.

## Bar widget + panel

- **Widget** (`walt/wallpaper-cursor:indicator`): bar capsule showing the
  active cursor theme (glyph + name, name toggleable via `show_label`).
  Click opens the panel, right-click opens the plugin settings.
- **Panel** (`walt/wallpaper-cursor:board`): two jobs only.
  1. **Set wallpaper** — folder dropdown, image dropdown, Set button
     (focused output, first known output fallback). The service follows
     with the matching cursor.
  2. **Set cursor** — cursor dropdown + Save button. Save writes the
     `folder = "cursor"` row straight into the plugin settings
     (`folder_map`), keeping a `.bak-wallpaper-cursor` backup and
     reloading config so the service adopts it. Shows a Saved note.
- **Pick from disk**: all dropdowns list real on-disk names (wallpaper
  subfolders under `wallpaper_root`, cursor themes with a `cursors/` dir
  under `icon_root`, image files by extension). Two folder shortcut
  buttons open the roots (`xdg-open`).

Add the widget through the Noctalia Settings UI (Bar → add widget → pick
the indicator) — do not hand-edit `~/.local/state/noctalia/settings.toml`,
it is GUI-owned and manual edits get overwritten.

## Tests

Self-contained stub-host suite, no running Noctalia needed (stock `lua` only):

```
lua plugin/tests/service_test.lua   # from the repo root, expect ALL PASS
```

Covers all three folder mappings, unmatched/nil paths, steady-state silence,
missing `cursor_theme=` line, missing Mango config, multi-output
last-change-wins (changed-wins, tie, no-flap), poll-interval and notification
toggles. Run it after any `service.luau` change, before the live
wallpaper-switch test.
