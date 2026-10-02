import QtQuick
import qs.Commons
import qs.Ui
import "Core.js" as Core

// Upscayl's main sidebar tab: batch toggle, then the four steps (input,
// model, output folder, go).
Column {
  id: root

  required property var app
  readonly property var settings: app.settings
  readonly property bool busy: app.upscaler.running
  readonly property color muted: Util.alpha(Color.foreground, 0.62)

  spacing: Style.spacing.huge

  Toggle {
    width: parent.width
    label: "Batch Upscayl"
    description: "This will let you Upscayl all files in a folder at once"
    checked: root.app.batchMode
    enabled: !root.busy
    onClicked: if (!root.busy) root.app.setBatchMode(!root.app.batchMode)
  }

  // ---- Step 1 -----------------------------------------------------------------
  Column {
    width: parent.width
    spacing: Style.spacing.md

    StepHeader { step: 1; title: root.app.batchMode ? "Select Folder" : "Select Image" }

    Button {
      width: parent.width
      bordered: true
      text: root.app.batchMode ? "Select Folder" : "Select Image"
      enabled: !root.busy
      onClicked: root.app.batchMode ? root.app.chooseFolder("batch") : root.app.chooseImage()
    }

    Text {
      textFormat: Text.PlainText
      width: parent.width
      visible: text !== ""
      text: root.app.batchMode ? root.app.batchFolderPath : Core.baseName(root.app.imagePath)
      color: root.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      elide: Text.ElideMiddle
    }
  }

  // ---- Step 2 -----------------------------------------------------------------
  Column {
    width: parent.width
    spacing: Style.spacing.md

    StepHeader { step: 2; title: "Select AI Model" }

    Dropdown {
      width: parent.width
      showLabel: false
      options: root.app.modelOptions
      value: root.settings.model
      onChanged: function(v) { root.settings.set("model", v) }
    }

    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: root.app.modelDescription
      color: root.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    Toggle {
      width: parent.width
      visible: !root.app.batchMode
      label: "Double Upscayl"
      description: "Run upscayl twice on an image. This may take much longer, and scales above 4X may cause performance issues."
      checked: root.app.doubleUpscayl
      onClicked: if (!root.busy) root.app.doubleUpscayl = !root.app.doubleUpscayl
    }

    // Image scale lives with the model, as in Upscayl 2.x.
    Column {
      width: parent.width
      spacing: Style.spacing.sm
      opacity: root.settings.useCustomWidth ? 0.5 : 1

      Text {
        textFormat: Text.PlainText
        text: "Image Scale (" + root.settings.scale + "X)" + (root.settings.useCustomWidth ? "  DISABLED" : "")
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
      }

      ThemeSlider {
        width: parent.width
        minimum: 1
        maximum: 16
        step: 1
        integer: true
        value: parseInt(root.settings.scale) || 4
        enabled: !root.settings.useCustomWidth
        onMoved: function(v) { root.settings.set("scale", String(Math.round(v))) }
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: root.settings.useCustomWidth
          ? "A custom output width (" + root.settings.customWidth + "px) is set in Settings and overrides the scale."
          : "Anything above 4X (except 16X Double Upscayl) only resizes the image and does not use AI upscaling."
        color: root.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        visible: !root.settings.useCustomWidth && parseInt(root.settings.scale) >= 6
        text: "This may cause performance issues on some devices!"
        color: Color.urgent
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
        wrapMode: Text.WordWrap
      }
    }
  }

  // ---- Step 3 -----------------------------------------------------------------
  Column {
    width: parent.width
    spacing: Style.spacing.md

    StepHeader { step: 3; title: "Output Folder" }

    Button {
      width: parent.width
      bordered: true
      text: "Set Output Folder"
      enabled: !root.busy
      onClicked: root.app.chooseFolder("output")
    }

    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: root.app.outputPath
        ? root.app.outputPath
        : (root.app.batchMode ? "Defaults to Folder's path" : "Defaults to Image's path")
      color: root.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      elide: Text.ElideMiddle
    }
  }

  // ---- Step 4 -----------------------------------------------------------------
  Column {
    width: parent.width
    spacing: Style.spacing.md

    StepHeader { step: 4; title: "Upscayl" }

    Text {
      textFormat: Text.PlainText
      width: parent.width
      visible: !root.app.batchMode && root.app.inputWidth > 0 && root.app.targetSize !== null
      text: root.app.targetSize
        ? "Upscayl from " + root.app.inputWidth + "x" + root.app.inputHeight
          + " to " + root.app.targetSize.width + "x" + root.app.targetSize.height
        : ""
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      wrapMode: Text.WordWrap
    }

    Button {
      id: go
      width: parent.width
      height: Style.spacing.controlHeight + Style.spacing.lg
      text: root.busy ? "Upscayling..." : "Upscayl"
      fontSize: Style.font.title
      bordered: true
      enabled: !root.busy
      background: root.busy ? "transparent" : Color.accent
      foreground: root.busy ? Color.foreground : Color.background
      onClicked: root.app.upscayl()
    }

    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: "Ctrl+Enter to start, Ctrl+V to paste an image"
      color: root.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignHCenter
    }
  }
}
