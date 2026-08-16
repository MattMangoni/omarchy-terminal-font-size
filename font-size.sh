#!/bin/bash

# Per-terminal font size pins that OVERRIDE the global default.
#
# `omarchy display text size` moves every terminal config in lockstep. This
# script keeps its own overrides file; a pinned terminal is re-asserted by
# `apply` whenever anything rewrites its config (the plugin's BarWidget watches
# the four config files and runs `apply` on change). An unpinned terminal
# follows the global command untouched.
#
# Reload nudges match the stock command: alacritty watches its file, kitty
# takes USR1, ghostty USR2, and foot has no reload signal so running windows
# get a restart toast.
#
# Usage:
#   font-size.sh get           # "default <pt>", then "<terminal> <current> <override|->"
#   font-size.sh set <t> <pt>  # pin <t> at <pt> and write its config
#   font-size.sh clear <t>     # unpin <t> and return it to the global default
#   font-size.sh clear-all     # unpin every terminal
#   font-size.sh apply         # re-assert every pin whose config drifted

MIN=6
MAX=32

foot_ini="$HOME/.config/foot/foot.ini"
alacritty_toml="$HOME/.config/alacritty/alacritty.toml"
kitty_conf="$HOME/.config/kitty/kitty.conf"
ghostty_config="$HOME/.config/ghostty/config"
overrides_file="$HOME/.config/omarchy/terminal-font-size.overrides"

TERMINALS=(foot alacritty kitty ghostty)

config_for() {
  case "$1" in
    foot) echo "$foot_ini" ;;
    alacritty) echo "$alacritty_toml" ;;
    kitty) echo "$kitty_conf" ;;
    ghostty) echo "$ghostty_config" ;;
  esac
}

# The px the global command last set (shell.toml base-size, default 12).
base_px() {
  local px=""
  if [[ -f $HOME/.config/omarchy/shell.toml ]]; then
    px="$(awk '
      /^[[:space:]]*\[/ { in_font = ($0 ~ /^[[:space:]]*\[font\]([[:space:]]|$)/); next }
      in_font && /^[[:space:]]*base-size[[:space:]]*=/ {
        v = $0
        sub(/^[^=]*=[[:space:]]*/, "", v)
        sub(/[[:space:]]*(#.*)?$/, "", v)
        print v
        exit
      }
    ' "$HOME/.config/omarchy/shell.toml")"
  fi
  [[ $px =~ ^[0-9]+$ ]] || px=12
  echo "$px"
}

# The pt the global command would put in the terminals right now, through the
# stock 12px == 9pt anchor.
default_pt() {
  awk -v s="$(base_px)" 'BEGIN { printf "%d", int(s * 9 / 12 + 0.5) }'
}

current_pt() {
  local file
  file="$(config_for "$1")"
  [[ -f $file ]] || return 0
  case "$1" in
    foot) grep -oP ':size=\K[0-9.]+' "$file" | head -1 ;;
    alacritty) grep -oP '^size[[:space:]]*=[[:space:]]*\K[0-9.]+' "$file" | head -1 ;;
    kitty) grep -oP '^font_size[[:space:]]+\K[0-9.]+' "$file" | head -1 ;;
    ghostty) grep -oP '^font-size = \K[0-9.]+' "$file" | head -1 ;;
  esac
}

override_for() {
  [[ -f $overrides_file ]] || return 0
  awk -v t="$1" '$1 == t { print $2; exit }' "$overrides_file"
}

record_override() {
  local term="$1" pt="$2" tmp
  mkdir -p "$(dirname "$overrides_file")"
  tmp="$(mktemp)"
  [[ -f $overrides_file ]] && awk -v t="$term" '$1 != t' "$overrides_file" >"$tmp"
  echo "$term $pt" >>"$tmp"
  mv "$tmp" "$overrides_file"
}

remove_override() {
  [[ -f $overrides_file ]] || return 0
  local tmp
  tmp="$(mktemp)"
  awk -v t="$1" '$1 != t' "$overrides_file" >"$tmp"
  mv "$tmp" "$overrides_file"
}

