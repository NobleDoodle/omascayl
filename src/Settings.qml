import QtQuick
import Quickshell
import Quickshell.Io
import "Core.js" as Core

// Persisted preferences and usage stats (Upscayl keeps both in localStorage),
// plus the backend locations the launcher resolved.
Item {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: Quickshell.env("OMASCAYL_STATE_DIR") || ((Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/omascayl")
  readonly property string cacheDir: Quickshell.env("OMASCAYL_CACHE_DIR") || ((Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/omascayl")
  property string binPath: Quickshell.env("OMASCAYL_BIN") || "upscayl-bin"
  property string modelsPath: Quickshell.env("OMASCAYL_MODELS") || "/usr/share/upscayl/models"
  property string picturesDir: Quickshell.env("OMASCAYL_PICTURES") || home + "/Pictures"
  property string iconPath: Quickshell.env("OMASCAYL_ICON") || "image-x-generic"

  readonly property var defaults: ({
    model: Core.DEFAULT_MODEL,
    scale: "4",
    format: "png",
    compression: 0,
    gpuId: "",
    tileSize: 0,
    useCustomWidth: false,
    customWidth: 0,
    tta: false,
    customModelsPath: "",
    rememberOutputFolder: false,
    outputFolder: "",
    overwrite: false,
    notifications: true,
    viewMode: "slider",
    zoom: 100,
    knownGpus: [],
    stats: { total: 0, image: 0, batch: 0, double: 0, averageMs: 0, lastMs: 0, lastUsedAt: 0 }
  })

  property var st: clone(defaults)
  property bool ready: false

  readonly property string model: st.model || Core.DEFAULT_MODEL
  readonly property string scale: String(st.scale || "4")
  readonly property string format: Core.FORMATS.indexOf(st.format) !== -1 ? st.format : "png"
  readonly property int compression: Math.max(0, Math.min(100, st.compression | 0))
  readonly property string gpuId: st.gpuId || ""
  readonly property int tileSize: Math.max(0, st.tileSize | 0)
  readonly property bool useCustomWidth: !!st.useCustomWidth
  readonly property int customWidth: Math.max(0, st.customWidth | 0)
  readonly property bool tta: !!st.tta
  readonly property string customModelsPath: st.customModelsPath || ""
  readonly property bool rememberOutputFolder: !!st.rememberOutputFolder
  readonly property string outputFolder: st.outputFolder || ""
  readonly property bool overwrite: !!st.overwrite
  readonly property bool notifications: st.notifications !== false
  readonly property string viewMode: st.viewMode === "lens" ? "lens" : "slider"
  readonly property int zoom: Math.max(100, Math.min(400, st.zoom | 0))
  readonly property var knownGpus: st.knownGpus || []
  readonly property var stats: st.stats || defaults.stats

  function clone(v) { return JSON.parse(JSON.stringify(v)) }

  function set(key, value) {
    var patch = {}
    patch[key] = value
    update(patch)
  }

  function update(patch) {
    var next = {}
    for (var k in st) next[k] = st[k]
    for (var p in patch) next[p] = patch[p]
    st = next
    saveTimer.restart()
  }

  function reset() {
    st = clone(defaults)
    flush()
  }

  function rememberGpus(list) { update({ knownGpus: list }) }

  // Upscayl's "more options" counters.
  function recordRun(mode, ms) {
    var s = clone(stats)
    s.averageMs = (s.averageMs * s.total + ms) / (s.total + 1)
    s.total += 1
    if (mode === "batch") s.batch += 1
    else s.image += 1
    if (mode === "double") s.double += 1
    s.lastMs = ms
    s.lastUsedAt = Date.now()
    update({ stats: s })
  }

  function flush() {
    saveTimer.stop()
    if (ready) stateFile.setText(JSON.stringify(st, null, 1))
  }

  Timer {
    id: saveTimer
    interval: 400
    onTriggered: root.flush()
  }

  FileView {
    id: stateFile
    path: root.stateDir + "/settings.json"
    atomicWrites: true
    printErrors: false
    // Never blockLoading: this runs inside omarchy-shell, and a FIFO (or a
    // huge file) planted at settings.json would stall the whole desktop shell,
    // its lock screen included, at startup. Loaded asynchronously, it can only
    // keep Omascayl on its defaults.
    blockLoading: false
    onLoaded: {
      try {
        var s = JSON.parse(text())
        var next = root.clone(root.defaults)
        for (var k in s) next[k] = s[k]
        root.st = next
      } catch (e) {
        console.warn("omascayl: ignoring unreadable settings:", e)
      }
      root.ready = true
    }
    onLoadFailed: root.ready = true
  }
}
