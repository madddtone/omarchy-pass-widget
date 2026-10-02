import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

Item {
  id: root

  property var service: null
  property bool wide: false

  // mode: "add" | "edit"
  property string mode: "add"
  property string targetService: ""

  property string fService: ""
  property string fUsername: ""
  property string fUrl: ""
  property string fCategory: ""
  property string fNotes: ""
  property string fPassword: ""
  property bool autoGenerate: true
  property int genLength: 20
  property int focusIndex: 0
  property string errorText: ""

  signal closeRequested()

  readonly property color fg: Color.menu.text
  readonly property color bg: Color.menu.background
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.menuFamily
  property QtObject bar: null

  // Row indices. Layout: 0 = mode toggle, 1..n = fields, n+1 = save.
  // Fields are service, username, [password], website, category, notes.
  readonly property bool passwordVisible: !autoGenerate
  readonly property int fieldCount: passwordVisible ? 6 : 5
  readonly property int toggleRow: 0
  readonly property int passwordRow: 3
  readonly property int saveRow: fieldCount + 1
  readonly property int maxRow: fieldCount + 1

  function setField(key, text) {
    if (key === "service") fService = text
    else if (key === "username") fUsername = text
    else if (key === "url") fUrl = text
    else if (key === "category") fCategory = text
    else if (key === "notes") fNotes = text
    else if (key === "password") fPassword = text
    root.errorText = ""
  }

  function fieldRows() {
    var rows = [
      { key: "service", label: "Service", value: fService },
      { key: "username", label: "Username", value: fUsername }
    ]
    if (passwordVisible)
      rows.push({ key: "password", label: "Password", value: fPassword, secret: true })
    rows.push({ key: "url", label: "Website", value: fUrl })
    rows.push({ key: "category", label: "Category", value: fCategory })
    rows.push({ key: "notes", label: "Notes", value: fNotes })
    return rows
  }

  function loadFrom(entry) {
    mode = "edit"
    targetService = entry.service
    fService = entry.service
    fUsername = entry.username
    fUrl = entry.url
    fCategory = entry.category
    fNotes = entry.notes
    fPassword = ""
    // Editing must not silently rotate the password: default to "keep it".
    autoGenerate = false
    focusIndex = 1
  }

  function reset() {
    mode = "add"
    targetService = ""
    fService = ""
    fUsername = ""
    fUrl = ""
    fCategory = ""
    fNotes = ""
    fPassword = ""
    autoGenerate = true
    genLength = 20
    focusIndex = 1
    errorText = ""
  }

  function keyForIndex(i) {
    if (i === toggleRow) return "toggle"
    if (i === saveRow) return "save"
    var rows = fieldRows()
    var row = rows[i - 1]
    return row ? row.key : ""
  }

  function moveFocus(delta) {
    var count = maxRow + 1
    focusIndex = (focusIndex + delta + count) % count
  }

  function typeInto(text) {
    var key = keyForIndex(focusIndex)
    if (key === "toggle" || key === "save" || key === "") return
    var row = fieldRows()[focusIndex - 1]
    setField(key, String(row ? row.value : "") + text)
  }

  function backspace() {
    var key = keyForIndex(focusIndex)
    if (key === "toggle" || key === "save" || key === "") return
    var row = fieldRows()[focusIndex - 1]
    setField(key, String(row ? row.value : "").slice(0, -1))
  }

  function toggleMode() {
    autoGenerate = !autoGenerate
    if (autoGenerate) fPassword = ""
    if (focusIndex > maxRow) focusIndex = maxRow
    // Landing on the mode row just toggled: move into the password field so
    // the next keystroke is the password, not a second toggle.
    if (!autoGenerate && focusIndex === toggleRow) focusIndex = passwordRow
    else if (autoGenerate && focusIndex === passwordRow) focusIndex = toggleRow
  }

  function save() {
    if (!service) return
    if (mode === "add" && !fService.trim()) { errorText = "Service name is required"; return }
    if (!autoGenerate && String(fPassword) === "" && mode === "add") {
      errorText = "Enter a password, or switch to Auto-generate"
      focusIndex = passwordRow
      return
    }
    if (mode === "add") {
      // Service.addCredential(service, username, url, category, notes, password, autoGenerate)
      service.addCredential(fService, fUsername, fUrl, fCategory, fNotes,
                            autoGenerate ? "" : fPassword, autoGenerate)
    } else {
      // Service.updateCredential(service, username, url, category, notes, autoGenerate, password)
      service.updateCredential(targetService, fUsername, fUrl, fCategory, fNotes,
                               autoGenerate, autoGenerate ? "" : fPassword)
    }
    root.closeRequested()
  }

  function handleKey(event) {
    if (event.key === Qt.Key_Escape) { root.closeRequested(); event.accepted = true; return }
    if (event.key === Qt.Key_Down) { moveFocus(1); event.accepted = true; return }
    if (event.key === Qt.Key_Up) { moveFocus(-1); event.accepted = true; return }
    if (event.key === Qt.Key_Tab) { moveFocus((event.modifiers & Qt.ShiftModifier) ? -1 : 1); event.accepted = true; return }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (focusIndex === toggleRow) { toggleMode(); event.accepted = true; return }
      save(); event.accepted = true; return
    }
    if (event.key === Qt.Key_Space && focusIndex === toggleRow) { toggleMode(); event.accepted = true; return }
    if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) { backspace(); event.accepted = true; return }
    if (event.key === Qt.Key_Left || event.key === Qt.Key_Right || event.key === Qt.Key_Home || event.key === Qt.Key_End) {
      event.accepted = true; return
    }
    if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
      typeInto(event.text); event.accepted = true
    }
  }

  function dots(value) {
    var n = Math.min(String(value || "").length, 24)
    var s = ""
    for (var i = 0; i < n; i++) s += "•"
    return s
  }

  Rectangle {
    anchors.fill: parent
    color: Util.alpha(root.bg, 0.97)
    radius: Style.cornerRadius

    Column {
      anchors.fill: parent
      anchors.margins: Style.spacing.md
      spacing: Style.space(6)

      Text {
        text: root.mode === "add" ? "New credential" : ("Edit " + root.targetService)
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
      }

      // ---- Password mode toggle --------------------------------------------
      Rectangle {
        readonly property bool focused: root.focusIndex === root.toggleRow
        width: parent.width
        height: Style.space(38)
        radius: Style.cornerRadius
        color: focused ? Util.alpha(Color.accent, 0.18) : Util.alpha(root.fg, 0.05)
        border.width: focused ? 1 : 0
        border.color: Color.accent

        Row {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(6)
          anchors.right: parent.right
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(6)

          Repeater {
            model: [ { label: root.mode === "add" ? "Auto-generate" : "Generate new", wantsAuto: true },
                     { label: root.mode === "add" ? "Enter password" : "Keep / enter", wantsAuto: false } ]
            delegate: Rectangle {
              required property var modelData
              readonly property bool selected: root.autoGenerate === modelData.wantsAuto
              width: (parent.width - Style.space(12)) / 2
              height: Style.space(28)
              radius: Style.cornerRadius
              color: selected ? Util.alpha(Color.accent, 0.35) : "transparent"
              Text {
                anchors.centerIn: parent
                text: modelData.label
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.autoGenerate = modelData.wantsAuto
                  if (root.autoGenerate) {
                    root.fPassword = ""
                    root.focusIndex = root.toggleRow
                  } else {
                    // Jump straight into the password field so typing lands there.
                    root.focusIndex = root.passwordRow
                  }
                }
              }
            }
          }
        }
      }

      // ---- Fields ----------------------------------------------------------
      Repeater {
        model: {
          var rows = root.fieldRows()
          for (var i = 0; i < rows.length; i++) rows[i].rowIndex = i + 1
          return rows
        }
        delegate: Rectangle {
          id: fRow
          required property var modelData
          readonly property bool focused: root.focusIndex === modelData.rowIndex
          readonly property bool secretField: modelData.key === "password"
          width: parent.width
          height: Style.space(38)
          radius: Style.cornerRadius
          color: focused ? Util.alpha(Color.accent, 0.18) : Util.alpha(root.fg, 0.05)
          border.width: focused ? 1 : 0
          border.color: Color.accent

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(90)
            text: fRow.modelData.label
            color: root.fg
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
          Text {
            id: fValue
            anchors.left: parent.left
            anchors.leftMargin: Style.space(100)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            text: fRow.secretField
              ? (fRow.modelData.value ? root.dots(fRow.modelData.value) : (fRow.focused ? "" : "—"))
              : (fRow.modelData.value || (fRow.focused ? "" : "—"))
            color: root.fg
            opacity: fRow.modelData.value ? 1 : 0.4
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }
          Rectangle {
            visible: fRow.focused
            x: Math.min(fValue.x + fValue.contentWidth + Style.space(1), parent.width - Style.space(10))
            anchors.verticalCenter: parent.verticalCenter
            width: Style.normalBorderWidth
            height: Style.font.body
            color: Color.accent
            SequentialAnimation on opacity {
              loops: Animation.Infinite
              NumberAnimation { to: 0.15; duration: 500 }
              NumberAnimation { to: 1; duration: 500 }
            }
          }
          MouseArea {
            anchors.fill: parent
            onClicked: root.focusIndex = fRow.modelData.rowIndex
          }
        }
      }

      Rectangle {
        readonly property bool focused: root.focusIndex === root.saveRow
        width: parent.width
        height: Style.space(38)
        radius: Style.cornerRadius
        color: focused ? Util.alpha(Color.accent, 0.28) : Util.alpha(Color.accent, 0.16)
        Text {
          anchors.centerIn: parent
          text: root.mode === "add" ? "Create" : "Save changes"
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            root.focusIndex = root.saveRow
            root.save()
          }
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
        width: parent.width
        wrapMode: Text.WordWrap
        text: {
          if (root.autoGenerate)
            return root.mode === "add"
              ? "pass-cli will generate and store a password."
              : "A new password will be generated, replacing the current one."
          if (root.focusIndex === root.passwordRow && (root.fPassword || "") === "")
            return "Leave empty to keep the current password, or type a new one."
          return root.mode === "add"
            ? "Type the password you want to store."
            : "The typed password will replace the current one."
        }
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
