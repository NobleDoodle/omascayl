#!/usr/bin/bash
# Tests src/NumberStepper.qml, the number entry that replaces the SDK
# NumberField: keys and limits, and that it contains no text input (an
# editable one reads the clipboard on every change inside omarchy-shell).
# Offscreen Quickshell with a scratch config; touches nothing else.
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
omarchy=${OMARCHY_PATH:-/usr/share/omarchy}
mkdir -p "$work/config"
ln -s "$here/src/NumberStepper.qml" "$work/config/"
ln -s "$omarchy/shell/Commons" "$work/config/Commons"
ln -s "$omarchy/shell/Ui" "$work/config/Ui"
cat > "$work/config/shell.qml" <<'QML'
import QtQuick
import Quickshell

ShellRoot {
  id: shell
  property var results: []
  function expect(name, ok) { results.push((ok ? "  ok   " : "  FAIL ") + name) }
  function keys(s, list) { var used = true; for (var i = 0; i < list.length; i++) used = s.key(list[i]) && used; return used }
  function textInputs(item) {
    var n = ("readOnly" in item && "cursorPosition" in item) ? 1 : 0
    for (var i = 0; i < item.children.length; i++) n += textInputs(item.children[i])
    return n
  }

  NumberStepper { id: tile; from: 0; to: 2048; stepSize: 32; value: 256; onModified: function(v) { value = v } }
  NumberStepper { id: width; from: 1; to: 65535; stepSize: 100; value: 1920; onModified: function(v) { value = v } }

  Component.onCompleted: {
    keys(tile, [Qt.Key_1, Qt.Key_0, Qt.Key_2, Qt.Key_4])
    expect("typing shows the digits, value unchanged until Enter", tile.typed === "1024" && tile.value === 256)
    keys(tile, [Qt.Key_Return])
    expect("Enter sets the typed value", tile.value === 1024 && tile.typed === "")
    keys(tile, [Qt.Key_9, Qt.Key_9, Qt.Key_9, Qt.Key_9, Qt.Key_9, Qt.Key_Enter])
    expect("typing stops at the maximum's length and clamps to it", tile.value === 2048)
    keys(tile, [Qt.Key_5, Qt.Key_Escape])
    expect("Escape cancels typing", tile.value === 2048 && tile.typed === "")
    keys(tile, [Qt.Key_Backspace, Qt.Key_Return])
    expect("Backspace edits the current value", tile.value === 204)
    keys(tile, [Qt.Key_Up])
    expect("Up steps by stepSize", tile.value === 236)
    keys(tile, [Qt.Key_Down, Qt.Key_Down])
    expect("Down steps back", tile.value === 172)
    keys(tile, [Qt.Key_PageDown])
    expect("PageDown steps ten and clamps at the minimum", tile.value === 0)
    keys(tile, [Qt.Key_0, Qt.Key_5, Qt.Key_Return])
    expect("a leading zero is replaced", tile.value === 5)
    keys(tile, [Qt.Key_1, Qt.Key_0, Qt.Key_0, Qt.Key_Up])
    expect("stepping from a typed value", tile.value === 132 && tile.typed === "")
    expect("other keys are left alone", tile.key(Qt.Key_A) === false && tile.key(Qt.Key_V) === false)
    keys(width, [Qt.Key_Backspace, Qt.Key_Backspace, Qt.Key_Backspace, Qt.Key_Backspace, Qt.Key_Return])
    expect("emptying a field clamps to its minimum", width.value === 1)
    keys(width, [Qt.Key_PageUp])
    expect("PageUp steps ten", width.value === 1001)
    expect("no text input inside the control", textInputs(tile) === 0 && textInputs(width) === 0)
    for (var i = 0; i < results.length; i++) console.log(results[i])
    Qt.quit()
  }
}
QML

out=$(env -u WAYLAND_DISPLAY -u DISPLAY -u QT_QPA_PLATFORMTHEME QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
  timeout 60 qs -p "$work/config" 2>&1)
lines=$(grep -aoE '  (ok|FAIL) .*' <<< "$out")
[[ -n $lines ]] || { echo "$out" | tail -20; echo "passed 0, failed 1"; exit 1; }
echo "$lines"
pass=$(grep -c "  ok " <<< "$lines"); fail=$(grep -c "  FAIL " <<< "$lines")
echo "passed $pass, failed $fail"
[[ $fail == 0 ]]