# Same one-toast nudge as omarchy-display-text-size: reuse the notification id
# so repeated writes refresh a single toast instead of stacking a pile.
notify_foot_restart() {
  pgrep -x foot >/dev/null 2>&1 || return 0
  local id_file="${XDG_RUNTIME_DIR:-/tmp}/matteo-terminal-font-size.foot-notif-id"
  local prev_id=""
  [[ -f $id_file ]] && read -r prev_id <"$id_file" 2>/dev/null
  local replace=()
  [[ $prev_id =~ ^[0-9]+$ ]] && replace=(-r "$prev_id")
  local new_id
  new_id="$(omarchy-notification-send \
    "Restart Foot to apply the new terminal font size" \
    "${replace[@]}" -p 2>/dev/null)" || true
  [[ $new_id =~ ^[0-9]+$ ]] && printf '%s\n' "$new_id" >"$id_file"
}

write_size() {
  local term="$1" pt="$2" file
  file="$(config_for "$term")"
  [[ -f $file ]] || return 0
  case "$term" in
    foot)
      sed -i -E "s/(:size=)[0-9.]+/\1$pt/" "$file"
      notify_foot_restart
      ;;
    alacritty)
      sed -i -E "s/^size[[:space:]]*=.*/size = $pt/" "$file"
      ;;
    kitty)
      sed -i -E "s/^font_size[[:space:]]+.*/font_size $pt.0/" "$file"
      pkill -USR1 kitty 2>/dev/null || true
      ;;
    ghostty)
      sed -i -E "s/^font-size = .*/font-size = $pt/" "$file"
      pkill -SIGUSR2 ghostty 2>/dev/null || true
      ;;
  esac
}

valid_term() {
  local t
  for t in "${TERMINALS[@]}"; do [[ $t == "$1" ]] && return 0; done
  echo "Unknown terminal: $1" >&2
  return 1
}

get() {
  echo "global $(base_px)"
  echo "default $(default_pt)"
  local term cur ovr
  for term in "${TERMINALS[@]}"; do
    [[ -f $(config_for "$term") ]] || continue
    cur="$(current_pt "$term")"
    [[ -n $cur ]] || continue
    ovr="$(override_for "$term")"
    echo "$term $cur ${ovr:--}"
  done
}

set_size() {
  local term="$1" pt="$2"
  valid_term "$term" || exit 1
  if [[ ! $pt =~ ^[0-9]+$ ]] || ((pt < MIN || pt > MAX)); then
    echo "Size must be an integer between $MIN and $MAX (pt)." >&2
    exit 1
  fi
  record_override "$term" "$pt"
  write_size "$term" "$pt"
}

clear_one() {
  local term="$1"
  valid_term "$term" || exit 1
  remove_override "$term"
  write_size "$term" "$(default_pt)"
}

clear_all() {
  local term
  for term in "${TERMINALS[@]}"; do
    [[ -n $(override_for "$term") ]] || continue
    remove_override "$term"
    write_size "$term" "$(default_pt)"
  done
}

apply() {
  [[ -f $overrides_file ]] || return 0
  local term pt cur
  while read -r term pt; do
    [[ $pt =~ ^[0-9]+$ ]] || continue
    valid_term "$term" 2>/dev/null || continue
    cur="$(current_pt "$term")"
    [[ -n $cur ]] || continue
    awk -v a="$cur" -v b="$pt" 'BEGIN { exit (a == b) ? 0 : 1 }' && continue
    write_size "$term" "$pt"
  done <"$overrides_file"
}

case "${1:-}" in
  get) get ;;
  set) set_size "${2:-}" "${3:-}" ;;
  clear) clear_one "${2:-}" ;;
  clear-all) clear_all ;;
  apply) apply ;;
  *)
    echo "Usage: font-size.sh get | set <terminal> <pt> | clear <terminal> | clear-all | apply" >&2
    exit 1
    ;;
esac
