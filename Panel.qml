import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// Text-size popup, terminal-centric.
//
// Top row "Everything" drives `omarchy display text size` — the one knob for
// shell text, GTK text-scaling-factor, and every unpinned terminal.
//
// Below it, one slider per terminal. A moved slider PINS that terminal at a
// size that overrides the global knob; the BarWidget's config watcher
// re-asserts pins whenever anything rewrites a config, so the pin wins. The ✕
// on a pinned row unpins it and the terminal falls back to the default.
//
// Which terminal rows show: the widget's `terminals` setting (currently just
// foot), plus the terminal focused when the panel opened, plus any terminal
// that holds a pin (a pin must stay reachable to be unpinned).
Panel {
  id: root
  moduleName: "mttmng.terminal-font-size"
  ipcTarget: "mttmng.terminal-font-size"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string helperPath: Qt.resolvedUrl("font-size.sh").toString().replace("file://", "")

  readonly property int minPt: 6
  readonly property int maxPt: 32
  // omarchy-display-text-size accepts 9–20 px.
  readonly property int minPx: 9
  readonly property int maxPx: 20

  // The system default terminal, resolved at every open so the "default"
  // keyword below follows `omarchy default terminal` switches automatically.
  property string defaultTerminal: ""

  // Which terminals the panel always shows, from the widget's shell.json entry:
  //   omarchy bar set mttmng.terminal-font-size terminals "default kitty"
  // "default" stands for whatever the system default terminal is right now.
  readonly property var visibleTerminals: {
    var raw = setting("terminals", "default")
    var list = Array.isArray(raw)
      ? raw
      : String(raw).trim().split(/[\s,]+/).filter(function(s) { return s !== "" })
    return list.map(function(t) { return t === "default" ? root.defaultTerminal : t })
  }

  // The terminal focused when the panel opened, so an ad-hoc terminal gets a
  // row without being added to the setting.
  property string focusedTerminal: ""
  readonly property var classMap: ({
    "foot": "foot",
    "footclient": "foot",
    "alacritty": "alacritty",
    "kitty": "kitty",
    "ghostty": "ghostty",
    "com.mitchellh.ghostty": "ghostty"
  })

  // The global knob (px) and what it means for terminals (pt).
  property int globalPx: 12
  property int defaultPt: 9

  // Every terminal config found on disk; `rows` is the visible subset.
  property var allRows: []
  readonly property var rows: allRows.filter(function(r) {
    return root.visibleTerminals.indexOf(r.key) !== -1
      || r.key === root.focusedTerminal
      || r.pinned
  })
  readonly property bool hasFoot: rows.some(function(r) { return r.key === "foot" })
  readonly property bool anyPinned: rows.some(function(r) { return r.pinned })

  function open() {
    if (!focusProc.running) focusProc.running = true
    if (!defaultProc.running) defaultProc.running = true
    refresh()
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function refresh() {
    if (!getProc.running) getProc.running = true
  }

  function runHelper(args) {
    if (root.bar) root.bar.run("bash " + Util.shellQuote(root.helperPath) + " " + args)
  }

  function displayPxFor(pt) {
    return Math.round(pt * 12 / 9)
  }

  function patchRow(key, pt, pinned) {
    var next = []
    for (var i = 0; i < allRows.length; i++) {
      var r = allRows[i]
      next.push(r.key === key ? { key: r.key, label: r.label, pt: pt, pinned: pinned } : r)
    }
    root.allRows = next
  }

  function setSize(key, pt) {
    pt = Math.max(minPt, Math.min(maxPt, Math.round(pt)))
    runHelper("set " + key + " " + pt)
    patchRow(key, pt, true)
  }

  function clearSize(key) {
    runHelper("clear " + key)
    patchRow(key, root.defaultPt, false)
  }

  function clearAll() {
    runHelper("clear-all")
    var next = []
    for (var i = 0; i < allRows.length; i++) {
      var r = allRows[i]
      next.push({ key: r.key, label: r.label, pt: root.defaultPt, pinned: false })
    }
    root.allRows = next
  }

  // The one knob for everything. The command rewrites the terminal configs
  // too, and the BarWidget's watcher re-asserts every pin right after, so
  // pinned rows keep their size. The optimistic pass moves the unpinned rows;
  // the delayed refresh reads the truth back once the command has run.
  function setGlobal(px) {
    px = Math.max(minPx, Math.min(maxPx, Math.round(px)))
    if (root.bar) root.bar.run("omarchy-display-text-size " + px)
    root.globalPx = px
    root.defaultPt = Math.round(px * 9 / 12)
    var next = []
    for (var i = 0; i < allRows.length; i++) {
      var r = allRows[i]
      next.push(r.pinned ? r : { key: r.key, label: r.label, pt: root.defaultPt, pinned: false })
    }
    root.allRows = next
    refreshTimer.restart()
  }

  Timer {
    id: refreshTimer
    interval: 900
    onTriggered: root.refresh()
  }

  Process {
    id: defaultProc
    command: ["omarchy-default-terminal"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var name = String(text || "").trim().toLowerCase()
        if (name === "foot" || name === "alacritty" || name === "kitty" || name === "ghostty")
          root.defaultTerminal = name
      }
    }
  }

  Process {
    id: focusProc
    command: ["hyprctl", "-j", "activewindow"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var cls = ""
        try { cls = String(JSON.parse(text || "{}").class || "").toLowerCase() } catch (e) {}
        root.focusedTerminal = root.classMap[cls] || ""
      }
    }
  }

  Process {
    id: getProc
    command: ["bash", root.helperPath, "get"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var labels = { foot: "Foot", alacritty: "Alacritty", kitty: "Kitty", ghostty: "Ghostty" }
        var next = []
        var lines = String(text || "").trim().split("\n")
        for (var i = 0; i < lines.length; i++) {
          var parts = lines[i].trim().split(/\s+/)
          if (parts.length < 2) continue
          if (parts[0] === "global") {
            var px = parseInt(parts[1], 10)
            if (isFinite(px) && px > 0) root.globalPx = px
            continue
          }
          if (parts[0] === "default") {
            var def = parseInt(parts[1], 10)
            if (isFinite(def) && def > 0) root.defaultPt = def
            continue
          }
          if (parts.length !== 3 || !labels[parts[0]]) continue
          var pt = parseFloat(parts[1])
          if (!isFinite(pt) || pt <= 0) continue
          next.push({
            key: parts[0],
            label: labels[parts[0]],
            pt: Math.round(pt),
            pinned: parts[2] !== "-"
          })
        }
        root.allRows = next
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(10)

        Text {
          text: "TEXT SIZE"
          color: root.contentForeground
          opacity: 0.6
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1.5
        }

        // ---- The global knob: shell, GTK, and every unpinned terminal.
        Item {
          width: content.width
          height: Style.space(32)

          Text {
            id: globalName
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(84)
            text: "Everything"
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
          }

          Item {
            id: globalSpacer
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(22)
            height: Style.space(22)
          }

          Text {
            id: globalValue
            anchors.right: globalSpacer.left
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(48)
            horizontalAlignment: Text.AlignRight
            text: Math.round(globalSlider.liveValue) + " px"
            color: root.contentForeground
            opacity: 0.8
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }

          PanelSlider {
            id: globalSlider
            anchors.left: globalName.right
            anchors.right: globalValue.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            bar: root.bar
            minimum: root.minPx
            maximum: root.maxPx
            step: 1
            integer: true
            value: root.globalPx
            onReleased: function(v) { root.setGlobal(v) }
          }
        }

        PanelSeparator {
          foreground: root.contentForeground
        }

        // ---- Terminal pins.
        Repeater {
          model: root.rows

          Item {
            id: row
            required property var modelData
            width: content.width
            height: Style.space(32)

            Item {
              id: nameArea
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(84)
              height: parent.height

              Text {
                id: nameLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: row.modelData.label
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
              }

              // Marks the terminal that was focused when the panel opened —
              // the row that shows up ad hoc without being in the setting.
              Rectangle {
                visible: row.modelData.key === root.focusedTerminal
                anchors.left: nameLabel.right
                anchors.leftMargin: Style.space(5)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(5)
                height: width
                radius: width / 2
                color: Color.accent
              }
            }

            // Unpin: back to following the global default. Reserved space even
            // when unpinned so the slider does not resize with pin state.
            Item {
              id: unpin
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(22)
              height: Style.space(22)

              Text {
                anchors.centerIn: parent
                visible: row.modelData.pinned
                text: "✕"
                color: unpinMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Color.accent)
                  : root.contentForeground
                opacity: unpinMouse.containsMouse ? 1 : 0.6
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                id: unpinMouse
                anchors.fill: parent
                enabled: row.modelData.pinned
                hoverEnabled: enabled
                cursorShape: Qt.PointingHandCursor
                onClicked: root.clearSize(row.modelData.key)

                PanelToolTip {
                  visible: unpinMouse.containsMouse
                  text: "Follow the default again"
                  fontFamily: root.contentFontFamily
                }
              }
            }

            Text {
              id: valueLabel
              anchors.right: unpin.left
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(48)
              horizontalAlignment: Text.AlignRight
              text: root.displayPxFor(slider.liveValue) + " px"
              color: row.modelData.pinned ? Color.accent : root.contentForeground
              opacity: row.modelData.pinned ? 1 : 0.6
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
            }

            PanelSlider {
              id: slider
              anchors.left: nameArea.right
              anchors.right: valueLabel.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              bar: root.bar
              minimum: root.minPt
              maximum: root.maxPt
              step: 1
              integer: true
              value: row.modelData.pt
              onReleased: function(v) { root.setSize(row.modelData.key, v) }
            }
          }
        }

        Text {
          visible: root.rows.length === 0
          text: "No terminal configs found"
          color: root.contentForeground
          opacity: 0.6
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          width: content.width
          wrapMode: Text.WordWrap
          text: "Everything scales shell, GTK apps, and unpinned terminals. A moved terminal slider pins that terminal; pins win over the default"
            + (root.hasFoot ? ". Foot applies sizes in new windows." : ".")
          color: root.contentForeground
          opacity: 0.5
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          id: resetLink
          visible: root.anyPinned
          text: "Unpin all · follow the default everywhere"
          color: resetMouse.containsMouse
            ? Style.hoverStateColor(root.contentForeground, Color.accent)
            : root.contentForeground
          opacity: resetMouse.containsMouse ? 1 : 0.7
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          font.underline: resetMouse.containsMouse

          MouseArea {
            id: resetMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.clearAll()
          }
        }
      }
    }
  }
}
