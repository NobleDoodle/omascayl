import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Upscayl's left pane: title, the Upscayl / Settings tabs and their content.
Rectangle {
  id: root

  required property var app
  property string tab: "upscayl"

  color: Style.normalFill

  function scrollTo(y) { flick.contentY = Math.max(0, Math.min(y, flick.contentHeight - flick.height)) }

  Column {
    id: header
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.margins: Style.spacing.panelPadding
    spacing: Style.spacing.md

    Row {
      spacing: Style.spacing.lg

      Logo {
        size: Style.font.displayLarge + Style.spacing.sm
        anchors.verticalCenter: parent.verticalCenter
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.xxs

        Text {
          textFormat: Text.PlainText
          text: "Omascayl"
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.display
          font.bold: true
        }
        Text {
          textFormat: Text.PlainText
          text: "AI Image Upscaler"
          color: Util.alpha(Color.foreground, 0.6)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
      }
    }

    Segmented {
      id: tabs
      width: parent.width
      options: [
        { value: "upscayl", label: "Upscayl" },
        { value: "settings", label: "Settings" }
      ]
      value: root.tab
      onChanged: function(v) { root.tab = v }
    }
  }

  Flickable {
    id: flick
    anchors.top: header.bottom
    anchors.topMargin: Style.spacing.xxl
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    contentHeight: body.implicitHeight + Style.spacing.panelPadding
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar {
      policy: flick.contentHeight > flick.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
      contentItem: Rectangle {
        implicitWidth: Style.space(4)
        radius: width / 2
        color: Util.alpha(Color.foreground, 0.35)
      }
    }

    Item {
      id: body
      width: flick.width
      implicitHeight: root.tab === "settings" ? settingsTab.implicitHeight : upscaylTab.implicitHeight

      UpscaylTab {
        id: upscaylTab
        app: root.app
        visible: root.tab === "upscayl"
        x: Style.spacing.panelPadding
        width: parent.width - 2 * Style.spacing.panelPadding
      }

      SettingsTab {
        id: settingsTab
        app: root.app
        visible: root.tab === "settings"
        x: Style.spacing.panelPadding
        width: parent.width - 2 * Style.spacing.panelPadding
      }
    }
  }
}
