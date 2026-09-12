#!/usr/bin/env bash
# install-plugin.sh - install the Stage 2 service plugin (local dev drop-in).
# Symlinks plugin/ to $XDG_DATA_HOME/noctalia/plugins/wallpaper-cursor so repo
# edits hot-reload (.luau) or apply on config reload (plugin.toml).
# Disables the Stage 1 hook to avoid double-writes to Mango's config.
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_SRC="$REPO_DIR/plugin"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
DEST_DIR="$DATA_HOME/noctalia/plugins/wallpaper-cursor"
HOOK_TOML="$HOME/.config/noctalia/cursor-wallpaper.toml"
PLUGIN_ID="walt/wallpaper-cursor"

usage() {
  echo "usage: $(basename "$0") [--enable] [--keep-hook] [--uninstall]"
  echo "  (no args)   link plugin into data dir (hook disabled unless --keep-hook)"
  echo "  --enable    also run: noctalia msg plugins enable $PLUGIN_ID"
  echo "  --keep-hook leave the Stage 1 hook wiring in place (not recommended:"
  echo "              hook + plugin both write cursor_theme)"
  echo "  --uninstall remove the data-dir link (hook stays as-is)"
}

ENABLE=0
KEEP_HOOK=0
UNINSTALL=0
for arg in "$@"; do
  case "$arg" in
    --enable) ENABLE=1 ;;
    --keep-hook) KEEP_HOOK=1 ;;
    --uninstall) UNINSTALL=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $arg" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ "$UNINSTALL" == 1 ]]; then
  rm -f "$DEST_DIR"
  echo "uninstalled plugin link: $DEST_DIR"
  echo "re-enable hook if wanted: ./install.sh && noctalia msg config-reload"
  exit 0
fi

[[ -f "$PLUGIN_SRC/plugin.toml" ]] || { echo "missing $PLUGIN_SRC/plugin.toml"; exit 1; }
[[ -f "$HOME/.config/mango/config.conf" ]] || { echo "missing ~/.config/mango/config.conf"; exit 1; }

mkdir -p "$(dirname "$DEST_DIR")"
ln -sfn "$PLUGIN_SRC" "$DEST_DIR"
echo "installed: $DEST_DIR -> $PLUGIN_SRC"

if [[ "$KEEP_HOOK" == 0 && -e "$HOOK_TOML" ]]; then
  mv "$HOOK_TOML" "$HOOK_TOML.disabled-by-plugin-$(date +%Y%m%d-%H%M%S)"
  echo "disabled Stage 1 hook: $HOOK_TOML (moved aside)"
  if command -v noctalia >/dev/null 2>&1; then
    noctalia msg config-reload 2>/dev/null || true
  fi
elif [[ "$KEEP_HOOK" == 1 ]]; then
  echo "warning: hook left in place; hook + plugin both write cursor_theme."
fi

if [[ "$ENABLE" == 1 ]]; then
  noctalia msg plugins enable "$PLUGIN_ID"
else
  echo "enable with: noctalia msg plugins enable $PLUGIN_ID"
fi
