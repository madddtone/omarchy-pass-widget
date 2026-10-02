import QtQuick
import qs.Ui
import qs.Commons

BarWidget {
  id: root

  moduleName: "kalel.pass"

  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("kalel.pass") : null

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened : false

  function _withPanel(method) {
    if (panelLoader.item) { panelLoader.item[method](); return }
    panelLoader.active = true
    Qt.callLater(function () { if (panelLoader.item) panelLoader.item[method]() })
  }

  function open() { _withPanel("open") }
  function toggle() { _withPanel("toggle") }
  function close() { if (panelLoader.item) panelLoader.item.close() }

  function pushSettings() {
    if (!service) return
    service.passCliBin = String(setting("passCliBin", ""))
    service.vaultConfig = String(setting("vaultConfig", ""))
    service.lockMinutes = Number(setting("lockMinutes", 5)) || 0
    service.defaultCopyField = String(setting("defaultCopyField", "password"))
    service.gitRemote = String(setting("gitRemote", ""))
    service.gitAuto = String(setting("gitAuto", "On"))
  }

  onServiceChanged: pushSettings()
  onSettingsChanged: pushSettings()
  Component.onCompleted: pushSettings()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Loader {
    id: panelLoader
    active: false
    visible: false
    sourceComponent: VaultPanel {
      bar: root.bar
      settings: root.settings
      service: root.service
      anchorItem: button
      hostWidget: root
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    active: root.opened
    // The glyph is drawn by the same Text as the label, so it must always be
    // visible; "Show label" only controls whether " Pass" follows the glyph.
    labelVisible: true
    text: String(root.setting("showLabel", "Off")) === "On"
      ? String(root.setting("glyph", "\uF084")) + " Pass"
      : String(root.setting("glyph", "\uF084"))
    tooltipText: root.service && root.service.state === "ready"
      ? "Pass · " + root.service.credentials.length + " credentials"
      : "Pass"

    onPressed: function (buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
      else if (buttonCode === Qt.RightButton) root.bar.run("omarchy-shell shell summon kalel.pass")
      else if (buttonCode === Qt.MiddleButton && root.service) root.service.refresh()
    }
  }
}
