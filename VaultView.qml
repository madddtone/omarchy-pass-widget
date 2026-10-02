import QtQuick
import qs.Commons
import qs.Ui
import "lib/Parse.js" as Parse

Item {
  id: root

  property var service: null
  property QtObject bar: null
  property var settings: ({})
  property bool wide: false

  readonly property alias keyCatcher: keyCatcher
  signal closeRequested()

  readonly property color fg: Color.menu.text
  readonly property color bg: Color.menu.background
  readonly property color borderColor: Color.menu.border
  readonly property color selBg: Color.menu.selectedBackground
  readonly property color selFg: Color.menu.selectedText
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.menuFamily
  readonly property bool hideUsernames: String(setting("hideUsernames", "Off")) === "On"

  property string query: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property string sortMode: "recent"
  property string toastText: ""
  property bool toastError: false
  property bool confirmDelete: false
  property bool showHelp: false
  property bool formOpen: false
  property bool importOpen: false
  property bool syncOpen: false
  property int tick: 0
  property string pinBuffer: ""
  property string pinError: ""
  readonly property bool pinLocked: service !== null && String(service.requirePin) === "On" && !service.unlocked
  property string revealedPassword: ""
  property string revealService: ""

  readonly property var entries: Parse.filter(root.service ? root.service.credentials : [], root.query, root.sortMode)
  readonly property var selected: (entries.length > 0 && selectedIndex >= 0 && selectedIndex < entries.length) ? entries[selectedIndex] : null

  readonly property var detailRows: {
    var e = root.selected
    if (!e) return []
    var revealed = root.revealService === e.service && root.revealedPassword !== ""
    var rows = []
    if (e.username) rows.push({ label: "Username", value: e.username, field: "username", secret: false, canOpen: false, reveal: false })
    rows.push({
      label: "Password",
      value: revealed ? root.revealedPassword : "••••••••••••",
      field: "password",
      secret: !revealed,
      canOpen: false,
      reveal: true
    })
    if (e.url) rows.push({ label: "Website", value: e.url, field: "url", secret: false, canOpen: true, reveal: false })
    if (e.notes) rows.push({ label: "Notes", value: e.notes, field: "notes", secret: false, canOpen: false, reveal: false })
    if (e.category) rows.push({ label: "Category", value: e.category, field: "category", secret: false, canOpen: false, reveal: false })
    return rows
  }

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function rel(value) {
    root.tick
    return Parse.relativeTime(value)
  }

  onEntriesChanged: {
    if (entries.length === 0) selectedIndex = 0
    else if (selectedIndex >= entries.length) selectedIndex = entries.length - 1
    else if (selectedIndex < 0) selectedIndex = 0
  }

  onSelectedIndexChanged: {
    // Never keep a revealed secret next to a different entry.
    if (selected && selected.service !== revealService) {
      revealedPassword = ""
      revealService = ""
    }
  }

  onQueryChanged: {
    selectedIndex = 0
    cursorActive = entries.length > 0
  }

  function notify(text, error) {
    toastText = String(text || "")
    toastError = error === true
    toastTimer.restart()
  }

  function moveSelection(delta) {
    if (entries.length === 0) return
    cursorActive = true
    selectedIndex = (selectedIndex + delta + entries.length) % entries.length
    listView.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  function selectAbsolute(index) {
    if (entries.length === 0) return
    cursorActive = true
    selectedIndex = Math.max(0, Math.min(index, entries.length - 1))
    listView.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  function copyPassword() {
    if (!selected || !service) return
    service.copyPassword(selected.service)
  }

  function toggleReveal() {
    if (!selected || !service) return
    // Already revealed for this entry -> hide and drop the plaintext.
    if (revealService === selected.service && revealedPassword !== "") {
      revealService = ""
      revealedPassword = ""
      return
    }
    revealService = selected.service
    revealedPassword = ""
    service.revealPassword(selected.service)
  }

  function copyUsername() {
    if (!selected || !service) return
    service.copyField(selected.service, "username")
  }

  function copyTotp() {
    if (!selected || !service) return
    service.copyTotp(selected.service)
  }

  function openSelectedUrl() {
    if (!selected || !service) return
    service.openUrl(selected.url)
  }

  function generate() {
    if (!service) return
    service.generatePassword(20)
  }

  function editSelected() {
    if (!service) return
    if (selected) editForm.loadFrom(selected)
    else addCredential()
    formOpen = true
  }

  function addCredential() {
    if (!service) return
    editForm.reset()
    formOpen = true
  }

  function openImport() {
    if (!service) return
    importForm.reset()
    importOpen = true
  }

  function openSync() {
    if (!service) return
    syncForm.reset()
    syncOpen = true
  }

  function confirmDeleteSelected() {
    if (!selected) return
    confirmDelete = true
  }

  function doDelete() {
    var svc = selected ? selected.service : ""
    confirmDelete = false
    if (service && svc) service.deleteCredential(svc)
  }

  function handlePinKey(event) {
    if (event.key === Qt.Key_Escape) { root.closeRequested(); event.accepted = true; return }
    if (event.key === Qt.Key_Backspace) {
      pinBuffer = pinBuffer.slice(0, -1); pinError = ""; event.accepted = true; return
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (pinBuffer === "") { pinError = "Enter your password"; event.accepted = true; return }
      if (service) service.unlock(pinBuffer)
      event.accepted = true; return
    }
    if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
      pinBuffer = pinBuffer + event.text; pinError = ""; event.accepted = true
    }
  }

  function handleKey(event) {
    if (pinLocked) {
      handlePinKey(event)
      return
    }
    if (syncOpen) {
      syncForm.handleKey(event)
      return
    }
    if (importOpen) {
      importForm.handleKey(event)
      return
    }
    if (formOpen) {
      editForm.handleKey(event)
      return
    }
    if (showHelp) {
      if (event.key === Qt.Key_Escape || event.key === Qt.Key_Question || event.key === Qt.Key_Slash) {
        showHelp = false
        event.accepted = true
      }
      return
    }
    if (confirmDelete) {
      if (confirm.handleKey(event)) event.accepted = true
      return
    }
    if (service && (service.state === "missing" || service.state === "locked" || service.state === "nobinary")) {
      if (event.key === Qt.Key_Escape) { root.closeRequested(); event.accepted = true }
      return
    }

    if (event.key === Qt.Key_Escape) {
      if (query) { query = "" }
      else { root.closeRequested() }
      event.accepted = true
    } else if (Util.editsFilter(event, query)) {
      query = Util.editedFilter(event, query)
      event.accepted = true
    } else if (event.key === Qt.Key_Up) {
      moveSelection(-1); event.accepted = true
    } else if (event.key === Qt.Key_Down) {
      moveSelection(1); event.accepted = true
    } else if (event.key === Qt.Key_PageUp) {
      moveSelection(-6); event.accepted = true
    } else if (event.key === Qt.Key_PageDown) {
      moveSelection(6); event.accepted = true
    } else if (event.key === Qt.Key_Home) {
      selectAbsolute(0); event.accepted = true
    } else if (event.key === Qt.Key_End) {
      selectAbsolute(entries.length - 1); event.accepted = true
    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      sortMode = sortMode === "recent" ? "alpha" : "recent"
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (event.modifiers & Qt.ControlModifier) copyTotp()
      else if (event.modifiers & Qt.ShiftModifier) copyUsername()
      else if (String(setting("defaultCopyField", "password")) === "username") copyUsername()
      else copyPassword()
      event.accepted = true
    } else if (event.key === Qt.Key_Delete) {
      confirmDeleteSelected(); event.accepted = true
    } else if (event.modifiers & Qt.ControlModifier) {
      if (event.key === Qt.Key_G) { generate(); event.accepted = true }
      else if (event.key === Qt.Key_E) { editSelected(); event.accepted = true }
      else if (event.key === Qt.Key_N) { addCredential(); event.accepted = true }
      else if (event.key === Qt.Key_O) { openSelectedUrl(); event.accepted = true }
      else if (event.key === Qt.Key_R) { if (service) service.refresh(); event.accepted = true }
      else if (event.key === Qt.Key_S) { toggleReveal(); event.accepted = true }
      else if (event.key === Qt.Key_I) { openImport(); event.accepted = true }
      else if (event.key === Qt.Key_P) { openSync(); event.accepted = true }
      else if (event.key === Qt.Key_L) { if (service) service.lockNow(); event.accepted = true }
    } else if (event.text === "?") {
      showHelp = true; event.accepted = true
    } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
      query = query + event.text
      event.accepted = true
    }
  }

  Timer {
    id: toastTimer
    interval: 2600
    onTriggered: root.toastText = ""
  }

  Timer {
    id: timeTicker
    interval: 30000
    repeat: true
    running: true
    onTriggered: root.tick++
  }

  Connections {
    target: root.service
    function onFeedback(text, error) { root.notify(text, error) }
    function onLockRequested() { root.closeRequested() }
    function onPasswordRevealed(service, password) {
      if (service === root.revealService) root.revealedPassword = String(password)
    }
    function onPinCheckResult(ok) {
      if (ok) { root.pinBuffer = ""; root.pinError = "" }
      else { root.pinBuffer = ""; root.pinError = "Wrong password" }
    }
  }

  Item {
    id: keyCatcher
    anchors.fill: parent
    focus: true
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function (event) { root.handleKey(event) }
  }

  Column {
    anchors.fill: parent
    spacing: Style.spacing.md

    Rectangle {
      width: parent.width
      height: Style.space(44)
      radius: Style.cornerRadius
      color: "transparent"

      Row {
        anchors.fill: parent
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        spacing: Style.space(10)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "󰍉"
          color: root.fg
          opacity: 0.7
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - Style.space(140)
          text: root.query || "Search vault…"
          color: root.fg
          opacity: root.query ? 1 : 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          elide: Text.ElideRight
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.sortMode === "alpha" ? "A–Z" : "Recent"
          color: root.fg
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Style.normalBorderWidth
        color: Util.alpha(root.borderColor, 0.4)
      }
    }

    Item {
      width: parent.width
      height: parent.height - Style.space(44) - Style.space(26) - Style.spacing.md * 2

      Row {
        anchors.fill: parent
        spacing: Style.spacing.md

        Rectangle {
          visible: root.wide
          width: root.wide ? Style.space(168) : 0
          height: parent.height
          radius: Style.cornerRadius
          color: Util.alpha(root.fg, 0.04)
          clip: true

          Column {
            anchors.fill: parent
            anchors.topMargin: Style.space(8)
            anchors.bottomMargin: Style.space(8)
            spacing: Style.space(2)

            Text {
              width: parent.width
              leftPadding: Style.space(12)
              text: "CATEGORIES"
              color: root.fg
              opacity: 0.45
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              width: parent.width
              leftPadding: Style.space(12)
              topPadding: Style.space(4)
              text: "All  (" + (root.service ? root.service.credentials.length : 0) + ")"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Repeater {
              model: root.service ? root.service.categories : []
              Text {
                required property var modelData
                width: parent.width
                leftPadding: Style.space(12)
                topPadding: Style.space(4)
                text: modelData
                color: root.fg
                opacity: 0.8
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
                MouseArea {
                  anchors.fill: parent
                  onClicked: { root.query = String(modelData); root.cursorActive = true }
                }
              }
            }
          }
        }

        Item {
          width: root.wide ? (parent.width - Style.space(168) - Style.spacing.md) * 0.44
                           : parent.width * 0.46
          height: parent.height
          clip: true

          ListView {
            id: listView
            anchors.fill: parent
            anchors.rightMargin: Style.space(8)
            model: root.entries
            clip: true
            spacing: Style.space(3)
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
              id: rowItem
              required property var modelData
              required property int index

              readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex

              width: ListView.view.width
              height: Style.space(50)
              radius: Style.cornerRadius
              color: hasCursor ? root.selBg : (rowMouse.containsMouse ? Util.alpha(root.fg, 0.07) : "transparent")

              Row {
                anchors.fill: parent
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                spacing: Style.space(10)

                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(26)
                  height: Style.space(26)
                  radius: width / 2
                  color: Util.alpha(Color.accent, 0.22)
                  Text {
                    anchors.centerIn: parent
                    text: String(rowItem.modelData.service || "?").substring(0, 1).toUpperCase()
                    color: rowItem.hasCursor ? root.selFg : root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                }

                Column {
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - Style.space(26) - Style.space(10) - badge.width - Style.space(10)
                  spacing: 1
                  Text {
                    width: parent.width
                    text: rowItem.modelData.service
                    color: rowItem.hasCursor ? root.selFg : root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    elide: Text.ElideRight
                  }
                  Text {
                    width: parent.width
                    visible: !root.hideUsernames && rowItem.modelData.username !== ""
                    text: rowItem.modelData.username
                    color: rowItem.hasCursor ? root.selFg : root.fg
                    opacity: 0.6
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                Text {
                  id: badge
                  anchors.verticalCenter: parent.verticalCenter
                  visible: rowItem.modelData.hasTotp
                  text: "TOTP"
                  color: Color.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                onClicked: function (mouse) {
                  root.cursorActive = true
                  root.selectedIndex = rowItem.index
                  if (mouse.button === Qt.MiddleButton) root.copyUsername()
                }
                onDoubleClicked: {
                  root.cursorActive = true
                  root.selectedIndex = rowItem.index
                  root.copyPassword()
                }
              }
            }
          }

          Text {
            anchors.centerIn: parent
            width: parent.width - Style.space(20)
            horizontalAlignment: Text.AlignHCenter
            visible: root.entries.length === 0
            wrapMode: Text.WordWrap
            text: root.service && root.service.state === "ready" && root.query !== ""
              ? "No matches for “" + root.query + "”"
              : (root.service && root.service.state === "ready" ? "Your vault is empty" : "")
            color: root.fg
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
        }

        Rectangle {
          width: Style.normalBorderWidth
          height: parent.height
          color: Util.alpha(root.borderColor, 0.35)
        }

        Item {
          width: parent.width - (root.wide ? Style.space(168) + Style.spacing.md : 0)
                     - (root.wide ? (parent.width - Style.space(168) - Style.spacing.md) * 0.44 : (parent.width * 0.46))
                     - Style.spacing.md * 2 - Style.normalBorderWidth
          height: parent.height
          clip: true

          Column {
            anchors.fill: parent
            anchors.leftMargin: Style.space(12)
            spacing: Style.space(6)

            Text {
              width: parent.width
              text: root.selected ? root.selected.service : "Select a credential"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              elide: Text.ElideRight
            }

            Row {
              spacing: Style.space(6)
              visible: root.selected && (root.selected.category !== "" || root.selected.hasTotp)
              Rectangle {
                visible: root.selected && root.selected.category !== ""
                height: Style.space(20)
                width: catLabel.width + Style.space(16)
                radius: Style.cornerRadius
                color: Util.alpha(Color.accent, 0.18)
                Text {
                  id: catLabel
                  anchors.centerIn: parent
                  text: root.selected ? root.selected.category : ""
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
              Rectangle {
                visible: root.selected && root.selected.hasTotp
                height: Style.space(20)
                width: totpLabel.width + Style.space(16)
                radius: Style.cornerRadius
                color: Util.alpha(Color.accent, 0.18)
                Text {
                  id: totpLabel
                  anchors.centerIn: parent
                  text: "TOTP"
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }

            Repeater {
              model: root.detailRows
              delegate: Rectangle {
                id: fieldRow
                required property var modelData
                width: parent.width
                height: Style.space(34)
                radius: Style.cornerRadius
                color: fieldMouse.containsMouse ? Util.alpha(root.fg, 0.07) : "transparent"

                Text {
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(80)
                  text: fieldRow.modelData.label
                  color: root.fg
                  opacity: 0.55
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(86)
                  anchors.right: actionsRow.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  text: fieldRow.modelData.value
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }

                Row {
                  id: actionsRow
                  z: 5
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(12)

                  Text {
                    id: revealButton
                    visible: fieldRow.modelData.reveal === true
                    text: (root.revealService === (root.selected ? root.selected.service : "")
                           && root.revealedPassword !== "") ? "Hide" : "Show"
                    color: Color.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    MouseArea {
                      anchors.fill: parent
                      anchors.margins: -Style.space(5)
                      cursorShape: Qt.PointingHandCursor
                      onClicked: function (mouse) { mouse.accepted = true; root.toggleReveal() }
                    }
                  }

                  Text {
                    id: copyHint
                    text: "Copy"
                    visible: fieldMouse.containsMouse
                    color: Color.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Text {
                    id: openButton
                    visible: fieldRow.modelData.canOpen
                    text: "Open"
                    color: Color.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    MouseArea {
                      anchors.fill: parent
                      anchors.margins: -Style.space(5)
                      cursorShape: Qt.PointingHandCursor
                      onClicked: function (mouse) {
                        mouse.accepted = true
                        if (root.service) root.service.openUrl(root.selected ? root.selected.url : "")
                      }
                    }
                  }
                }

                MouseArea {
                  id: fieldMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (fieldRow.modelData.field === "password") root.copyPassword()
                    else if (root.service && root.selected) root.service.copyField(root.selected.service, fieldRow.modelData.field)
                  }
                }
              }
            }

            Rectangle {
              visible: root.selected && root.selected.hasTotp
              width: parent.width
              height: Style.space(34)
              radius: Style.cornerRadius
              color: totpMouse.containsMouse ? Util.alpha(root.fg, 0.07) : "transparent"
              Text {
                anchors.left: parent.left
                width: Style.space(80)
                anchors.verticalCenter: parent.verticalCenter
                text: "TOTP"
                color: root.fg
                opacity: 0.55
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(86)
                anchors.verticalCenter: parent.verticalCenter
                text: "Copy code (Ctrl+Enter)"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              MouseArea {
                id: totpMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.copyTotp()
              }
            }

            Rectangle {
              width: parent.width
              height: Style.normalBorderWidth
              visible: root.selected
              color: Util.alpha(root.borderColor, 0.3)
            }

            Text {
              width: parent.width
              visible: root.selected
              wrapMode: Text.WordWrap
              text: root.selected
                ? ("Used " + root.selected.usageCount + "× · last " + (root.rel(root.selected.lastAccessed) || "never")
                   + (root.selected.updatedAt ? " · updated " + root.rel(root.selected.updatedAt) : ""))
                : ""
              color: root.fg
              opacity: 0.55
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }

      Text {
        anchors.centerIn: parent
        width: parent.width - Style.space(40)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        visible: root.service && root.service.state !== "ready"
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        text: root.service ? root.stateMessage(root.service.state) : ""
      }
    }

    Rectangle {
      width: parent.width
      height: Style.space(26)
      color: "transparent"

      Text {
        anchors.left: parent.left
        text: "Enter copy · ⇧Enter user · ^Enter TOTP · ^O open · ^E edit · ^N new · ^I import · ^P sync · ^L lock · Del remove · ^G gen · Tab sort · ? help"
        color: root.fg
        opacity: 0.45
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        width: parent.width
      }
    }
  }

  EditForm {
    id: editForm
    anchors.fill: parent
    visible: root.formOpen
    z: 10
    service: root.service
    bar: root.bar
    wide: root.wide
    onCloseRequested: root.formOpen = false
  }

  ImportForm {
    id: importForm
    anchors.fill: parent
    visible: root.importOpen
    z: 10
    service: root.service
    bar: root.bar
    onCloseRequested: root.importOpen = false
  }

  SyncForm {
    id: syncForm
    anchors.fill: parent
    visible: root.syncOpen
    z: 10
    service: root.service
    bar: root.bar
    onCloseRequested: root.syncOpen = false
  }

  // Password gate: covers everything while locked.
  Rectangle {
    id: pinGate
    anchors.fill: parent
    z: 30
    visible: root.pinLocked
    color: Util.alpha(root.bg, 0.98)
    radius: Style.cornerRadius

    Column {
      anchors.centerIn: parent
      width: Math.min(parent.width - Style.space(80), Style.space(360))
      spacing: Style.space(12)

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "\uF023"
        color: Color.accent
        font.family: root.fontFamily
        font.pixelSize: Style.space(40)
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "Vault locked"
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
      }
      Rectangle {
        width: parent.width
        height: Style.space(40)
        radius: Style.cornerRadius
        color: Util.alpha(root.fg, 0.06)
        border.width: 1
        border.color: root.pinError !== "" ? Color.urgent : Color.accent
        Text {
          anchors.centerIn: parent
          text: root.pinBuffer !== "" ? new Array(root.pinBuffer.length + 1).join("•") : "Enter your password"
          color: root.fg
          opacity: root.pinBuffer !== "" ? 1 : 0.4
          font.family: root.fontFamily
          font.pixelSize: root.pinBuffer !== "" ? Style.font.title : Style.font.body
        }
      }
      Text {
        visible: root.pinError !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.pinError
        color: Color.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: "Unlock with your system password · Enter to unlock · Esc to close"
        color: root.fg
        opacity: 0.5
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  Rectangle {
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: Style.space(10)
    visible: root.toastText !== ""
    width: toastLabel.width + Style.space(24)
    height: Style.space(30)
    radius: Style.cornerRadius
    color: Util.alpha(root.toastError ? Color.urgent : Color.accent, 0.22)
    Text {
      id: toastLabel
      anchors.centerIn: parent
      text: root.toastText
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }
  }

  Rectangle {
    anchors.fill: parent
    visible: root.showHelp
    color: Util.alpha(root.bg, 0.82)
    radius: Style.cornerRadius
    MouseArea { anchors.fill: parent; onClicked: root.showHelp = false }
    Column {
      anchors.centerIn: parent
      width: parent.width - Style.space(60)
      spacing: Style.space(6)
      Text { text: "Pass — keyboard"; color: root.fg; font.family: root.fontFamily; font.pixelSize: Style.font.heading }
      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        color: root.fg
        opacity: 0.85
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        text: "Type to search · ↑/↓ move · Enter copy password · Shift+Enter username · Ctrl+Enter TOTP · Ctrl+O open URL · Ctrl+E edit · Ctrl+N new · Ctrl+I import · Ctrl+P git sync · Ctrl+L lock · Delete remove · Ctrl+G generate · Ctrl+R refresh · Ctrl+S reveal · Tab sort · Esc back"
      }
    }
  }

  ConfirmDialog {
    id: confirm
    anchors.fill: parent
    opened: root.confirmDelete
    message: root.selected ? ("Delete “" + root.selected.service + "”?") : ""
    confirmText: "Delete"
    background: root.bg
    foreground: root.fg
    scrim: Color.menu.scrim
    selectedBackground: root.selBg
    selectedText: root.selFg
    fontFamily: root.fontFamily
    cornerRadius: Style.cornerRadius
    onCanceled: root.confirmDelete = false
    onConfirmed: root.doDelete()
  }

  function stateMessage(state) {
    if (state === "missing") return "No pass-cli vault found. Run “pass-cli init” in a terminal to create one."
    if (state === "locked") return "Vault is locked. Open a terminal and run “pass-cli keychain enable”, or “pass-cli get <service>” to unlock."
    if (state === "nobinary") return "pass-cli is not installed. Install it, then reopen."
    if (state === "error") return root.service && root.service.lastError ? root.service.lastError : "Could not read the vault."
    if (state === "unknown" || state === "") return "Loading…"
    return ""
  }
}
