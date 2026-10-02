import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

Item {
  id: root

  property var service: null
  property QtObject bar: null

  property var status: null
  property string message: ""
  property bool messageError: false
  property string remoteText: ""
  property bool busy: false

  signal closeRequested()

  readonly property color fg: Color.menu.text
  readonly property color bg: Color.menu.background
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.menuFamily
  readonly property bool enabled: status && status.enabled === true

  function reset() {
    status = null
    message = ""
    messageError = false
    busy = false
    if (service) {
      remoteText = String(service.gitRemote || "")
      service.gitStatus()
    }
  }

  function refresh() { if (service) service.gitStatus() }

  function push() { if (service) { busy = true; service.gitPush() } }
  function pull() { if (service) { busy = true; service.gitPull() } }
  function initRemote() {
    if (!service) return
    busy = true
    if (remoteText.trim() !== "") service.gitInit(remoteText.trim())
    else service.gitInit("")
  }
  function setRemote() {
    if (service && remoteText.trim() !== "") { busy = true; service.gitSetRemote(remoteText.trim()) }
  }

  function handleKey(event) {
    if (event.key === Qt.Key_Escape) { root.closeRequested(); event.accepted = true; return }
    if (event.key === Qt.Key_R) { refresh(); event.accepted = true; return }
    if (root.enabled) {
      if (event.key === Qt.Key_P || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { push(); event.accepted = true; return }
      if (event.key === Qt.Key_L || event.key === Qt.Key_U) { pull(); event.accepted = true; return }
      return
    }
    // Not initialized: the line is a remote-URL input.
    if (event.key === Qt.Key_Backspace) { remoteText = remoteText.slice(0, -1); event.accepted = true; return }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { initRemote(); event.accepted = true; return }
    if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
      remoteText = remoteText + event.text
      event.accepted = true
    }
  }

  Connections {
    target: root.service
    function onGitStatusLoaded(s) { root.status = s; root.busy = false }
    function onGitResult(r) {
      root.busy = false
      root.message = (r && r.ok) ? "Done" : ((r && r.error) ? String(r.error) : "Failed")
      root.messageError = !(r && r.ok)
      root.refresh()
    }
  }

  Rectangle {
    anchors.fill: parent
    color: Util.alpha(root.bg, 0.97)
    radius: Style.cornerRadius

    Column {
      anchors.fill: parent
      anchors.margins: Style.spacing.md
      spacing: Style.space(8)

      Text {
        text: "Git sync (GitHub)"
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
      }

      // ---- not enabled ----
      Column {
        visible: !root.enabled
        width: parent.width
        spacing: Style.space(8)
        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          text: "Not initialized. Enter a private git remote URL (e.g. git@github.com:you/pass-vault.git) and press Enter, or leave blank to init locally."
          color: root.fg
          opacity: 0.7
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
        Rectangle {
          width: parent.width
          height: Style.space(34)
          radius: Style.cornerRadius
          color: Util.alpha(root.fg, 0.06)
          border.width: 1
          border.color: Color.accent
          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(10)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            text: root.remoteText !== "" ? root.remoteText : "git@github.com:you/pass-vault.git"
            color: root.fg
            opacity: root.remoteText !== "" ? 1 : 0.4
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideLeft
          }
        }
        Rectangle {
          width: parent.width
          height: Style.space(36)
          radius: Style.cornerRadius
          color: Util.alpha(Color.accent, 0.16)
          Text { anchors.centerIn: parent; text: "Initialize"; color: root.fg; font.family: root.fontFamily; font.pixelSize: Style.font.body }
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.initRemote() }
        }
      }

      // ---- enabled ----
      Column {
        visible: root.enabled
        width: parent.width
        spacing: Style.space(8)

        Text {
          width: parent.width
          text: (root.status && root.status.remote ? root.status.remote : "(no remote)") + "  ·  " + (root.status ? root.status.branch : "")
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          readonly property var s: root.status || ({})
          text: {
            var parts = []
            parts.push(s.dirty ? "uncommitted changes" : "clean")
            if ((s.ahead || 0) > 0) parts.push("↑" + s.ahead + " to push")
            if ((s.behind || 0) > 0) parts.push("↓" + s.behind + " to pull")
            if ((s.ahead || 0) === 0 && (s.behind || 0) === 0) parts.push("in sync")
            return parts.join(" · ")
          }
          color: root.fg
          opacity: 0.7
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          visible: root.status && root.status.last
          text: root.status && root.status.last ? ("last commit " + root.status.last) : ""
          color: root.fg
          opacity: 0.45
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Row {
          spacing: Style.space(10)
          Rectangle {
            width: Style.space(140)
            height: Style.space(36)
            radius: Style.cornerRadius
            color: Util.alpha(Color.accent, 0.2)
            Text { anchors.centerIn: parent; text: root.busy ? "…" : "Push (P)"; color: root.fg; font.family: root.fontFamily; font.pixelSize: Style.font.body }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.push() }
          }
          Rectangle {
            width: Style.space(140)
            height: Style.space(36)
            radius: Style.cornerRadius
            color: Util.alpha(root.fg, 0.08)
            Text { anchors.centerIn: parent; text: "Pull (L)"; color: root.fg; font.family: root.fontFamily; font.pixelSize: Style.font.body }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.pull() }
          }
        }

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          text: "Auto-push is " + (String(root.service ? root.service.gitAuto : "On") === "On" ? "on" : "off") + "."
                + " File-level sync of the encrypted vault; use one machine at a time."
          color: root.fg
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Text {
        visible: root.message !== ""
        width: parent.width
        wrapMode: Text.WordWrap
        text: root.message
        color: root.messageError ? Color.urgent : root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        text: root.enabled ? "P push · L pull · R refresh · Esc close" : "Type a remote URL · Enter initialize · Esc close"
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
