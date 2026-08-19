import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar label for the per-terminal font size panel. The click opens a popup
// with one slider per terminal config found on disk; Panel.qml owns the
// sliders and the config writes.
//
// This widget also keeps the pins honest: it watches the four terminal
// configs and runs `font-size.sh apply` whenever one changes, so a pinned
// size is re-asserted right after `omarchy display text size` (or anything
// else) rewrites it. Apply only writes on drift, so its own writes converge
// instead of looping the watcher.
BarWidget {
  id: root
  moduleName: "mttmng.terminal-font-size"

  readonly property string helperPath: Qt.resolvedUrl("font-size.sh").toString().replace("file://", "")
  readonly property string home: Quickshell.env("HOME")

  function scheduleApply() {
    applyTimer.restart()
  }

  // Debounced: the global command rewrites all four configs in one burst, and
  // one apply pass covers every pin.
  Timer {
    id: applyTimer
    interval: 400
    onTriggered: if (root.bar) root.bar.run("bash " + Util.shellQuote(root.helperPath) + " apply")
  }

  // Startup pass covers rewrites that happened while the shell was off.
  Component.onCompleted: scheduleApply()

  FileView { path: root.home + "/.config/foot/foot.ini"; watchChanges: true; printErrors: false; onFileChanged: root.scheduleApply() }
  FileView { path: root.home + "/.config/alacritty/alacritty.toml"; watchChanges: true; printErrors: false; onFileChanged: root.scheduleApply() }
  FileView { path: root.home + "/.config/kitty/kitty.conf"; watchChanges: true; printErrors: false; onFileChanged: root.scheduleApply() }
  FileView { path: root.home + "/.config/ghostty/config"; watchChanges: true; printErrors: false; onFileChanged: root.scheduleApply() }

  // ---- Popup. Shape contract for shell.summon/hide/toggle routing:
  //      Bar.findPanelWidget requires open/close/opened on the bar-widget root.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "mttmng.terminal-font-size"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "Aa"
    fontSize: Style.font.caption
    horizontalMargin: 6
    tooltipText: "Terminal font size"
    onPressed: function() { root.togglePanel() }
  }
}
