import QtQuick
import qs.Commons
import qs.Ui

// First-open dependency prompt: what is missing, why it matters, and a button
// that runs bin/omascayl-setup in a terminal (which explains each item again
// and installs nothing without consent).
Rectangle {
  id: root

  required property var app
  readonly property color muted: Util.alpha(Color.foreground, 0.62)

  visible: app.depsPromptOpen && app.error === null
  color: Util.alpha(Color.background, 0.6)

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
  }

  Rectangle {
    anchors.centerIn: parent
    width: Math.min(parent.width - 4 * Style.spacing.huge, Style.space(560))
    height: Math.min(parent.height - 4 * Style.spacing.huge, body.implicitHeight + 2 * Style.spacing.popupPadding)
    color: Color.popups.background
    radius: Style.cornerRadius
    border.width: Math.max(1, Style.normalBorderWidth)
    border.color: root.app.requiredMissing ? Color.urgent : Color.popups.border

    MouseArea { anchors.fill: parent }

    Column {
      id: body
      anchors.fill: parent
      anchors.margins: Style.spacing.popupPadding
      spacing: Style.spacing.lg

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: root.app.requiredMissing ? "Finish setting up Omascayl" : "A few optional pieces are missing"
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.heading
        font.bold: true
        wrapMode: Text.WordWrap
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: root.app.requiredMissing
          ? "Omascayl can't upscale anything until these are installed:"
          : "Omascayl works without these, but these parts stay unavailable:"
        color: root.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        wrapMode: Text.WordWrap
      }

      Repeater {
        model: root.app.missingDeps

        delegate: Row {
          required property var modelData
          width: body.width
          spacing: Style.spacing.md

          Text {
            textFormat: Text.PlainText
            text: "✗"
            color: modelData.need === "required" ? Color.urgent : root.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Column {
            width: parent.width - Style.space(20)
            spacing: Style.spacing.xxs

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: modelData.label + (modelData.need === "required" ? "  (required)" : "")
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
              wrapMode: Text.WordWrap
            }
            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: modelData.why
              color: root.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: root.app.setupRunning
          ? "Setup is running in a terminal window. Omascayl checks again when it finishes."
          : "Setup opens in a terminal, shows what it will install, and asks once before installing."
        color: root.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      Row {
        anchors.right: parent.right
        spacing: Style.spacing.sm

        Button {
          bordered: true
          text: "Check again"
          visible: root.app.setupRunning
          onClicked: root.app.recheck()
        }
        Button {
          bordered: true
          text: "Not now"
          onClicked: root.app.dismissDepsPrompt()
        }
        Button {
          bordered: true
          text: root.app.setupRunning ? "Setup is open..." : "Open setup in a terminal"
          enabled: !root.app.setupRunning
          background: root.app.setupRunning ? "transparent" : Color.accent
          foreground: root.app.setupRunning ? Color.popups.text : Color.background
          onClicked: root.app.openSetup()
        }
      }
    }
  }

  // Everything installed while it was open: nothing left to say.
  Connections {
    target: root.app
    function onMissingDepsChanged() {
      if (root.app.depsPromptOpen && root.app.missingDeps.length === 0) {
        root.app.depsPromptOpen = false
        root.app.showToast("Everything Omascayl needs is installed")
      }
    }
  }
}
