import QtQuick
import qs.Commons

// "STEP 1  Select Image": Upscayl's step badge followed by its title.
Row {
  id: root

  property int step: 1
  property string title: ""

  spacing: Style.spacing.md

  Rectangle {
    anchors.verticalCenter: parent.verticalCenter
    width: badge.implicitWidth + 2 * Style.spacing.md
    height: badge.implicitHeight + Style.spacing.xs * 2
    radius: Style.cornerRadius > 0 ? height / 2 : 0
    color: Style.selectedAccentFill
    border.width: 1
    border.color: Color.accent

    Text {
      textFormat: Text.PlainText
      id: badge
      anchors.centerIn: parent
      text: "STEP " + root.step
      color: Color.accent
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }

  Text {
    textFormat: Text.PlainText
    anchors.verticalCenter: parent.verticalCenter
    text: root.title
    color: Color.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.subtitle
    font.bold: true
  }
}
