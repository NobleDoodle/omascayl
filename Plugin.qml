import QtQuick
import Quickshell
import Quickshell.Io
import "src"
import "src/Core.js" as Core

// Omascayl as an omarchy-shell panel plugin: the same app as bin/omascayl's
// standalone mode, hosted by the shell instead of its own Quickshell process.
// It has no bar widget; the launcher entry (bin/omascayl) summons it.
//
// keepLoaded keeps the app state alive between window opens, so closing the
// window during an upscayl lets the job finish in the background.
Item {
  id: root

  // ---- host injections ----------------------------------------------------
  property var shell: null
  property var manifest: null
  property string omarchyPath: ""

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "io.github.nobledoodle.omascayl"
  readonly property string pluginDir: Core.pathFromUrl(Qt.resolvedUrl(".").toString()).replace(/\/+$/, "")

  // Read by the host to answer `toggle`.
  property bool opened: false

  App {
    id: hostedApp
    embedded: true
    toolsDir: root.pluginDir + "/bin"
    onQuitRequested: root.requestClose()
  }

  // ---- host lifecycle -------------------------------------------------------
  // payload: {} or { "path": "/image/or/folder" }
  function open(payloadJson) {
    var p = {}
    try { p = JSON.parse(String(payloadJson || "{}")) || {} } catch (e) { p = {} }
    opened = true
    if (typeof p.path === "string" && p.path) hostedApp.openPath(p.path)
  }

  function close() { opened = false }

  // The window was closed by the user: tell the host, so its open-panel state
  // (and `toggle`) stays right. Deferred, because this runs inside the
  // window's own visibility handler and the host destroys that window.
  function requestClose() {
    if (!opened) return
    Qt.callLater(function() {
      if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
      else root.opened = false
    })
  }

  function summon(payload) {
    var json = JSON.stringify(payload || {})
    if (root.shell && typeof root.shell.summon === "function") root.shell.summon(root.pluginId, json)
    else root.open(json)
  }

  Loader {
    active: root.opened
    sourceComponent: AppWindow {
      app: hostedApp
      visible: true
    }
  }

  // `omarchy plugin add` runs no install hooks, so the plugin installs its own
  // launcher entry, icon and `omascayl` command each time it loads (a no-op
  // once they are in place). They go through a stub outside the plugin folder,
  // which removes them again once the plugin has been removed; unloading asks
  // it to check, and it only acts if this folder really disappears.
  // A relative XDG_DATA_HOME is ignored, as bin/omascayl-integrate ignores it.
  readonly property string launchStub: (Core.isAbsolutePath(Quickshell.env("XDG_DATA_HOME") || "")
                                          ? Quickshell.env("XDG_DATA_HOME")
                                          : Quickshell.env("HOME") + "/.local/share")
                                       + "/omascayl/plugin-launch"

  Component.onCompleted: {
    hostedApp.settings.iconPath = root.pluginDir + "/share/omascayl.svg"
    Quickshell.execDetached({ command: [root.pluginDir + "/bin/omascayl-integrate", "install", root.pluginDir],
                              environment: ({ PATH: Core.TRUSTED_PATH }) })
  }

  Component.onDestruction: {
    if (Core.isAbsolutePath(root.launchStub))
      Quickshell.execDetached({ command: [root.launchStub, "--cleanup-if-removed"],
                                environment: ({ PATH: Core.TRUSTED_PATH }) })
  }

  // omarchy-shell omascayl <method>; bin/omascayl uses these when the plugin
  // is installed.
  IpcHandler {
    target: "omascayl"
    function show(): void { root.summon({}) }
    function open(path: string): void { root.summon(path ? { path: path } : {}) }
    function close(): void { hostedApp.quit() }
    // pick image|batch|output|models: open the window and that picker.
    function pick(purpose: string): void {
      root.summon({})
      if (purpose === "image") hostedApp.chooseImage()
      else hostedApp.chooseFolder(purpose)
    }
    function upscayl(): void { hostedApp.upscayl() }
    function stop(): void { hostedApp.stop() }
    function status(): string {
      return JSON.stringify({
        mode: "plugin",
        open: root.opened,
        running: hostedApp.upscaler.running,
        percent: hostedApp.upscaler.percent,
        image: hostedApp.imagePath,
        folder: hostedApp.batchFolderPath,
        output: hostedApp.outputPath,
        models: hostedApp.settings.customModelsPath,
        picker: hostedApp.pickerOpen,
        error: hostedApp.error ? hostedApp.error.title : "",
        result: hostedApp.upscaledImagePath || hostedApp.upscaledBatchFolderPath,
        backend: hostedApp.backendFound ? hostedApp.settings.binPath : ""
      })
    }
  }
}
