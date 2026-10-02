import QtQuick
import Quickshell.Io
import "Core.js" as Core

// exec(argv, cb(code, stdout, stderr), env) runs a one-shot command without a
// shell, so paths are never interpreted, and calls back once it has exited
// and both streams are drained.
//
// The command must be an absolute path (a bare name would be looked up in
// omarchy-shell's own PATH), and it runs with PATH pinned to Core.TRUSTED_PATH
// for anything it starts in turn. Output past maxOutputBytes stops the
// command, and the callback sees code -1.
Item {
  id: root

  readonly property int maxOutputBytes: 4 * 1024 * 1024

  // env: optional { NAME: value } added to the inherited environment; PATH is
  // always the trusted one unless env names another.
  function exec(argv, cb, env) {
    if (!argv || !Core.isAbsolutePath(String(argv[0]))) {
      console.warn("omascayl: refusing to run a command that is not an absolute path:", argv && argv[0])
      Qt.callLater(function() { if (cb) cb(127, "", "not an absolute path: " + (argv && argv[0])) })
      return
    }
    var environment = { PATH: Core.TRUSTED_PATH }
    if (env) for (var k in env) environment[k] = env[k]
    var p = execComponent.createObject(root, { command: argv, callback: cb, environment: environment })
    p.running = true
    // A command that cannot be started (not installed) never emits exited;
    // report it as 127, like a shell would.
    Qt.callLater(function() {
      if (p && !p.running && p.code === -1 && p.pending === 3) {
        p.pending = 1
        p.code = 127
        p.settle()
      }
    })
  }

  Component {
    id: execComponent
    Process {
      id: p
      property var callback: null
      property int pending: 3
      property int code: -1
      property bool overflowed: false
      property string out: ""
      property string err: ""
      function settle() {
        if (--pending > 0) return
        try { if (callback) callback(overflowed ? -1 : code, out, err) } catch (e) { console.warn("omascayl:", e) }
        p.destroy()
      }
      function guard(data) {
        if (!overflowed && data && data.byteLength > root.maxOutputBytes) {
          overflowed = true
          p.running = false
        }
      }
      stdout: StdioCollector {
        onDataChanged: p.guard(data)
        onStreamFinished: { p.out = p.overflowed ? "" : text; p.settle() }
      }
      stderr: StdioCollector {
        onDataChanged: p.guard(data)
        onStreamFinished: { p.err = p.overflowed ? "" : text; p.settle() }
      }
      onExited: function(exitCode, status) { p.code = exitCode; p.settle() }
    }
  }
}
