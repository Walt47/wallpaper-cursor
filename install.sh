#!/usr/bin/env bash
# install.sh - idempotent install of the Stage 1 hook. No Noctalia restart needed
# for hooks (config stack reloads); Mango needs SUPER+SHIFT+r after cursor changes.
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$REPO_DIR/hooks/wallpaper-cursor.sh"
SRC_TOML="$REPO_DIR/noctalia/cursor-wallpaper.toml"
DEST_TOML="$HOME/.config/noctalia/cursor-wallpaper.toml"

chmod +x "$HOOK"

# Guard: Stage 2 plugin owns cursor_theme once installed. Re-enabling the
# hook alongside it would double-write Mango's config.
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
if [[ -e "$DATA_HOME/noctalia/plugins/wallpaper-cursor" ]]; then
  echo "refusing: Stage 2 plugin is installed ($DATA_HOME/noctalia/plugins/wallpaper-cursor)."
  echo "hook + plugin both write cursor_theme. Remove it first:"
  echo "  ./install-plugin.sh --uninstall"
  echo "  noctalia msg plugins disable walt/wallpaper-cursor"
  exit 1
fi

# Mango backup (first install only keeps one timestamped copy).
[[ -f "$HOME/.config/mango/config.conf" ]] || { echo "missing ~/.config/mango/config.conf"; exit 1; }
ls "$HOME"/.config/mango/config.conf.bak-cursor-install-* >/dev/null 2>&1 \
  || cp -a "$HOME/.config/mango/config.conf" "$HOME/.config/mango/config.conf.bak-cursor-install-$(date +%Y%m%d-%H%M%S)"

# Link wiring (symlink so repo edits take effect immediately).
ln -sfn "$SRC_TOML" "$DEST_TOML"

echo "installed: $DEST_TOML -> $SRC_TOML"
echo "test: NOCTALIA_WALLPAPER_PATH=\$HOME/Pictures/Wallpapers/Umineko/Beatrice.png $HOOK"
echo "then reload Noctalia config: noctalia msg config-reload"
