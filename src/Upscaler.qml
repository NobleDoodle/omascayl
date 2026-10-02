import QtQuick
import Quickshell
import Quickshell.Io
import "Core.js" as Core

// Runs upscayl-bin for one job at a time: a single image, a Double Upscayl
// (two passes, the second in place on the first's output) or a whole folder.
// Mirrors Upscayl's main-process handlers: the same arguments, the same
// "Error"/"failed" kill rule and the same output naming.
Item {
  id: root

  required property var settings

  // ---- live job state -----------------------------------------------------
  property bool running: false
  property string mode: ""            // single | double | batch
  property int pass: 1                // Double Upscayl pass, 1 or 2
  property real percent: -1           // current image, -1 before the first report
  property string phase: ""           // wait | processing | scaling
  property int batchTotal: 0
  property int batchDone: 0
  property var job: null
  property string outputPath: ""      // file (single/double) or folder (batch)

  property var logLines: []
  property var gpus: []               // [{ id, name }] seen on any run
  property bool probingGpus: false

  property bool _stopped: false
  property string _error: ""
  property bool _sawSuccess: false
  property double _startedAt: 0

  signal finished(string mode, string path, bool cached)
  signal failed(string title, string description)

  // Overall 0..1 for a progress bar.
  readonly property real overall: {
    var p = Math.max(0, percent) / 100
    if (mode === "batch") return batchTotal > 0 ? Math.min(1, (batchDone + (batchDone < batchTotal ? p : 0)) / batchTotal) : 0
    if (mode === "double") return (pass - 1 + p) / 2
    return p
  }

  function log(line) {
    var next = logLines.length >= 2000 ? logLines.slice(-1500) : logLines.slice()
    next.push(line)
    logLines = next
  }

  function clearLogs() { logLines = [] }

  // job: { mode, input, outputDir, model, modelsPath, scale, gpuId, format,
  //        useCustomWidth, customWidth, compression, tileSize, tta, overwrite }
  function start(j) {
    if (running) return
    // Paths reach find, mkdir and the engine as arguments: absolute only, so
    // none can be taken for an option.
    if (!Core.isAbsolutePath(j.input) || !Core.isAbsolutePath(j.outputDir) || !Core.isAbsolutePath(j.modelsPath)) {
      failed("Error", "The image, output folder or models folder is not an absolute path.")
      return
    }
    job = j
    mode = j.mode
    pass = 1
    percent = -1
    phase = "wait"
    batchTotal = 0
    batchDone = 0
    _stopped = false
    _error = ""
    _sawSuccess = false
    _startedAt = Date.now()
    running = true

    if (mode === "batch") {
      outputPath = Core.batchOutputDir(j)
      exec([Core.bin("mkdir"), "-p", "--", outputPath], function(code) {
        if (!root.running) return
        if (code !== 0) { root.fail("Could not create the output folder " + root.outputPath); return }
        // upscayl-bin walks the folder itself; count the images it will
        // find so progress can say "3/10".
        exec([Core.bin("find"), j.input, "-maxdepth", "1", "-type", "f", "-iregex", ".*\\.\\(png\\|jpe?g\\|jfif\\|webp\\)"], function(c, out) {
          if (!root.running) return
          root.batchTotal = out.split("\n").filter(function(l) { return l.length > 0 }).length
          root.spawn(Core.buildArgs(root.argOpts(j.input, root.outputPath), "batch"))
        })
      })
      return
    }

    outputPath = Core.outputFile(j)
    if (mode === "double") {
      spawn(Core.buildArgs(argOpts(j.input, outputPath), "double1"))
      return
    }
    if (j.overwrite) {
      spawn(Core.buildArgs(argOpts(j.input, outputPath), "single"))
      return
    }
    // Like Upscayl: an existing result for these exact settings is shown
    // straight away instead of being recomputed.
    exec([Core.bin("test"), "-e", outputPath], function(code) {
      if (!root.running) return
      if (code === 0) {
        root.log("Already upscayled at: " + root.outputPath)
        root.complete(true)
      } else {
        root.spawn(Core.buildArgs(root.argOpts(j.input, root.outputPath), "single"))
      }
    })
  }

  function argOpts(input, output) {
    var o = {}
    for (var k in job) o[k] = job[k]
    o.input = input
    o.output = output
    return o
  }

  function stop() {
    if (!running) return
    _stopped = true
    log("Stopping the upscayl process")
    proc.running = false
    running = false
    phase = ""
  }

  function spawn(args) {
    // Only an engine found at an absolute path: a bare name would be looked
    // up in omarchy-shell's own PATH.
    if (!Core.isAbsolutePath(settings.binPath)) {
      fail("Could not start upscayl-bin: no engine was found. Run setup from Settings > Dependencies.")
      return
    }
    var cmd = [settings.binPath].concat(args)
    log("Upscayl command: " + JSON.stringify(cmd))
    _sawSuccess = false
    _exitSeen = false
    percent = -1
    proc.command = cmd
    proc.running = true
    // A command that cannot be started never emits exited.
    Qt.callLater(checkStarted)
  }

  property bool _exitSeen: false

  function checkStarted() {
    if (running && !_stopped && !proc.running && !_exitSeen)
      fail("Could not start upscayl-bin at " + settings.binPath + ". Install the upscayl-bin package or set OMASCAYL_BIN.")
  }

  function onLine(line) {
    if (line.length === 0) return
    log(line)
    var r = Core.parseLine(line)
    if (r.kind === "progress") {
      percent = r.percent
      if (phase === "wait") phase = "processing"
    } else if (r.kind === "error") {
      if (!_error) _error = r.message
      proc.running = false
    } else if (r.kind === "gpu") {
      noteGpu(r.id, r.name)
    } else if (r.kind === "resizing") {
      phase = "scaling"
    } else if (r.kind === "success") {
      _sawSuccess = true
      if (mode === "batch") { batchDone += 1; percent = -1 }
    }
  }

  function onExit(code) {
    if (_stopped || !running) return
    if (_error) { fail(_error); return }
    if (!_sawSuccess && code !== 0) {
      fail("upscayl-bin exited with code " + code + " without finishing. Check the logs in Settings.")
      return
    }
    if (mode === "double" && pass === 1) {
      pass = 2
      phase = "processing"
      log("Upscaling second pass")
      spawn(Core.buildArgs(argOpts(outputPath, outputPath), "double2"))
      return
    }
    complete(false)
  }

  function complete(cached) {
    var ms = Date.now() - _startedAt
    running = false
    phase = ""
    if (!cached) settings.recordRun(mode, ms)
    log("Done upscaling (" + Core.formatDuration(ms) + ")")
    if (settings.notifications) {
      if (mode === "batch") notify("Upscayled", "Images upscayled successfully!")
      else notify("Upscayled", "Image upscayled successfully!")
    }
    finished(mode, outputPath, cached)
  }

  function fail(message) {
    running = false
    phase = ""
    var d = Core.describeError(message)
    if (settings.notifications) notify("Upscayl Failure", mode === "batch" ? "Error upscaling images!" : "Failed to upscale image!")
    failed(d.title, d.description)
  }

  function notify(title, body) {
    Quickshell.execDetached({ command: [Core.bin("notify-send"), "-a", "Omascayl", "-i", settings.iconPath, "--", title, body], environment: ({ PATH: Core.TRUSTED_PATH }) })
  }

  function noteGpu(id, name) {
    for (var i = 0; i < gpus.length; i++) if (gpus[i].id === id) return
    var next = gpus.slice()
    next.push({ id: id, name: name })
    next.sort(function(a, b) { return a.id - b.id })
    gpus = next
    settings.rememberGpus(next)
  }

  // upscayl-bin lists every Vulkan device before it reads its input, so
  // pointing it at a file that cannot exist enumerates GPUs in about a second.
  function probeGpus() {
    if (probingGpus) return
    probingGpus = true
    var missing = settings.cacheDir + "/gpu-probe-" + Date.now() + "-does-not-exist.png"
    exec([settings.binPath, "-i", missing, "-o", missing + ".out.png",
          "-m", settings.modelsPath, "-n", Core.DEFAULT_MODEL], function(code, out, err) {
      err.split("\n").forEach(function(l) {
        var r = Core.parseLine(l)
        if (r.kind === "gpu") root.noteGpu(r.id, r.name)
      })
      root.probingGpus = false
    })
  }

  Component.onCompleted: gpus = settings.knownGpus

  Process {
    id: proc
    environment: ({ PATH: Core.TRUSTED_PATH })
    stdout: SplitParser { onRead: function(data) { root.onLine(String(data).trim()) } }
    stderr: SplitParser { onRead: function(data) { root.onLine(String(data).trim()) } }
    onExited: function(code, status) { root._exitSeen = true; root.onExit(code) }
    onRunningChanged: if (!running) Qt.callLater(root.checkStarted)
  }

  Runner { id: runner }

  function exec(argv, cb) { runner.exec(argv, cb) }
}
