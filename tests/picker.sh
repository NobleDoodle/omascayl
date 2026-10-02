#!/usr/bin/env bash
# Tests bin/omascayl-pick against tests/mock-portal.py on a private session
# bus, so no dialog appears and the real portal is never contacted. The bus
# (tests/private-bus.conf) has no service directories, so nothing on it can be
# auto-started, and the display variables are unset as a second guard.
# Re-executes itself inside that bus.
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if [[ ${1:-} != --inside ]]; then
  exec env -u WAYLAND_DISPLAY -u DISPLAY PYTHONWARNINGS=ignore \
    dbus-run-session --config-file="$here/tests/private-bus.conf" -- "$0" --inside
fi

work=$(mktemp -d)
trap 'kill $(jobs -p) 2>/dev/null; rm -rf -- "$work"' EXIT
pick="$here/bin/omascayl-pick"
pass=0; fail=0
ok() { echo "  ok   $1"; pass=$((pass+1)); }
no() { echo "  FAIL $1"; fail=$((fail+1)); }
expect() { if eval "$2"; then ok "$1"; else no "$1"; fi; }

start_mock() {  # env assignments for the mock
  [[ -n ${mock:-} ]] && kill "$mock" 2>/dev/null && wait "$mock" 2>/dev/null
  rm -f "$work/log.json"
  env MOCK_LOG="$work/log.json" "$@" python3 "$here/tests/mock-portal.py" &
  mock=$!
  for _ in $(seq 50); do
    busctl --user status org.freedesktop.portal.Desktop >/dev/null 2>&1 && return
    sleep 0.05
  done
}
log() { jq -r "$1" "$work/log.json"; }

mkdir -p "$work/My Pictures"
echo "== image picked"
start_mock MOCK_CODE=0 MOCK_URI="file://$work/My%20Pictures/a%23b.png"
out=$(OMASCAYL_PICKER=portal "$pick" image "Select an Image" "$work/My Pictures"); rc=$?
expect "exit 0" '[[ $rc == 0 ]]'
expect "decoded path" '[[ $out == "$work/My Pictures/a#b.png" ]]'
expect "title" '[[ $(log ".[0].title") == "Select an Image" ]]'
expect "not a folder picker" '[[ $(log ".[0].directory") == false ]]'
expect "image filters" '[[ $(log "[.[0].filters[0][1][][1]] | join(\" \")") == *"*.jfif"*"image/webp"* ]]'
expect "start folder" '[[ $(log ".[0].current_folder") == "$work/My Pictures" ]]'

echo "== folder picked"
start_mock MOCK_CODE=0 MOCK_URI="file://$work/out"
out=$(OMASCAYL_PICKER=portal "$pick" folder "Set Output Folder" /nonexistent); rc=$?
expect "exit 0 and path" '[[ $rc == 0 && $out == "$work/out" ]]'
expect "directory option" '[[ $(log ".[0].directory") == true ]]'
expect "no filters for folders" '[[ $(log ".[0].filters") == null ]]'
expect "missing start folder omitted" '[[ $(log ".[0].current_folder") == null ]]'

echo "== cancelled"
start_mock MOCK_CODE=1
out=$(OMASCAYL_PICKER=portal "$pick" image "Select an Image"); rc=$?
expect "exit 1, no output" '[[ $rc == 1 && -z $out ]]'

echo "== portal failure"
start_mock MOCK_CODE=2
OMASCAYL_PICKER=portal "$pick" image "Select an Image" 2>/dev/null; rc=$?
expect "exit 2" '[[ $rc == 2 ]]'

echo "== killed while open closes the dialog"
start_mock MOCK_CODE=never
OMASCAYL_PICKER=portal "$pick" folder "Select a Folder" & p=$!
sleep 0.6
kill -TERM $p; wait $p; rc=$?
sleep 0.2
expect "exit 1 after SIGTERM" '[[ $rc == 1 ]]'
expect "Request.Close sent" '[[ $(log "[.[] | select(.event == \"close\")] | length") == 1 ]]'

echo "== no portal: zenity fallback"
kill "$mock" 2>/dev/null; wait "$mock" 2>/dev/null; mock=""
mkdir -p "$work/fakebin"
printf '#!/bin/sh\necho "$@" > "%s/zenity.args"\necho /picked/by/zenity.png\n' "$work" > "$work/fakebin/zenity"
chmod +x "$work/fakebin/zenity"
# The picker pins PATH to the system folders, so run a probe copy whose PATH
# line puts the fake zenity first.
sed 's|^os.environ\["PATH"\] = "/usr/bin:|os.environ["PATH"] = "'"$work"'/fakebin:/usr/bin:|' "$pick" > "$work/pick-probe"
chmod +x "$work/pick-probe"
expect "probe changes only the PATH line" '[[ $(diff "$pick" "$work/pick-probe" | grep -c "^>") == 1 ]]'
out=$(DBUS_SESSION_BUS_ADDRESS="unix:path=$work/no-bus" "$work/pick-probe" image "Select an Image" "$work" 2>/dev/null); rc=$?
expect "falls back to zenity" '[[ $rc == 0 && $out == /picked/by/zenity.png ]]'
expect "zenity gets filters and folder" 'grep -q -- "--file-filter Images | \*.png" "$work/zenity.args" && grep -q -- "--filename $work/" "$work/zenity.args"'

echo "== a zenity on the inherited PATH is never used"
rm -f "$work/zenity.args"
timeout 10 env -u WAYLAND_DISPLAY -u DISPLAY PATH="$work/fakebin:$PATH" DBUS_SESSION_BUS_ADDRESS="unix:path=$work/no-bus" OMASCAYL_PICKER=zenity "$pick" image "Select an Image" "$work" >/dev/null 2>&1
expect "fake zenity not run" '[[ ! -e $work/zenity.args ]]'

echo "passed $pass, failed $fail"
[[ $fail == 0 ]]
