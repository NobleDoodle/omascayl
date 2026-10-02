import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Core.js" as Core

// Upscayl's Settings tab. Theme and language are left out (the window follows
// the Omarchy theme), as are auto-update, telemetry and Upscayl Cloud.
Column {
  id: root

  required property var app
  readonly property var settings: app.settings
  readonly property var upscaler: app.upscaler
  readonly property color muted: Util.alpha(Color.foreground, 0.62)

  spacing: Style.spacing.huge

  component Caption: Text {
    textFormat: Text.PlainText
    width: parent ? parent.width : 0
    color: root.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  component Section: Column {
    property string title: ""
    width: parent ? parent.width : 0
    spacing: Style.spacing.md
    PanelSectionHeader { text: parent.title }
  }

  Section {
    title: "SAVE IMAGE AS"
    Segmented {
      width: parent.width
      options: Core.FORMATS.map(function(f) { return { value: f, label: f.toUpperCase() } })
      value: root.settings.format
      onChanged: function(v) { root.settings.set("format", v) }
    }
  }

  Section {
    title: "IMAGE COMPRESSION (" + root.settings.compression + "%)"
    ThemeSlider {
      width: parent.width
      minimum: 0
      maximum: 100
      step: 5
      integer: true
      value: root.settings.compression
      onMoved: function(v) { root.settings.set("compression", Math.round(v)) }
    }
    Caption {
      text: "PNG compression is lossless, so it might not reduce the file size significantly and higher compression values might affect the performance. JPG and WebP compression is lossy."
    }
  }

  Section {
    title: "GPU"
    Dropdown {
      width: parent.width
      showLabel: false
      options: {
        var out = [{ value: "", label: "Auto" }]
        var list = root.upscaler.gpus
        for (var i = 0; i < list.length; i++)
          out.push({ value: String(list[i].id), label: list[i].id + ": " + list[i].name })
        if (root.settings.gpuId && !out.some(function(o) { return o.value === root.settings.gpuId }))
          out.push({ value: root.settings.gpuId, label: "GPU " + root.settings.gpuId })
        return out
      }
      value: root.settings.gpuId
      onChanged: function(v) { root.settings.set("gpuId", v) }
    }
    Button {
      bordered: true
      text: root.upscaler.probingGpus ? "Detecting GPUs..." : "Detect GPUs"
      enabled: !root.upscaler.probingGpus
      onClicked: root.upscaler.probeGpus()
    }
    Caption {
      text: "Auto lets upscayl-bin pick a device. Pick another GPU if upscaling fails or is slow on the default one."
    }
  }

  Section {
    title: "CUSTOM TILE SIZE"
    NumberField {
      from: 0
      to: 2048
      stepSize: 32
      value: root.settings.tileSize
      onModified: function(v) { root.settings.set("tileSize", v) }
    }
    Caption {
      text: "Use a custom tile size for segmenting the image. This can help process images faster by reducing the number of tiles generated. 0 is automatic."
    }
  }

  Section {
    title: "CUSTOM OUTPUT WIDTH"
    Toggle {
      width: parent.width
      label: "Use custom width"
      description: "The height is adjusted automatically. This overrides the scale setting."
      checked: root.settings.useCustomWidth
      onClicked: {
        var on = !root.settings.useCustomWidth
        var patch = { useCustomWidth: on }
        if (on && root.settings.customWidth <= 0) patch.customWidth = 1920
        root.settings.update(patch)
      }
    }
    NumberField {
      visible: root.settings.useCustomWidth
      label: "Width (px)"
      from: 1
      to: 65535
      stepSize: 100
      value: root.settings.customWidth
      onModified: function(v) { root.settings.set("customWidth", v) }
    }
  }

  Toggle {
    width: parent.width
    label: "TTA Mode"
    description: "Test Time Augmentation gives better results, such as removing artifacts, BUT increases processing time by 8x!"
    checked: root.settings.tta
    onClicked: root.settings.set("tta", !root.settings.tta)
  }

  Section {
    title: "ADD CUSTOM MODELS"
    Row {
      spacing: Style.spacing.sm
      Button {
        bordered: true
        text: "Select Folder"
        onClicked: root.app.chooseFolder("models")
      }
      Button {
        bordered: true
        visible: root.settings.customModelsPath !== ""
        text: "Remove"
        onClicked: root.app.clearCustomModels()
      }
    }
    Caption {
      text: root.settings.customModelsPath
        ? root.settings.customModelsPath + "\n" + root.app.customModels.length + " model(s): " + root.app.customModels.join(", ")
        : "Pick a folder of NCNN models (.param + .bin pairs). Models with x2/2x or x3/3x in the name are treated as 2x/3x models. Upscayl's custom-models repository on GitHub has many."
    }
  }

  Toggle {
    width: parent.width
    label: "Save Output Folder"
    description: "If enabled, the output folder will be remembered between sessions."
    checked: root.settings.rememberOutputFolder
    onClicked: {
      var on = !root.settings.rememberOutputFolder
      root.settings.update({ rememberOutputFolder: on, outputFolder: on ? root.app.outputPath : root.settings.outputFolder })
    }
  }

  Toggle {
    width: parent.width
    label: "Overwrite Previous Upscale"
    description: "If enabled, Omascayl will process the image again instead of loading the existing result."
    checked: root.settings.overwrite
    onClicked: root.settings.set("overwrite", !root.settings.overwrite)
  }

  Toggle {
    width: parent.width
    label: "Turn Off Notifications"
    description: "If enabled, Omascayl will not send desktop notifications on success or failure."
    checked: !root.settings.notifications
    onClicked: root.settings.set("notifications", !root.settings.notifications)
  }

  Section {
    title: "LOGS"
    Row {
      spacing: Style.spacing.sm
      Button {
        bordered: true
        text: "Copy Logs"
        enabled: root.upscaler.logLines.length > 0
        onClicked: root.app.copyText(root.upscaler.logLines.join("\n"))
      }
      Button {
        bordered: true
        text: "Clear"
        enabled: root.upscaler.logLines.length > 0
        onClicked: root.upscaler.clearLogs()
      }
    }
    Rectangle {
      width: parent.width
      height: Style.space(150)
      color: Style.normalFill
      radius: Style.cornerRadius
      border.width: Style.normalBorderWidth
      border.color: Style.normalBorderColor

      Flickable {
        id: logFlick
        anchors.fill: parent
        anchors.margins: Style.spacing.md
        clip: true
        contentWidth: width
        contentHeight: logText.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        onContentHeightChanged: contentY = Math.max(0, contentHeight - height)
        ScrollBar.vertical: ScrollBar {}

        TextEdit {
          textFormat: TextEdit.PlainText
          id: logText
          width: logFlick.width
          readOnly: true
          selectByMouse: true
          wrapMode: TextEdit.WrapAnywhere
          text: root.upscaler.logLines.length ? root.upscaler.logLines.join("\n") : "No logs to show"
          color: root.muted
          selectionColor: Style.selectionFill
          font.family: "monospace"
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  Section {
    title: "USAGE"
    Caption {
      text: "Total upscayls: " + root.settings.stats.total
        + "   (images " + root.settings.stats.image + ", batches " + root.settings.stats.batch
        + ", double " + root.settings.stats.double + ")\n"
        + "Average time: " + Core.formatDuration(root.settings.stats.averageMs)
        + "   Last: " + Core.formatDuration(root.settings.stats.lastMs)
    }
  }

  Section {
    title: "DEPENDENCIES"
    Repeater {
      model: root.app.deps
      delegate: Text {
        required property var modelData
        width: parent ? parent.width : 0
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        color: modelData.state === "ok" ? Color.foreground
             : modelData.need === "required" ? Color.urgent : root.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        text: (modelData.state === "ok" ? "✓ " : "✗ ") + modelData.label
          + (modelData.state === "ok" ? "" : (modelData.need === "required" ? "  (required)" : "  (recommended)"))
      }
    }
    Caption {
      visible: root.app.deps.length === 0
      text: root.app.depsChecked ? "Not checked (bin/omascayl-deps was not found)." : "Checking..."
    }
    Row {
      spacing: Style.spacing.sm
      Button {
        bordered: true
        text: root.app.setupRunning ? "Setup is open..." : "Run setup"
        enabled: !root.app.setupRunning
        onClicked: root.app.openSetup()
      }
      Button {
        bordered: true
        text: "Check again"
        onClicked: root.app.recheck()
      }
    }
    Caption {
      text: "Setup opens in a terminal, shows what it will install, and asks once before installing."
    }
  }

  Section {
    title: "BACKEND"
    Caption {
      text: "upscayl-bin: " + root.settings.binPath + (root.app.backendFound ? "" : "  (not found)")
        + "\nModels: " + root.settings.modelsPath + " (" + root.app.installedModels.length + ")"
    }
  }

  Button {
    bordered: true
    text: "Reset Omascayl"
    tooltipText: "Restore every setting to its default"
    onClicked: {
      root.settings.reset()
      root.app.refreshModels()
      root.app.showToast("Settings reset")
    }
  }
}
