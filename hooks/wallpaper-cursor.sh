#!/usr/bin/env bash
# wallpaper-cursor.sh - map Noctalia wallpaper -> Mango cursor theme
# Triggered by Noctalia [hooks] wallpaper_changed.
# Env from Noctalia: NOCTALIA_WALLPAPER_PATH, NOCTALIA_WALLPAPER_CONNECTOR
#
# Mapping (per-folder):
#   */Land of the Lustrous/* -> Phosphophyllite
#   */Umineko/*              -> Beatrice
#   * (everything else)      -> Adwaita (default)
#
# This is Stage 1 (hook). Stage 2 plugin reuses the same mapping
# via folder_map defaults 1:1. See ../plugin/plugin.toml.
set -euo pipefail

MANGO_CONF="${MANGO_CONF:-$HOME/.config/mango/config.conf}"
DEFAULT_CURSOR="Adwaita"

map_cursor() {
  local path="${1:-}"
  case "$path" in
    *"/Land of the Lustrous/"*) printf 'Phosphophyllite\n' ;;
    *"/Umineko/"*)              printf 'Beatrice\n' ;;
    *)                          printf '%s\n' "$DEFAULT_CURSOR" ;;
  esac
}

WALLPAPER_PATH="${NOCTALIA_WALLPAPER_PATH:-${1:-}}"
if [[ -z "$WALLPAPER_PATH" ]]; then
  logger -t noctalia-hooks "wallpaper-cursor: no path (NOCTALIA_WALLPAPER_PATH empty), defaulting to $DEFAULT_CURSOR"
  WALLPAPER_PATH="__unmatched__"
fi

CURSOR="$(map_cursor "$WALLPAPER_PATH")"
CONNECTOR="${NOCTALIA_WALLPAPER_CONNECTOR:-}"

if [[ ! -f "$MANGO_CONF" ]]; then
  logger -t noctalia-hooks "wallpaper-cursor: mango conf missing: $MANGO_CONF"
  exit 1
fi

CURRENT="$(grep -m1 '^cursor_theme=' "$MANGO_CONF" | cut -d= -f2 || true)"
if [[ "$CURRENT" == "$CURSOR" ]]; then
  exit 0  # already correct, avoid reload loop (hook fires per-output)
fi

# Backup once per day at most, then update the single cursor_theme line.
BACKUP_DIR="$HOME/.config/mango"
BACKUP_FILE="$BACKUP_DIR/config.conf.bak-cursor-$(date +%Y%m%d)"
[[ -f "$BACKUP_FILE" ]] || cp -a "$MANGO_CONF" "$BACKUP_FILE"

sed -i "s/^cursor_theme=.*/cursor_theme=$CURSOR/" "$MANGO_CONF"

# Live-apply: no manual SUPER+SHIFT+r needed.
# 1. Primary: setoption changes appearance without reloading (no flicker).
# 2. Fallback: script-triggered hot-reload (still no keypress).
if command -v mmsg >/dev/null 2>&1; then
  if ! mmsg -s -d setoption,cursor_theme,"$CURSOR" 2>/dev/null; then
    mmsg -s -d reload_config 2>/dev/null || true
  fi
fi

# 3. GTK apps follow live (Noctalia's gtk template only syncs gtk-theme,
# not cursor). Best-effort: silent when gsettings/dbus unavailable.
if command -v gsettings >/dev/null 2>&1; then
  gsettings set org.gnome.desktop.interface cursor-theme "$CURSOR" 2>/dev/null || true
  gsettings set org.gnome.desktop.interface cursor-size 24 2>/dev/null || true
fi

logger -t noctalia-hooks "wallpaper-cursor: [$CONNECTOR] $WALLPAPER_PATH -> $CURSOR (was: ${CURRENT:-unset}, applied live)."

# Best-effort desktop notification (silent if notify-send missing).
command -v notify-send >/dev/null 2>&1 \
  && notify-send "Cursor: $CURSOR" "$WALLPAPER_PATH" 2>/dev/null || true

# Export for newly launched apps in this shell context (compositor
# already updated live above; this covers XWayland/Qt child processes).
export XCURSOR_THEME="$CURSOR"
export XCURSOR_SIZE=24
