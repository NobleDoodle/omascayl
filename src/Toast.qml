import QtQuick
import qs.Commons

// Short-lived status line ("Copied", "Already upscayled", ...).
Rectangle {
  id: root

  required property var app

  width: label.implicitWidth + 2 * Style.spacing.xxl
  height: label.implicitHeight + 2 * Style.spacing.md
  radius: Style.cornerRadius
  color: Color.popups.background
  border.width: Math.max(1, Style.normalBorderWidth)
  border.color: Color.popups.border
  opacity: shown ? 1 : 0
  visible: opacity > 0

  property bool shown: false

  Behavior on opacity { NumberAnimation { duration: 160 } }

  Text {
    textFormat: Text.PlainText
    id: label
    anchors.centerIn: parent
    text: root.app.toast
    color: Color.popups.text
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  Timer {
    id: hideTimer
    interval: 3200
    onTriggered: root.shown = false
  }

  Connections {
    target: root.app
    function onToastChanged() {
      if (!root.app.toast) return
      root.shown = true
      hideTimer.restart()
    }
  }
}
