//@ pragma AppId io.github.nobledoodle.omascayl
//@ pragma ShellId omascayl
import QtQuick
import Quickshell
import Quickshell.Io

// Omascayl: Upscayl's AI image upscaler as a Quickshell application, themed by
// Omarchy. Launched through bin/omascayl, which links Omarchy's Commons and Ui
// modules next to these files and hands later launches to this instance over
// IPC.
ShellRoot {
  id: shell

  App { id: app }

  AppWindow {
    id: window
    app: app
    visible: true
  }

  // omascayl <path> while already running: qs ipc call omascayl open <path>
  IpcHandler {
    target: "omascayl"
    function open(path: string): void { if (path) app.openPath(path) }
    function upscayl(): void { app.upscayl() }
    function stop(): void { app.stop() }
    function quit(): void { app.quit() }
    function status(): string {
      return JSON.stringify({
        running: app.upscaler.running,
        mode: app.upscaler.mode,
        percent: app.upscaler.percent,
        image: app.imagePath,
        folder: app.batchFolderPath,
        result: app.upscaledImagePath || app.upscaledBatchFolderPath
      })
    }
  }

  // Development aid: OMASCAYL_SNAPSHOT=<file.png> renders the window offscreen
  // after OMASCAYL_SNAPSHOT_DELAY ms, saves it and quits. OMASCAYL_SNAPSHOT_STATE
  // is a JSON object applied first ({ tab, image, result, viewMode, zoom,
  // pointer: [x, y], split, error }), so each screen can be checked headless.
  Loader {
    active: !!Quickshell.env("OMASCAYL_SNAPSHOT")
    sourceComponent: Item {
      Timer {
        running: true
        interval: 600
        onTriggered: {
          var s = {}
          try { s = JSON.parse(Quickshell.env("OMASCAYL_SNAPSHOT_STATE") || "{}") } catch (e) { console.warn("bad OMASCAYL_SNAPSHOT_STATE", e) }
          window.applySnapshotState(s)
        }
      }
      Timer {
        running: true
        interval: parseInt(Quickshell.env("OMASCAYL_SNAPSHOT_DELAY") || "2500")
        onTriggered: {
          report.setText(JSON.stringify({
            running: app.upscaler.running,
            mode: app.upscaler.mode,
            batchDone: app.upscaler.batchDone,
            batchTotal: app.upscaler.batchTotal,
            image: app.imagePath,
            folder: app.batchFolderPath,
            batchMode: app.batchMode,
            output: app.outputPath,
            result: app.upscaledImagePath,
            batchResult: app.upscaledBatchFolderPath,
            inputSize: [app.inputWidth, app.inputHeight],
            error: app.error,
            depsPromptOpen: app.depsPromptOpen,
            setupRunning: app.setupRunning,
            missingDeps: app.missingDeps.map(function(d) { return d.key }),
            backendFound: app.backendFound,
            toast: app.toast,
            gpus: app.upscaler.gpus,
            models: app.modelOptions,
            stats: app.settings.stats,
            logs: app.upscaler.logLines
          }, null, 1))
          window.snapshot(Quickshell.env("OMASCAYL_SNAPSHOT"), function() { Qt.quit() })
        }
      }
      FileView {
        id: report
        path: Quickshell.env("OMASCAYL_SNAPSHOT") + ".json"
        printErrors: false
      }
    }
  }
}
