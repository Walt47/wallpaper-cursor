# wallpaper-cursor

Switch Mango cursor theme when the Noctalia wallpaper changes (per-folder).

| Wallpaper folder | Cursor |
|---|---|
| `Pictures/Wallpapers/Land of the Lustrous/*` | `Phosphophyllite` |
| `Pictures/Wallpapers/Umineko/*` | `Beatrice` |
| everything else | `Adwaita` (default) |

Requires the cursor themes in `~/.local/share/icons/` (Phosphophyllite, Beatrice)
and Mango (`cursor_theme=` in `~/.config/mango/config.conf`).

## Stage 1 — hook (ship now)

```
./install.sh
noctalia msg config-reload
# switch wallpapers, then:
journalctl --user -t noctalia-hooks | tail
# Mango applies cursor_theme on reload: SUPER+SHIFT+r
```

Dry-run without switching wallpaper:

```
NOCTALIA_WALLPAPER_PATH=~/Pictures/Wallpapers/Umineko/Beatrice.png ./hooks/wallpaper-cursor.sh
grep ^cursor_theme= ~/.config/mango/config.conf
```

No manual refresh: the hook applies live via `mmsg setoption`
(fallback: script-triggered `reload_config`) + `gsettings` for GTK apps.

## Stage 2 — plugin (promoted)

```
./install-plugin.sh --enable
# switch wallpapers, then check Noctalia logs for "wallpaper-cursor:"
```

`plugin/` holds the `[[service]]` (`plugin.toml`, `service.luau`,
`translations/en.json`, `README.md`). Its `folder_map` defaults mirror the
hook's `case` branches 1:1, plus `cursor_size`, `enable_notifications`, and
`poll_interval_ms` settings. The service polls wallpapers (default 2000ms),
writes `cursor_theme=` once per poll at most (**last-change-wins** across
outputs), and live-applies via `mmsg setoption` + `gsettings` — same as the
hook. Installing the plugin disables the hook wiring so only one writer owns
`cursor_theme`; see `plugin/README.md` for rollback.
