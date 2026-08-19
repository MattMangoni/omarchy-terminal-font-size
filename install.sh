#!/usr/bin/env bash
# Installer for the Terminal font size bar widget.
# Idempotent: safe to re-run, skips everything already in place.
#   bash install.sh
set -euo pipefail

PLUGIN_ID="mttmng.terminal-font-size"
PLUGIN_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$PLUGIN_ID"
REPO_URL="https://github.com/MattMangoni/omarchy-terminal-font-size"
SHELL_JSON="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/shell.json"

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
skip() { printf '\033[1;32m ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m !!\033[0m %s\n' "$*"; }

command -v omarchy >/dev/null || { warn "This installer needs an Omarchy system."; exit 1; }

# 1. Plugin files ------------------------------------------------------------
if [[ -f "$PLUGIN_DIR/manifest.json" ]]; then
  skip "Plugin files are already at $PLUGIN_DIR"
else
  say "Cloning the plugin into $PLUGIN_DIR"
  git clone "$REPO_URL" "$PLUGIN_DIR"
fi

chmod +x "$PLUGIN_DIR/font-size.sh"

# 2. Register with the shell -------------------------------------------------
say "Registering the widget with omarchy-shell"
omarchy-shell shell rescanPlugins || true

if [[ -f "$SHELL_JSON" ]] && grep -q "$PLUGIN_ID" "$SHELL_JSON"; then
  skip "Widget is already placed on the bar"
else
  say "Placing the widget on the right side of the bar"
  omarchy bar put "$PLUGIN_ID" --section right
fi

say "Done. Click the Aa label on the bar to open the panel."
say "The panel shows the system default terminal; see README.md to add more."
