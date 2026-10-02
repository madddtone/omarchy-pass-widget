import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

Item {
  id: root

  property var service: null
  property QtObject bar: null

  // state: "pick" | "running" | "result"
  property string state: "pick"
  property string curDir: ""
  property string parentDir: ""
  property string homeDir: ""
  property var entries: []
  property int selectedIndex: 0
  property bool overwrite: false
  property bool dryRun: true
  property string pathText: ""
  property var summary: null
  property string errorText: ""
  property int progressDone: 0
  property int progressTotal: 0

  signal closeRequested()

  readonly property color fg: Color.menu.text
  readonly property color bg: Color.menu.background
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.menuFamily

  function reset() {
    state = "pick"
    entries = []
    selectedIndex = 0
    overwrite = false
    dryRun = false
    pathText = ""
    summary = null
    errorText = ""
    progressDone = 0
    progressTotal = 0
    if (service) service.loadImportDir("")
  }

  function displayDir(path) {
    if (!path) return "~"
    if (homeDir && path.indexOf(homeDir) === 0) return "~" + path.substring(homeDir.length)
    return path
  }

  function selectedEntry() {
    if (entries.length > 0 && selectedIndex >= 0 && selectedIndex < entries.length) return entries[selectedIndex]
    return null
  }

  function activate() {
    if (pathText.trim() !== "") { run(pathText.trim()); return }
    var e = selectedEntry()
    if (!e) { errorText = "Nothing selected"; return }
    if (e.type === "dir") { if (service) service.loadImportDir(e.path); return }
    run(e.path)
  }

  function run(path) {
    errorText = ""
    state = "running"
    if (service) service.runImport(path, overwrite, dryRun)
  }

  function goUp() {
    if (parentDir) { if (service) service.loadImportDir(parentDir); return }
    root.closeRequested()
  }

  function moveSelection(delta) {
    if (entries.length === 0) return
    selectedIndex = (selectedIndex + delta + entries.length) % entries.length
  }

  function handleKey(event) {
    if (event.key === Qt.Key_Escape) {
      if (pathText !== "") { pathText = "" }
      else if (root.state === "result") { root.closeRequested() }
      else { goUp() }
      event.accepted = true; return
    }
    if (root.state === "running") return
    if (root.state === "result") {
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.text === " ") {
        root.closeRequested(); event.accepted = true
      }
      return
    }
    if (event.modifiers & Qt.ControlModifier) {
      if (event.key === Qt.Key_D) { root.dryRun = !root.dryRun; event.accepted = true; return }
      if (event.key === Qt.Key_O) { root.overwrite = !root.overwrite; event.accepted = true; return }
    }
    if (event.key === Qt.Key_Down) { moveSelection(1); event.accepted = true; return }
    if (event.key === Qt.Key_Up) { moveSelection(-1); event.accepted = true; return }
    if (event.key === Qt.Key_Left) { goUp(); event.accepted = true; return }
    if (event.key === Qt.Key_Right) {
      var e = selectedEntry()
      if (e && e.type === "dir" && service) service.loadImportDir(e.path)
      event.accepted = true; return
    }
    if (event.key === Qt.Key_Backspace) {
      if (pathText !== "") { pathText = pathText.slice(0, -1); event.accepted = true; return }
      goUp(); event.accepted = true; return
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { activate(); event.accepted = true; return }
    if (event.key === Qt.Key_Tab) { root.overwrite = !root.overwrite; event.accepted = true; return }
    if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
      pathText = pathText + event.text
      event.accepted = true
    }
  }

  function summaryLine() {
    if (!summary) return ""
    if (summary.ok === false && summary.error) return summary.error
    return "Added " + (summary.added || 0) + " · updated " + (summary.updated || 0)
      + " · skipped " + (summary.skipped || 0) + " · failed " + (summary.failed || 0)
  }

  Connections {
    target: root.service
    function onImportDirLoaded(dir, parent, home, list) {
      root.curDir = dir
      root.parentDir = parent
      if (home) root.homeDir = home
      root.entries = list
      root.selectedIndex = 0
      // Prefer the first file so Enter imports immediately.
      for (var i = 0; i < list.length; i++) {
        if (list[i].type === "file") { root.selectedIndex = i; break }
      }
    }
    function onImportFinished(result) {
      root.summary = result
      root.state = "result"
    }
    function onImportProgress(done, total) {
      root.progressDone = done
      root.progressTotal = total
    }
  }

  Rectangle {
    anchors.fill: parent
    color: Util.alpha(root.bg, 0.97)
    radius: Style.cornerRadius

    Column {
      anchors.fill: parent
      anchors.margins: Style.spacing.md
      spacing: Style.space(6)

      Row {
        width: parent.width
        spacing: Style.space(8)
        Text {
          text: "Import credentials"
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
        }
        Text {
          visible: root.state === "pick"
          text: root.displayDir(root.curDir)
          color: root.fg
          opacity: 0.6
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          anchors.verticalCenter: parent.verticalCenter
          elide: Text.ElideLeft
          width: parent.width - Style.space(160)
        }
      }

      // ---- file/dir list ----
      Rectangle {
        visible: root.state === "pick"
        width: parent.width
        height: Math.min(Style.space(300), Math.max(Style.space(80), root.entries.length * Style.space(30)))
        radius: Style.cornerRadius
        color: Util.alpha(root.fg, 0.05)
        clip: true

        ListView {
          id: list
          anchors.fill: parent
          anchors.margins: Style.space(4)
          model: root.entries
          clip: true
          spacing: 2
          delegate: Rectangle {
            id: erow
            required property var modelData
            required property int index
            readonly property bool sel: root.selectedIndex === index
            width: ListView.view.width
            height: Style.space(28)
            radius: Style.cornerRadius
            color: sel ? Util.alpha(Color.accent, 0.3) : (emouse.containsMouse ? Util.alpha(root.fg, 0.06) : "transparent")
            Row {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(10)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)
              Text {
                text: erow.modelData.type === "dir" ? "󰉋" : "󰈙"
                color: Color.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              Text {
                width: parent.width - Style.space(28)
                text: erow.modelData.name + (erow.modelData.type === "dir" ? "/" : "")
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }
            }
            MouseArea {
              id: emouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.selectedIndex = erow.index
              onDoubleClicked: {
                root.selectedIndex = erow.index
                if (root.entries[erow.index].type === "dir") root.service.loadImportDir(root.entries[erow.index].path)
                else root.run(root.entries[erow.index].path)
              }
            }
          }
        }

        Text {
          anchors.centerIn: parent
          visible: root.entries.length === 0
          text: "No subfolders or .csv/.json/.zip here — type a path below"
          color: root.fg
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      // ---- manual path ----
      Rectangle {
        visible: root.state === "pick"
        width: parent.width
        height: Style.space(32)
        radius: Style.cornerRadius
        color: Util.alpha(root.fg, 0.05)
        border.width: root.pathText !== "" ? 1 : 0
        border.color: Color.accent
        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(10)
          anchors.right: parent.right
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          text: root.pathText !== "" ? root.pathText : "…or type a full path, then Enter"
          color: root.fg
          opacity: root.pathText !== "" ? 1 : 0.45
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideLeft
        }
      }

      // ---- options ----
      Row {
        visible: root.state === "pick"
        spacing: Style.space(16)
        Text {
          text: (root.overwrite ? "☑" : "☐") + " Overwrite existing"
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          MouseArea { anchors.fill: parent; anchors.margins: -Style.space(4); cursorShape: Qt.PointingHandCursor; onClicked: root.overwrite = !root.overwrite }
        }
        Text {
          text: (root.dryRun ? "☑" : "☐") + " Preview only (dry run)"
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          MouseArea { anchors.fill: parent; anchors.margins: -Style.space(4); cursorShape: Qt.PointingHandCursor; onClicked: root.dryRun = !root.dryRun }
        }
      }

      Rectangle {
        visible: root.state === "pick"
        width: parent.width
        height: Style.space(36)
        radius: Style.cornerRadius
        color: Util.alpha(Color.accent, 0.16)
        Text {
          anchors.centerIn: parent
          text: root.dryRun ? "Preview" : "Import now"
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
        MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.activate() }
      }

      Column {
        visible: root.state === "running"
        width: parent.width
        spacing: Style.space(8)
        Text {
          text: "Importing…" + (root.progressTotal > 0 ? (" " + root.progressDone + " / " + root.progressTotal) : "")
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
        }
        Rectangle {
          width: parent.width
          height: Style.space(8)
          radius: height / 2
          color: Util.alpha(root.fg, 0.12)
          Rectangle {
            width: root.progressTotal > 0 ? parent.width * Math.min(1, root.progressDone / root.progressTotal) : 0
            height: parent.height
            radius: parent.radius
            color: Color.accent
            Behavior on width { NumberAnimation { duration: 120 } }
          }
        }
        Text {
          text: "Each credential unlocks and saves the vault; ~400 entries takes about a minute."
          color: root.fg
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Column {
        visible: root.state === "result"
        width: parent.width
        spacing: Style.space(6)
        Text {
          text: (root.summary && root.summary.ok) ? "Done" : "Finished with issues"
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
        }
        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          text: root.summaryLine()
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
        Text {
          visible: root.summary && root.summary.dryRun === true
          text: "Dry run — nothing was written."
          color: root.fg
          opacity: 0.6
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
        Text {
          visible: root.summary && root.summary.errors && root.summary.errors.length > 0
          width: parent.width
          wrapMode: Text.WordWrap
          text: root.summary && root.summary.errors ? root.summary.errors.slice(0, 4).map(function (e) { return "• " + e.service + ": " + e.error }).join("\n") : ""
          color: Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
        Text {
          text: "Press Enter to close"
          color: root.fg
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Text {
        visible: root.errorText !== ""
        text: root.errorText
        color: Color.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        visible: root.state === "pick"
        width: parent.width
        wrapMode: Text.WordWrap
        text: "↑/↓ select · →/Enter open folder · ←/Backspace up · Enter imports a file · ^D dry run · ^O overwrite · Esc closes"
        color: root.fg
        opacity: 0.45
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  Item {
    id: keyCatcher
    anchors.fill: parent
    focus: true
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function (event) { root.handleKey(event) }
  }
}
