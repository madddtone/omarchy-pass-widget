import QtQuick
import qs.Ui
import qs.Commons

Panel {
  id: root

  moduleName: "kalel.pass"
  ipcTarget: "kalel.pass"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null

  readonly property var barIdentity: hostWidget || root

  function open() {
    if (service) { service.refresh(); service.touch() }
    root.controller.show()
    Qt.callLater(function () { if (root.opened) setCenterHoverRevealSuppressed(true) })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }

  function toggle() { root.opened ? root.close() : root.open() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: vault.keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(700))
    contentHeight: panel.fittedContentHeight(Style.space(520))

    VaultView {
      id: vault
      anchors.fill: parent
      service: root.service
      bar: root.bar
      settings: root.settings
      onCloseRequested: root.close()
    }
  }
}
