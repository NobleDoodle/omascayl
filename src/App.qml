import QtQuick
import Quickshell
import Quickshell.Io
import "Core.js" as Core

// Application state and actions: what is selected, where results go, and the
// glue between the window, the settings and the upscayl-bin runner. This is
// the part of Upscayl that lives in its renderer (pages/index.tsx and the
// sidebar's step components).
Item {
  id: root

  readonly property alias settings: settingsObj
  readonly property alias upscaler: upscalerObj

  // Hosted by omarchy-shell (Plugin.qml) rather than running as its own
  // process: quitting only closes the window, and the backend is found with
  // bin/omascayl-backend because the shell's environment has no OMASCAYL_*
  // values.
  property bool embedded: false
  signal quitRequested()

  // This checkout's bin/ (omascayl-pick, omascayl-backend). The launcher
  // passes it as OMASCAYL_TOOLS; Plugin.qml sets it directly.
  property string toolsDir: Quickshell.env("OMASCAYL_TOOLS") || ""
  property bool pickerOpen: false

  // ---- selection ------------------------------------------------------------
  property bool batchMode: false
  property bool doubleUpscayl: false
  property string imagePath: ""
  property string batchFolderPath: ""
  property string outputPath: ""
  property bool outputFromClipboard: false

  property string upscaledImagePath: ""
  property string upscaledBatchFolderPath: ""
  property int resultRevision: 0       // bumps so the viewer reloads a rewritten file
  property var resultSize: null        // { width, height } the finished job aimed for
  property var sizing: null            // the scale options the running job used

  // Natural size of the selected image, reported by the viewer once loaded.
  property int inputWidth: 0
  property int inputHeight: 0

  // ---- models ---------------------------------------------------------------
  property var installedModels: []     // names in settings.modelsPath
  property var customModels: []        // names in settings.customModelsPath
  property bool backendFound: true
  property bool modelsLoaded: false

  readonly property var modelOptions: {
    var out = []
    for (var i = 0; i < installedModels.length; i++)
      out.push({ value: installedModels[i], label: Core.modelInfo(installedModels[i]).name })
    for (var j = 0; j < customModels.length; j++)
      if (installedModels.indexOf(customModels[j]) === -1)
        out.push({ value: customModels[j], label: customModels[j] + "  (custom)" })
    return out
  }

  readonly property string modelDescription: {
    var m = settings.model
    if (installedModels.indexOf(m) === -1 && customModels.indexOf(m) !== -1)
      return "Imported custom model from " + settings.customModelsPath
    return Core.modelInfo(m).description
  }

  readonly property var targetSize: Core.targetSize(inputWidth, inputHeight, {
    scale: settings.scale,
    useCustomWidth: settings.useCustomWidth,
    customWidth: settings.customWidth,
    doubleUpscayl: doubleUpscayl && !batchMode
  })

  // ---- messages -------------------------------------------------------------
  property var error: null             // { title, description }
  property string toast: ""

  // ---- pickers ----------------------------------------------------------------
  // The dialog runs in another process: bin/omascayl-pick asks the
  // xdg-desktop-portal FileChooser (zenity if there is no portal). Inside
  // omarchy-shell that keeps GTK's file chooser, and the gvfs monitors it
  // starts, out of the desktop shell's process, where a crash in them would
  // take the whole shell down. Both modes use it, so they behave the same.
  function chooseImage() {
    if (upscaler.running) return
    runPicker("image", "Select an Image",
              imagePath ? Core.dirName(imagePath) : settings.picturesDir,
              function(path) { root.setImage(path, false) })
  }

  // purpose: batch | output | models. Models can be picked mid-upscayl.
  function chooseFolder(purpose) {
    if (upscaler.running && purpose !== "models") return
    var title = purpose === "output" ? "Set Output Folder"
              : purpose === "models" ? "Select Custom Models Folder"
              : "Select a Folder"
    var start = purpose === "output" ? outputPath
              : purpose === "models" ? settings.customModelsPath
              : batchFolderPath
    runPicker("folder", title, start || settings.picturesDir, function(path) {
      if (purpose === "output") root.setOutputFolder(path)
      else if (purpose === "models") root.setCustomModelsFolder(path)
      else root.setBatchFolder(path)
    })
  }

  function runPicker(kind, title, start, onPicked) {
    if (pickerOpen) return            // one dialog at a time
    if (!toolsDir) {
      showError("Error", "The file picker helper (bin/omascayl-pick) was not found. Start Omascayl with bin/omascayl.")
      return
    }
    pickerOpen = true
    runner.exec([toolsDir + "/omascayl-pick", kind, title, start || ""], function(code, out, err) {
      root.pickerOpen = false
      var path = out.split("\n")[0]
      if (code === 0 && path.charAt(0) === "/") onPicked(path)
      else if (code !== 1) root.showError("Could not open the file picker",
        (err.trim() || "omascayl-pick exited with code " + code)
        + "\n\nYou can still drag an image or folder onto the window, or paste one with Ctrl+V.")
    })
  }

  function showError(title, description) { error = { title: title, description: description } }
  function dismissError() { error = null }
  function showToast(text) { toast = ""; toast = text }

  // ---- selection actions ----------------------------------------------------
  function setBatchMode(on) {
    if (batchMode === on) return
    batchMode = on
    if (on) doubleUpscayl = false
  }

  function defaultOutputFor(dir) {
    if (settings.rememberOutputFolder && Core.isAbsolutePath(settings.outputFolder)) return settings.outputFolder
    return dir
  }

  function setImage(path, fromClipboard) {
    if (!Core.isImagePath(path)) {
      showError("Invalid Image", "Please select/paste an image with a valid extension like PNG, JPG, JPEG, JFIF or WEBP.")
      return
    }
    resetImage()
    setBatchMode(false)
    imagePath = path
    outputFromClipboard = !!fromClipboard
    outputPath = defaultOutputFor(fromClipboard ? settings.picturesDir : Core.dirName(path))
  }

  function setBatchFolder(path) {
    resetImage()
    setBatchMode(true)
    batchFolderPath = path
    outputPath = defaultOutputFor(path)
  }

  function setOutputFolder(path) {
    outputPath = path
    outputFromClipboard = false
    settings.set("outputFolder", path)
  }

  function resetImage() {
    upscaledImagePath = ""
    upscaledBatchFolderPath = ""
    resultSize = null
    imagePath = ""
    batchFolderPath = ""
    inputWidth = 0
    inputHeight = 0
  }

  // A path from a drop, the command line or a pasted file list: folders go
  // to batch mode, images to single mode.
  function openPath(path) {
    path = String(path || "").trim()
    if (path.indexOf("file://") === 0) path = Core.pathFromUrl(path)
    if (!path) return
    if (path.charAt(0) !== "/") path = Quickshell.env("PWD") + "/" + path
    runner.exec([Core.bin("test"), "-d", path], function(code) {
      if (code === 0) root.setBatchFolder(path.replace(/\/+$/, "") || "/")
      else root.setImage(path, false)
    })
  }

  function openUrls(urls) {
    if (!urls || urls.length === 0) {
      showError("Invalid Image", "Please drag and drop an image")
      return
    }
    openPath(Core.pathFromUrl(String(urls[0])))
  }

  // Ctrl+V: a copied file (text/uri-list, from a file manager) wins over raw
  // image data (a screenshot or an image copied from a browser), which is
  // saved under the cache dir first, like Upscayl's paste handler.
  function paste() {
    if (upscaler.running) return
    runner.exec([Core.bin("wl-paste"), "--list-types"], function(code, out) {
      var types = out.split("\n").map(function(t) { return t.trim() })
      if (types.indexOf("text/uri-list") !== -1) {
        runner.exec([Core.bin("wl-paste"), "--no-newline", "--type", "text/uri-list"], function(c, list) {
          var lines = list.split(/\r?\n/).filter(function(l) { return l && l.charAt(0) !== "#" })
          if (lines.length) root.openPath(Core.pathFromUrl(lines[0]))
          else root.showError("No image selected", "No Image file found in Clipboard to paste!")
        })
        return
      }
      var pick = ["image/png", "image/webp", "image/jpeg"].filter(function(t) { return types.indexOf(t) !== -1 })[0]
      if (!pick) {
        root.showError("Invalid Image", "No Image file found in Clipboard to paste!")
        return
      }
      var ext = pick === "image/jpeg" ? "jpg" : pick.split("/")[1]
      var dir = root.settings.cacheDir + "/clipboard"
      var token = Math.floor(Math.random() * 0x100000000).toString(16)
      var file = dir + "/pasted-" + Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss") + "-" + token + "." + ext
      runner.exec([Core.bin("mkdir"), "-p", "--", dir], function() {
        // The only shell in Omascayl: it redirects wl-paste into the file.
        // Both values are passed as positional arguments, never spliced in,
        // and noclobber (set -C) makes the redirection fail rather than
        // follow anything already at that name, a planted symlink included.
        runner.exec([Core.bin("sh"), "-c", "set -C; exec " + Core.bin("wl-paste") + " --no-newline --type \"$1\" > \"$2\"",
                     "omascayl-paste", pick, file], function(c2) {
          if (c2 === 0) root.setImage(file, true)
          else root.showError("Error", "Could not save the pasted image to " + file)
        })
      })
    })
  }

  // ---- upscayl ----------------------------------------------------------------
  function isCustomModel(model) {
    return installedModels.indexOf(model) === -1 && customModels.indexOf(model) !== -1
  }

  function upscayl() {
    if (upscaler.running) return
    if (!backendFound && toolsDir) {
      depsPromptOpen = true           // offer setup instead of failing
      return
    }
    var input = batchMode ? batchFolderPath : imagePath
    if (!input) {
      showError("No image selected", batchMode ? "Please select a folder to upscale" : "Please select an image to upscale")
      return
    }
    if (!outputPath) {
      showError("Set Output Folder", "Please select an output folder first")
      return
    }
    var model = settings.model
    if (modelOptions.length && !modelOptions.some(function(o) { return o.value === model })) {
      showError("Error", "The model \"" + model + "\" is not installed. Pick another model in Step 2.")
      return
    }
    upscaledImagePath = ""
    upscaledBatchFolderPath = ""
    resultSize = null
    sizing = {
      scale: settings.scale,
      useCustomWidth: settings.useCustomWidth,
      customWidth: settings.customWidth,
      doubleUpscayl: doubleUpscayl && !batchMode
    }
    upscaler.start({
      mode: batchMode ? "batch" : (doubleUpscayl ? "double" : "single"),
      input: input,
      outputDir: outputPath,
      model: model,
      modelsPath: isCustomModel(model) ? settings.customModelsPath : settings.modelsPath,
      scale: settings.scale,
      gpuId: settings.gpuId,
      format: settings.format,
      useCustomWidth: settings.useCustomWidth,
      customWidth: settings.customWidth,
      compression: settings.compression,
      tileSize: settings.tileSize,
      tta: settings.tta,
      overwrite: settings.overwrite
    })
  }

  function stop() { upscaler.stop() }

  function quit() {
    settings.flush()
    // Inside omarchy-shell, Qt.quit() would take the whole desktop shell
    // down. Just close the window; a running job finishes in the background.
    if (embedded) {
      quitRequested()
      return
    }
    upscaler.stop()
    Qt.quit()
  }

  // ---- outside world --------------------------------------------------------
  function openExternally(path) {
    if (Core.isAbsolutePath(path)) Quickshell.execDetached({ command: [Core.bin("xdg-open"), path], environment: ({ PATH: Core.TRUSTED_PATH }) })
  }

  function revealFolder(path) {
    if (Core.isAbsolutePath(path)) Quickshell.execDetached({ command: [Core.bin("xdg-open"), path], environment: ({ PATH: Core.TRUSTED_PATH }) })
  }

  function copyText(text) {
    Quickshell.execDetached({ command: [Core.bin("wl-copy"), "--", String(text)], environment: ({ PATH: Core.TRUSTED_PATH }) })
    showToast("Copied")
  }

  function listModels(dir, cb) {
    // Absolute only: a value from settings.json such as "-delete" would
    // otherwise be read by find as an expression, not a path.
    if (!Core.isAbsolutePath(dir)) { cb([]); return }
    runner.exec([Core.bin("find"), dir, "-maxdepth", "1", "(", "-type", "f", "-o", "-type", "l", ")", "-printf", "%f\n"], function(code, out) {
      var files = out.split("\n").filter(function(l) { return l.length > 0 })
      files.sort()
      cb(code === 0 ? Core.modelNamesFromFiles(files) : [])
    })
  }

  function refreshModels() {
    listModels(settings.modelsPath, function(names) {
      root.installedModels = Core.orderInstalledModels(names)
      root.modelsLoaded = true
      root.ensureModel()
    })
    refreshCustomModels()
  }

  function refreshCustomModels() {
    listModels(settings.customModelsPath, function(names) {
      root.customModels = names
      root.ensureModel()
    })
  }

  function setCustomModelsFolder(path) {
    listModels(path, function(names) {
      if (!names.length) {
        root.showError("Invalid Folder", "The selected folder does not contain valid model files. Make sure you select the folder that ONLY contains '.param' and '.bin' files.")
        return
      }
      root.settings.set("customModelsPath", path)
      root.customModels = names
      root.showToast(names.length + (names.length === 1 ? " custom model imported" : " custom models imported"))
    })
  }

  function clearCustomModels() {
    settings.set("customModelsPath", "")
    customModels = []
    ensureModel()
  }

  function ensureModel() {
    if (!modelsLoaded || !modelOptions.length) return
    var m = settings.model
    if (modelOptions.some(function(o) { return o.value === m })) return
    settings.set("model", installedModels.indexOf(Core.DEFAULT_MODEL) !== -1 ? Core.DEFAULT_MODEL : modelOptions[0].value)
  }

  // bin/omascayl-backend finds the engine and models (and honors
  // OMASCAYL_BIN / OMASCAYL_MODELS when set). Asked on every check, so a
  // backend that setup installs while Omascayl is open is picked up.
  function checkBackend() {
    if (!toolsDir) {
      runner.exec([Core.bin("test"), "-x", settings.binPath], function(code) {
        root.backendFound = code === 0 && Core.isAbsolutePath(settings.binPath)
      })
      refreshModels()
      return
    }
    runner.exec([toolsDir + "/omascayl-backend"], function(code, out) {
      var lines = out.split("\n")
      if (lines[0]) root.settings.binPath = lines[0]
      if (lines[1]) root.settings.modelsPath = lines[1]
      if (lines[2]) root.settings.picturesDir = lines[2]
      root.backendFound = code === 0 && Core.isAbsolutePath(root.settings.binPath)
      root.refreshModels()
    })
  }

  // ---- dependencies and setup ------------------------------------------------------
  // bin/omascayl-deps says what is missing; bin/omascayl-setup installs it,
  // interactively and with consent, in Omarchy's presented terminal. It has to
  // be a terminal: it asks questions and pacman asks for a password, and
  // neither can happen inside omarchy-shell.
  property var deps: []                // [{ state, key, need, label, packages, why }]
  property bool depsChecked: false
  property bool setupRunning: false
  property bool depsPromptOpen: false
  property bool depsPrompted: false    // the first-open prompt was offered this session
  readonly property var missingDeps: deps.filter(function(d) { return d.state === "missing" })
  readonly property bool requiredMissing: missingDeps.some(function(d) { return d.need === "required" })
  readonly property string omarchyBin: (Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy") + "/bin"

  function checkDeps() {
    if (!toolsDir) { depsChecked = true; return }
    runner.exec([toolsDir + "/omascayl-deps"], function(code, out) {
      root.deps = out.split("\n").filter(function(l) { return l.length > 0 }).map(function(l) {
        var f = l.split("\t")
        return { state: f[0], key: f[1], need: f[2], label: f[3], packages: f[4], why: f[5] }
      })
      root.depsChecked = true
      root.maybePromptDeps()
    })
  }

  // On first open: anything required missing, or something recommended that
  // hasn't been declined before ("Not now" on a recommended-only prompt is
  // remembered; required ones keep their banner instead).
  function maybePromptDeps() {
    if (!settings.ready || depsPrompted || !missingDeps.length) return
    if (!requiredMissing && settings.st.depsPromptDeclined) return
    depsPrompted = true
    depsPromptOpen = true
  }

  function dismissDepsPrompt() {
    depsPromptOpen = false
    if (!requiredMissing) settings.set("depsPromptDeclined", true)
  }

  function recheck() {
    checkBackend()
    checkDeps()
  }

  function openSetup() {
    if (setupRunning) return
    if (!toolsDir) {
      showError("Error", "The setup script (bin/omascayl-setup) was not found. Start Omascayl with bin/omascayl.")
      return
    }
    setupRunning = true
    var script = toolsDir + "/omascayl-setup"
    // By absolute path: a bare name would be looked up in omarchy-shell's own
    // PATH, not the one given here. The launcher calls Omarchy's other
    // helpers by name, so its PATH starts with Omarchy's bin (root-owned on a
    // packaged install; /usr/share/omarchy/bin/omarchy links to /usr/bin).
    var env = { PATH: omarchyBin + ":/usr/bin" }
    runner.exec([omarchyBin + "/omarchy", "launch", "floating", "terminal", "with", "presentation", script], function(code) {
      if (code === 127) {
        // No Omarchy launcher: any terminal will do.
        runner.exec([Core.bin("xdg-terminal-exec"), script], function(c2) {
          root.setupRunning = false
          if (c2 === 127) root.showError("Could not open a terminal", "Run this in a terminal instead:\n" + script)
          root.recheck()
        }, env)
        return
      }
      root.setupRunning = false
      root.recheck()
    }, env)
  }

  // The setup script touches this when it ends, however it ends; the launch
  // command above may return before the terminal closes.
  FileView {
    path: root.settings.stateDir + "/setup-finished"
    watchChanges: true
    printErrors: false
    onFileChanged: { reload(); root.setupRunning = false; root.recheck() }
  }

  // ---- wiring -------------------------------------------------------------------
  Settings { id: settingsObj }
  Upscaler { id: upscalerObj; settings: settingsObj }
  Runner { id: runner }

  Connections {
    target: upscalerObj
    function onFinished(mode, path, cached) {
      if (mode === "batch") root.upscaledBatchFolderPath = path
      else {
        root.resultRevision += 1
        root.upscaledImagePath = path
        if (root.sizing) root.resultSize = Core.targetSize(root.inputWidth, root.inputHeight, root.sizing)
      }
      if (cached) root.showToast("Already upscayled. Turn on Overwrite Previous Upscale in Settings to redo it.")
    }
    function onFailed(title, description) { root.showError(title, description) }
  }

  // Settings load asynchronously (see Settings.qml); what depends on them
  // waits for this.
  Connections {
    target: settingsObj
    function onReadyChanged() {
      if (!settingsObj.ready) return
      if (root.settings.rememberOutputFolder && Core.isAbsolutePath(root.settings.outputFolder) && !root.outputPath)
        root.outputPath = root.settings.outputFolder
      root.refreshCustomModels()
      root.maybePromptDeps()
    }
  }

  Component.onCompleted: {
    // The launcher creates these; the plugin has no launcher.
    runner.exec([Core.bin("mkdir"), "-p", "--", settings.stateDir, settings.cacheDir], function() {})
    checkBackend()
    checkDeps()
    var initial = Quickshell.env("OMASCAYL_OPEN")
    if (initial) openPath(initial)
  }
}
