#!/usr/bin/bash
# Tests bin/omascayl-integrate and the launcher stub it writes, in a scratch
# HOME (never the real one), with a fake notify-send. The scripts run tools by
# absolute path, so the plugin copy's BIN constant is pointed at fakebin.
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
export HOME="$work/home"
unset XDG_DATA_HOME
mkdir -p "$HOME" "$work/fakebin"
printf '#!/bin/sh\necho "$@" >> "%s/notify.log"\n' "$work" > "$work/fakebin/notify-send"
chmod +x "$work/fakebin/notify-send"
for t in update-desktop-database gtk-update-icon-cache; do
  [[ -x /usr/bin/$t ]] && ln -s "/usr/bin/$t" "$work/fakebin/$t"
done

id=io.github.nobledoodle.omascayl
plugin="$HOME/.config/omarchy/plugins/$id"
data="$HOME/.local/share"
desktop="$data/applications/$id.desktop"
icon="$data/icons/hicolor/scalable/apps/$id.svg"
stub="$data/omascayl/plugin-launch"
cmd="$HOME/.local/bin/omascayl"
install_copy() {
  mkdir -p "$plugin" && cp -r "$here/bin" "$here/src" "$here/share" "$here/VERSION" "$plugin/"
  sed -i "s|^BIN = \"/usr/bin/\"\$|BIN = \"$work/fakebin/\"|" "$plugin/bin/omascayl-integrate"
}
install_copy

pass=0; fail=0
expect() { if eval "$2"; then echo "  ok   $1"; pass=$((pass+1)); else echo "  FAIL $1"; fail=$((fail+1)); fi; }
integrate() { "$plugin/bin/omascayl-integrate" install "$plugin"; }

echo "== first install"
out=$(integrate); rc=$?
expect "exit 0" '[[ $rc == 0 ]]'
expect "reports the install" '[[ $out == *installed* ]]'
expect "launcher entry, marked as the plugin's" 'grep -q "^X-Omascayl-Managed=plugin$" "$desktop"'
expect "entry runs the stub" 'grep -q "^Exec=$stub %f$" "$desktop"'
expect "entry still offers images under Open With" 'grep -q "^MimeType=image/png;" "$desktop"'
expect "icon" '[[ -f $icon ]]'
expect "stub is executable" '[[ -x $stub ]]'
expect "command links to the stub" '[[ $(readlink "$cmd") == "$stub" ]]'
expect "stub hands off to the plugin" '[[ $("$cmd" --version) == "omascayl $(cat "$here/VERSION")" ]]'

echo "== second run changes nothing"
before=$(stat -c %Y "$desktop" "$icon" "$stub")
sleep 1.1
out=$(integrate)
expect "silent" '[[ -z $out ]]'
expect "files untouched" '[[ $(stat -c %Y "$desktop" "$icon" "$stub") == "$before" ]]'

echo "== a standalone install's entry and command are left alone"
printf '[Desktop Entry]\nName=Omascayl\nExec=%s/.local/bin/omascayl %%f\n' "$HOME" > "$desktop"
ln -sfn "$data/omascayl/app/bin/omascayl" "$cmd"
integrate >/dev/null
expect "entry kept" '! grep -q X-Omascayl-Managed "$desktop"'
expect "command kept" '[[ $(readlink "$cmd") == "$data/omascayl/app/bin/omascayl" ]]'

echo "== an older plugin install's entry and command are taken over"
printf '[Desktop Entry]\nName=Omascayl\nExec=%s/bin/omascayl %%f\n' "$plugin" > "$desktop"
ln -sfn "$plugin/bin/omascayl" "$cmd"
integrate >/dev/null
expect "entry now the plugin's" 'grep -q "^X-Omascayl-Managed=plugin$" "$desktop"'
expect "command now the stub" '[[ $(readlink "$cmd") == "$stub" ]]'

echo "== unloading while the plugin stays (a shell restart)"
"$stub" --cleanup-if-removed & p=$!
sleep 1.2
expect "nothing removed yet" '[[ -f $desktop && -f $icon && -x $stub ]]'
wait $p
expect "still nothing removed after the check" '[[ -f $desktop && -f $icon && -x $stub && -L $cmd ]]'

echo "== unloading because the plugin was removed"
mkdir -p "$data/omascayl/backend/models" && touch "$data/omascayl/backend/upscayl-bin"
"$stub" --cleanup-if-removed & p=$!
sleep 0.3
rm -rf "$plugin"
wait $p
expect "entry, icon, command and stub removed" '[[ ! -e $desktop && ! -e $icon && ! -e $cmd && ! -e $stub ]]'
expect "downloaded backend and stub folder removed" '[[ ! -e $data/omascayl ]]'

echo "== launching a leftover entry after the plugin is gone"
install_copy
integrate >/dev/null
rm -rf "$plugin"
"$cmd" >/dev/null 2>&1; rc=$?
expect "exits 1" '[[ $rc == 1 ]]'
expect "cleaned up" '[[ ! -e $desktop && ! -e $icon && ! -e $cmd && ! -e $stub ]]'
expect "tells the user" 'grep -q "not installed" "$work/notify.log"'

# The faults reported against Omarchroma, replayed here: integrate runs
# unattended at every shell start, so nothing planted in the user's data
# folders may redirect its writes or deletes, or hang it.
echo "== a symlinked applications folder is refused, not written through"
install_copy
mkdir -p "$work/elsewhere"
rm -rf "$data/applications" && ln -s "$work/elsewhere" "$data/applications"
integrate >/dev/null 2>&1; rc=$?
expect "fails" '[[ $rc != 0 ]]'
expect "nothing written through the link" '[[ -z $(ls -A "$work/elsewhere") ]]'
rm "$data/applications" && mkdir "$data/applications"

echo "== a FIFO planted as the entry neither hangs nor is replaced"
mkfifo "$desktop"
timeout 30 "$plugin/bin/omascayl-integrate" install "$plugin" >/dev/null 2>&1; rc=$?
expect "does not hang" '[[ $rc != 124 ]]'
expect "FIFO left alone" '[[ -p $desktop ]]'
rm -f "$desktop"

echo "== a symlinked entry is not followed"
echo keep > "$work/victim"
ln -s "$work/victim" "$desktop"
integrate >/dev/null 2>&1
expect "target unchanged" '[[ $(cat "$work/victim") == keep ]]'
rm -f "$desktop"

echo "== no temporary files left behind"
integrate >/dev/null 2>&1
expect "no leftovers" '[[ -z $(find "$data" "$HOME/.local/bin" -name ".*.*") ]]'

echo "== cleanup does not follow a symlinked backend"
mkdir -p "$work/precious" && touch "$work/precious/file"
rm -rf "$data/omascayl/backend" && ln -s "$work/precious" "$data/omascayl/backend"
"$stub" --cleanup-if-removed & p=$!
sleep 0.3
rm -rf "$plugin"
wait $p
expect "link target kept" '[[ -f $work/precious/file ]]'
expect "link itself removed" '[[ ! -e $data/omascayl/backend && ! -L $data/omascayl/backend ]]'

echo "passed $pass, failed $fail"
[[ $fail == 0 ]]
