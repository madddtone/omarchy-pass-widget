import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  property var service: null
  property var shell: null
  property bool opened: false

  function open(payloadJson) {
    root.opened = true
    if (service) { service.refresh(); service.touch(); service.lockNow() }
    Qt.callLater(function () {
      if (vault) vault.keyCatcher.forceActiveFocus()
    })
  }

  function close() { root.opened = false }

  function toggle() { root.opened ? root.close() : root.open("{}") }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-madddtone-pass"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: card
      width: Math.min(Style.space(1080), parent.width - Style.gapsOut * 2)
      height: Math.min(Style.space(660), parent.height - Style.gapsOut * 2)
      anchors.centerIn: parent
      radius: Style.cornerRadius
      color: Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.panelPadding

      MouseArea { anchors.fill: parent; onClicked: {} }

      VaultView {
        id: vault
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        service: root.service
        settings: ({})
        wide: true
        onCloseRequested: root.close()
      }
    }
  }
}
