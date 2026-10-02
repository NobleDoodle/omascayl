import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Modal error card (Upscayl's error toasts carry a "Copy Error" action; this
// keeps that and waits for the user instead of timing out).
Rectangle {
  id: root

  required property var app

  visible: app.error !== null
  color: Util.alpha(Color.background, 0.6)

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    onClicked: root.app.dismissError()
  }

  Rectangle {
    anchors.centerIn: parent
    width: Math.min(parent.width - 4 * Style.spacing.huge, Style.space(520))
    height: Math.min(parent.height - 4 * Style.spacing.huge, body.implicitHeight + 2 * Style.spacing.popupPadding)
    color: Color.popups.background
    radius: Style.cornerRadius
    border.width: Math.max(1, Style.normalBorderWidth)
    border.color: Color.urgent

    // Clicks on the card must not fall through to the dismiss layer.
    MouseArea { anchors.fill: parent }

    Column {
      id: body
      anchors.fill: parent
      anchors.margins: Style.spacing.popupPadding
      spacing: Style.spacing.lg

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: root.app.error ? root.app.error.title : ""
        color: Color.urgent
        font.family: Style.font.family
        font.pixelSize: Style.font.heading
        font.bold: true
        wrapMode: Text.WordWrap
      }

      TextEdit {
        textFormat: TextEdit.PlainText
        width: parent.width
        readOnly: true
        selectByMouse: true
        wrapMode: TextEdit.Wrap
        text: root.app.error ? root.app.error.description : ""
        color: Color.popups.text
        selectionColor: Style.selectionFill
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }

      Row {
        anchors.right: parent.right
        spacing: Style.spacing.sm

        Button {
          bordered: true
          text: "Copy Error"
          onClicked: root.app.copyText(root.app.error ? root.app.error.title + ": " + root.app.error.description : "")
        }
        Button {
          bordered: true
          text: "Close"
          onClicked: root.app.dismissError()
        }
      }
    }
  }
}
