# Terminal font size — Omarchy bar widget

Per-terminal font size pins for [Omarchy](https://omarchy.org/), as a bar
widget with a popup panel. Omarchy's own `omarchy display text size` is one
knob that scales the shell, GTK apps, and every terminal together. This widget
keeps that knob, and adds pins on top: set one terminal's font size, and that
size survives the global knob.

## What the panel shows

- **Everything** — a 9–20 px slider that runs `omarchy display text size`.
  It scales the omarchy shell, GTK text scaling, and every unpinned terminal.
- **One slider per terminal** (8–43 px on the same apparent-size scale as
  Display; stored as 6–32 pt in terminal configs). A moved slider **pins**
  that terminal. A pinned size overrides the global knob: whenever anything
  rewrites the terminal's config, the widget re-asserts the pin within about
  half a second. The ✕ on a pinned row unpins it, and the terminal follows
  the default again.

Which terminal rows appear:

1. The system default terminal (`omarchy default terminal`), resolved at
   every open. Change the default and the panel follows.
2. The terminal focused when the panel opened, marked with an accent dot.
   Open the panel from an ad-hoc kitty window and kitty gets a row.
3. Any terminal that holds a pin. A pin always stays reachable, so it can
   always be removed.

Supported terminals: foot, alacritty, kitty, ghostty — the four Omarchy
ships configs for.

## How it works

- `font-size.sh` owns the config edits. It writes the size line in each
  terminal's own config and nudges the running instance the way the stock
  command does: alacritty watches its file, kitty takes SIGUSR1, ghostty
  SIGUSR2, and foot (no reload signal) gets a restart toast.
- Pins live in `~/.config/omarchy/terminal-font-size.overrides`, one
  `<terminal> <pt>` line each.
- `BarWidget.qml` watches the four terminal configs with Quickshell's
  FileView and runs `font-size.sh apply` on any change. Apply rewrites only
  pinned configs that drifted, so its own writes converge instead of looping.
- A pass at shell start covers rewrites that happened while the shell was
  off.

## Requirements

- Omarchy 4.x (the Quickshell `omarchy-shell` bar)

## Install

```bash
git clone https://github.com/MattMangoni/omarchy-terminal-font-size \
  ~/.config/omarchy/plugins/mttmng.terminal-font-size
bash ~/.config/omarchy/plugins/mttmng.terminal-font-size/install.sh
```

The installer is idempotent: it registers the plugin and places the "Aa"
widget on the right side of the bar, and skips anything already in place.

## Configuration

Which terminals always have a row is the widget's `terminals` setting. The
keyword `default` stands for the current system default terminal:

```bash
# The default terminal only (the shipped default):
omarchy bar set mttmng.terminal-font-size terminals default

# The default terminal plus kitty, always:
omarchy bar set mttmng.terminal-font-size terminals "default kitty"

# A fixed list, ignoring the system default:
omarchy bar set mttmng.terminal-font-size terminals "foot alacritty"
```

Open the panel from a script or keybinding:

```bash
omarchy-shell shell summon mttmng.terminal-font-size
```

## Uninstall

```bash
rm -rf ~/.config/omarchy/plugins/mttmng.terminal-font-size
rm -f ~/.config/omarchy/terminal-font-size.overrides
omarchy-shell shell rescanPlugins
```

Optionally delete the `mttmng.terminal-font-size` entry from
`~/.config/omarchy/shell.json`; the bar ignores it once the plugin is gone.

## License

MIT. The config-edit and reload logic mirrors Omarchy's own
`omarchy-display-text-size` (MIT).
