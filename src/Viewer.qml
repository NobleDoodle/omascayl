import QtQuick
import qs.Commons
import qs.Ui
import "Core.js" as Core

// Upscayl's right pane: the drop target when empty, the selected image, the
// before/after comparison once upscayled, the batch folder status, and the
// progress overlay over all of them.
Item {
  id: root

  required property var app
  readonly property var settings: app.settings
  readonly property var upscaler: app.upscaler
  readonly property color muted: Util.alpha(Color.foreground, 0.62)

  readonly property alias compare: compare
  readonly property bool hasImage:!app.batchMode && app.imagePath !== ""
  readonly property bool hasResult: hasImage && app.upscaledImagePath !== ""
  readonly property string beforeUrl: hasImage ? Core.fileUrl(app.imagePath) : ""
  readonly property string afterUrl: hasResult ? Core.fileUrl(app.upscaledImagePath) + "?r=" + app.resultRevision : ""

  clip: true

  component Line: Text {
    textFormat: Text.PlainText
    anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
    width: Math.min(implicitWidth, root.width - 4 * Style.spacing.huge)
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.WordWrap
    color: Color.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  // ---- empty state / batch status -----------------------------------------------
  Column {
    anchors.centerIn: parent
    spacing: Style.spacing.lg
    visible: !root.hasImage

    Logo {
      anchors.horizontalCenter: parent.horizontalCenter
      size: 72
      tint: Util.alpha(Color.accent, root.app.batchMode && root.app.batchFolderPath ? 1 : 0.8)
    }

    // Nothing selected yet.
    Column {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.spacing.md
      visible: !root.app.batchMode || root.app.batchFolderPath === ""

      Line {
        text: root.app.batchMode ? "Select a Folder" : "Select an Image"
        font.pixelSize: Style.font.display
        font.bold: true
      }
      Line {
        text: root.app.batchMode
          ? "Make sure that the folder doesn't contain anything except PNG, JPG, JPEG & WEBP images."
          : "Select or drag and drop a PNG, JPG, JPEG or WEBP image."
        color: root.muted
      }
      Line {
        visible: !root.app.batchMode
        text: "Hit Ctrl+V to paste an image from the clipboard"
        color: root.muted
      }
      Item { width: 1; height: Style.spacing.sm }
      Button {
        anchors.horizontalCenter: parent.horizontalCenter
        bordered: true
        text: root.app.batchMode ? "Select Folder" : "Select Image"
        onClicked: root.app.batchMode ? root.app.chooseFolder("batch") : root.app.chooseImage()
      }
    }

    // Batch folder chosen, or done.
    Column {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.spacing.md
      visible: root.app.batchMode && root.app.batchFolderPath !== ""

      Line {
        text: root.app.upscaledBatchFolderPath ? "All done!" : "Selected folder:"
        font.pixelSize: root.app.upscaledBatchFolderPath ? Style.font.display : Style.font.title
        font.bold: true
      }
      Line {
        text: root.app.upscaledBatchFolderPath || root.app.batchFolderPath
        color: root.muted
      }
      Item { width: 1; height: Style.spacing.sm }
      Button {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.app.upscaledBatchFolderPath !== ""
        bordered: true
        text: "Open Upscayled Folder"
        onClicked: root.app.revealFolder(root.app.upscaledBatchFolderPath)
      }
    }
  }

  // ---- image / comparison ---------------------------------------------------------
  CompareView {
    id: compare
    anchors.fill: parent
    anchors.margins: Style.spacing.huge
    anchors.bottomMargin: infoBar.height + 2 * Style.spacing.huge
    visible: root.hasImage
    beforeSource: root.beforeUrl
    afterSource: root.afterUrl
    mode: root.settings.viewMode
    zoom: root.settings.zoom / 100

    onBeforeLoaded: function(w, h) {
      root.app.inputWidth = w
      root.app.inputHeight = h
    }
  }

  // Top-right tools, like Upscayl's "more options" drawer.
  Row {
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.margins: Style.spacing.huge
    spacing: Style.spacing.sm
    visible: root.hasImage && !root.upscaler.running

    Segmented {
      visible: root.hasResult
      width: Style.space(170)
      options: [{ value: "slider", label: "Slider" }, { value: "lens", label: "Lens" }]
      value: root.settings.viewMode
      onChanged: function(v) { root.settings.set("viewMode", v) }
    }

    Rectangle {
      visible: root.hasResult
      width: zoomRow.implicitWidth + 2 * Style.spacing.md
      height: Style.spacing.controlHeight
      color: Color.background
      radius: Style.cornerRadius
      border.width: Style.normalBorderWidth
      border.color: Style.normalBorderColor

      Row {
        id: zoomRow
        anchors.centerIn: parent
        spacing: Style.spacing.md
        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          text: "Zoom " + root.settings.zoom + "%"
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
        ThemeSlider {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(110)
          minimum: 100
          maximum: 400
          step: 25
          integer: true
          value: root.settings.zoom
          onMoved: function(v) { root.settings.set("zoom", Math.round(v / 25) * 25) }
        }
      }
    }

    Button {
      bordered: true
      background: Color.background
      text: "Reset Image"
      onClicked: root.app.resetImage()
    }
  }

  // Bottom info bar: sizes and where the result went.
  Rectangle {
    id: infoBar
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: Style.spacing.huge
    height: Style.spacing.controlHeight + Style.spacing.md
    visible: root.hasImage
    color: "transparent"

    Text {
      textFormat: Text.PlainText
      anchors.left: parent.left
      anchors.right: actions.left
      anchors.rightMargin: Style.spacing.lg
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideMiddle
      color: root.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      text: {
        var s = Core.baseName(root.app.imagePath)
        if (root.app.inputWidth > 0) s += "  " + root.app.inputWidth + "x" + root.app.inputHeight
        if (root.hasResult) {
          s += "   ->   " + Core.baseName(root.app.upscaledImagePath)
          if (root.app.resultSize) s += "  " + root.app.resultSize.width + "x" + root.app.resultSize.height
        }
        return s
      }
    }

    Row {
      id: actions
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.sm
      visible: root.hasResult

      Button {
        bordered: true
        text: "Open Image"
        onClicked: root.app.openExternally(root.app.upscaledImagePath)
      }
      Button {
        bordered: true
        text: "Open Folder"
        onClicked: root.app.revealFolder(Core.dirName(root.app.upscaledImagePath))
      }
      Button {
        bordered: true
        text: "Copy Path"
        onClicked: root.app.copyText(root.app.upscaledImagePath)
      }
    }
  }

  // ---- backend missing ------------------------------------------------------------
  Rectangle {
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.margins: Style.spacing.huge
    visible: !root.app.backendFound
    height: Math.max(missing.implicitHeight, setupButton.height) + 2 * Style.spacing.lg
    color: Util.alpha(Color.urgent, 0.15)
    radius: Style.cornerRadius
    border.width: 1
    border.color: Color.urgent

    Text {
      textFormat: Text.PlainText
      id: missing
      anchors.left: parent.left
      anchors.right: setupButton.left
      anchors.verticalCenter: parent.verticalCenter
      anchors.margins: Style.spacing.lg
      wrapMode: Text.WordWrap
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      text: "Upscayl's engine and models aren't installed yet, so nothing can be upscayled."
    }

    Button {
      id: setupButton
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.rightMargin: Style.spacing.lg
      bordered: true
      text: root.app.setupRunning ? "Setup is open..." : "Set up Omascayl"
      enabled: !root.app.setupRunning
      onClicked: root.app.openSetup()
    }
  }

  ProgressOverlay {
    anchors.fill: parent
    app: root.app
    visible: root.upscaler.running
  }
}
