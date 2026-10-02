import QtQuick
import Quickshell
import qs.Commons

// The application window: Upscayl's sidebar on the left, the image viewer on
// the right, plus drag and drop and keyboard shortcuts. File and folder
// pickers are deliberately not QtQuick.Dialogs: App runs bin/omascayl-pick,
// which shows the portal's dialog in another process (see App.choose*).
FloatingWindow {
  id: win

  required property var app

  title: "Omascayl"
  color: Color.background
  implicitWidth: 1280
  implicitHeight: 820
  minimumSize: Qt.size(900, 580)

  onVisibleChanged: if (!visible) app.quit()

  // Used by shell.qml's OMASCAYL_SNAPSHOT development hook only.
  function applySnapshotState(s) {
    if (s.tab) sidebar.tab = s.tab
    if (s.scroll) sidebar.scrollTo(s.scroll)
    if (s.batch) app.setBatchFolder(s.batch)
    if (s.image) app.setImage(s.image, false)
    if (s.result) {
      app.resultRevision += 1
      app.upscaledImagePath = s.result
      app.resultSize = s.resultSize || null
    }
    if (s.batchResult) app.upscaledBatchFolderPath = s.batchResult
    if (s.viewMode) app.settings.set("viewMode", s.viewMode)
    if (s.zoom) app.settings.set("zoom", s.zoom)
    if (s.split !== undefined) viewer.compare.split = s.split
    if (s.pointer) {
      viewer.compare.forceHover = true
      viewer.compare.pointer = Qt.point(s.pointer[0], s.pointer[1])
    }
    if (s.progress) {
      var u = app.upscaler
      u.mode = s.progress.mode || "single"
      u.pass = s.progress.pass || 1
      u.percent = s.progress.percent !== undefined ? s.progress.percent : -1
      u.phase = s.progress.phase || "processing"
      u.batchTotal = s.progress.batchTotal || 0
      u.batchDone = s.progress.batchDone || 0
      u.running = true
    }
    if (s.error) app.showError(s.error.title, s.error.description)
    if (s.toast) app.showToast(s.toast)
    if (s.settings) app.settings.update(s.settings)
    if (s.doubleUpscayl) app.doubleUpscayl = true
    if (s.output) app.setOutputFolder(s.output)
    if (s.open) app.openPath(s.open)
    if (s.paste) app.paste()
    if (s.openSetup) Qt.callLater(app.openSetup)
    if (s.noDepsPrompt) {
      app.depsPrompted = true
      app.depsPromptOpen = false
    }
    if (s.choose) s.choose === "image" ? app.chooseImage() : app.chooseFolder(s.choose)
    if (s.run) Qt.callLater(app.upscayl)
    if (s.stopAfter) {
      stopTimer.interval = s.stopAfter
      stopTimer.start()
    }
  }

  Timer {
    id: stopTimer
    interval: 700
    onTriggered: win.app.stop()
  }

  function snapshot(path, done) {
    content.grabToImage(function(result) {
      result.saveToFile(path)
      done()
    })
  }

  Item {
    id: content
    anchors.fill: parent
    focus: true

    Rectangle {
      anchors.fill: parent
      color: Color.background
    }

    Sidebar {
      id: sidebar
      app: win.app
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      width: Math.round(Math.max(340, Math.min(420, win.width * 0.3)))
    }

    Rectangle {
      id: divider
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.left: sidebar.right
      width: Math.max(1, Style.normalBorderWidth)
      color: Style.normalBorderColor
    }

    Viewer {
      id: viewer
      app: win.app
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.left: divider.right
      anchors.right: parent.right
    }

    DropArea {
      id: drop
      anchors.fill: parent
      enabled: !win.app.upscaler.running
      onEntered: function(drag) { drag.accepted = drag.hasUrls }
      onDropped: function(event) {
        if (event.hasUrls) {
          win.app.openUrls(event.urls)
          event.acceptProposedAction()
        }
      }
    }

    // Drop target highlight.
    Rectangle {
      anchors.fill: parent
      anchors.margins: Style.spacing.xxl
      visible: drop.containsDrag
      color: Style.selectedAccentFill
      radius: Style.cornerRadius
      border.width: Math.max(2, Style.selectedBorderWidth)
      border.color: Color.accent

      Text {
        textFormat: Text.PlainText
        anchors.centerIn: parent
        text: "Drop an image or a folder"
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.heading
        font.bold: true
      }
    }

    DepsDialog {
      anchors.fill: parent
      app: win.app
    }

    ErrorDialog {
      anchors.fill: parent
      app: win.app
    }

    Toast {
      app: win.app
      anchors.horizontalCenter: viewer.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.spacing.huge * 2
    }
  }

  Shortcut {
    sequences: [StandardKey.Paste]
    enabled: !win.app.error
    onActivated: win.app.paste()
  }
  Shortcut {
    sequence: "Ctrl+O"
    onActivated: win.app.batchMode ? win.app.chooseFolder("batch") : win.app.chooseImage()
  }
  Shortcut {
    sequences: ["Ctrl+Return", "Ctrl+Enter"]
    onActivated: win.app.upscayl()
  }
  Shortcut {
    sequence: "Escape"
    onActivated: {
      if (win.app.error) win.app.dismissError()
      else if (win.app.upscaler.running) win.app.stop()
    }
  }
  Shortcut {
    sequence: "Ctrl+Q"
    onActivated: win.app.quit()
  }
}
