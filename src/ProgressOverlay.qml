import QtQuick
import qs.Commons
import qs.Ui

// "Doing the Upscayl magic..." card over the viewer while upscayl-bin runs.
Rectangle {
  id: root

  required property var app
  readonly property var upscaler: app.upscaler

  color: Util.alpha(Color.background, 0.72)

  // Swallow clicks so the image underneath can't be dragged mid-run.
  MouseArea { anchors.fill: parent; hoverEnabled: true }

  readonly property string headline: upscaler.mode === "batch"
    ? "Batch Upscayl In Progress: " + upscaler.batchDone + "/" + (upscaler.batchTotal || "?")
    : upscaler.mode === "double" ? "Double Upscayl, pass " + upscaler.pass + " of 2"
    : "Doing the Upscayl magic..."

  readonly property string detail: upscaler.phase === "scaling" ? "Scaling and converting image..."
    : upscaler.percent >= 0 ? upscaler.percent.toFixed(2) + "%"
    : "Hold on..."

  Rectangle {
    anchors.centerIn: parent
    width: Math.min(parent.width - 4 * Style.spacing.huge, Style.space(420))
    height: card.implicitHeight + 2 * Style.spacing.popupPadding
    color: Color.popups.background
    radius: Style.cornerRadius
    border.width: Math.max(1, Style.normalBorderWidth)
    border.color: Color.popups.border

    Column {
      id: card
      anchors.centerIn: parent
      width: parent.width - 2 * Style.spacing.popupPadding
      spacing: Style.spacing.lg

      Logo {
        id: spinner
        anchors.horizontalCenter: parent.horizontalCenter
        size: 40
        SequentialAnimation on opacity {
          running: root.visible
          loops: Animation.Infinite
          NumberAnimation { from: 1; to: 0.35; duration: 700; easing.type: Easing.InOutSine }
          NumberAnimation { from: 0.35; to: 1; duration: 700; easing.type: Easing.InOutSine }
        }
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: root.headline
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.title
        font.bold: true
      }

      Rectangle {
        width: parent.width
        height: Style.space(6)
        radius: Style.cornerRadius > 0 ? height / 2 : 0
        color: Style.selectedFill

        Rectangle {
          height: parent.height
          radius: parent.radius
          width: parent.width * root.upscaler.overall
          color: Color.accent
          Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        }
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: root.detail
        color: Util.alpha(Color.popups.text, 0.7)
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }

      Button {
        anchors.horizontalCenter: parent.horizontalCenter
        bordered: true
        text: "STOP"
        foreground: Color.urgent
        onClicked: root.app.stop()
      }
    }
  }
}
