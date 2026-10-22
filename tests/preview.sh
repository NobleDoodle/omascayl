#!/usr/bin/bash
# Tests bin/omascayl-preview: the copy the window displays must keep the
# pixels and drop everything a codec could inflate inside omarchy-shell.
# Needs ImageMagick (magick) and Qt's qml tool; offscreen, scratch dirs only.
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
cache="$work/cache"; img="$work/img"
mkdir -p "$cache" "$img"
preview="$here/bin/omascayl-preview"

pass=0; fail=0
expect() { if eval "$2"; then echo "  ok   $1"; pass=$((pass+1)); else echo "  FAIL $1"; fail=$((fail+1)); fi; }

# A 1x1 PNG with N zTXt chunks that each inflate to ~7.9 MB.
make_bomb() {
  /usr/bin/python3 -I - "$1" "$2" <<'PY'
import struct, sys, zlib
def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
out, n = sys.argv[1], int(sys.argv[2])
text = zlib.compress(b"A" * 7_900_000, 9)
parts = [b"\x89PNG\r\n\x1a\n", chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))]
parts += [chunk(b"zTXt", b"Comment%d\0\0" % i + text) for i in range(n)]
parts += [chunk(b"iCCP", b"icc\0\0" + text), chunk(b"IDAT", zlib.compress(b"\x00\xff\x00\x00")), chunk(b"IEND", b"")]
open(out, "wb").write(b"".join(parts))
PY
}

# Qt's own decode of a file, offscreen, with the process's peak memory in MB.
qt_load() {
  cat > "$work/load.qml" <<'QML'
import QtQuick
Item {
  Image {
    asynchronous: true
    source: Qt.application.arguments[Qt.application.arguments.length - 1]
    onStatusChanged: if (status === Image.Ready || status === Image.Error) {
      console.log("STATUS " + (status === Image.Ready ? "ready" : "error") + " " + implicitWidth + "x" + implicitHeight)
      Qt.quit()
    }
  }
}
QML
  env -u DISPLAY -u WAYLAND_DISPLAY -u QT_QPA_PLATFORMTHEME QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
    /usr/bin/python3 -I -c '
import resource, subprocess, sys
r = subprocess.run(sys.argv[1:], capture_output=True, text=True, timeout=60)
line = next((l for l in r.stderr.splitlines() if "STATUS" in l), "STATUS none")
print(line.split("STATUS ", 1)[1], int(resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss / 1024))
' /usr/lib/qt6/bin/qml "$work/load.qml" "file://$1"
}

run() { "$preview" "$1" "$2" "$cache" 2> "$work/err.txt"; }

echo "== the attack: compressed text and iCCP chunks"
make_bomb "$img/bomb.png" 20
out=$(run before "$img/bomb.png"); rc=$?
copy=$(cut -f1 <<< "$out")
expect "accepted as a 1x1 PNG" '[[ $rc == 0 && $(cut -f2- <<< "$out") == "1	1	png" ]]'
expect "the copy has no text or iCCP chunks" '! grep -qaE "zTXt|iCCP|tEXt|iTXt" "$copy"'
expect "the copy is tiny" '(( $(stat -c %s "$copy") < 200 ))'
read -r st dims mb <<< "$(qt_load "$copy")"
expect "Qt loads the copy in normal memory ($mb MB)" '[[ $st == ready && $dims == 1x1 ]] && (( mb < 150 ))'

echo "== real images keep their pixels and lose their metadata"
magick rose: -resize 200% "$img/base.png"
magick rose: -profile /dev/null -set comment "a comment" -define png:color-type=6 "$img/meta.png" 2>/dev/null \
  || magick rose: -set comment "a comment" "$img/meta.png"
magick "$img/base.png" -type Palette PNG8:"$img/palette.png"
magick "$img/base.png" -depth 16 PNG48:"$img/deep.png"
magick "$img/base.png" -interlace PNG "$img/interlaced.png"
magick "$img/base.png" -colorspace Gray -alpha set -channel A -evaluate set 60% +channel PNG:"$img/grayalpha.png"
magick "$img/base.png" -set comment "a comment" -quality 90 "$img/baseline.jpg"
magick "$img/base.png" -interlace JPEG -quality 90 "$img/progressive.jpg"
magick "$img/base.png" -colorspace CMYK -quality 90 "$img/cmyk.jpg"
magick "$img/base.png" -quality 80 "$img/lossy.webp"
magick "$img/base.png" -define webp:lossless=true "$img/lossless.webp"
magick "$img/base.png" -alpha set -channel A -evaluate set 50% +channel -quality 80 "$img/alpha.webp"
exiftool_like() { magick "$1" -set comment "big comment" -set exif:Artist "someone" "$2" 2>/dev/null; }
exiftool_like "$img/baseline.jpg" "$img/exif.jpg"
for f in meta.png palette.png deep.png interlaced.png grayalpha.png baseline.jpg progressive.jpg cmyk.jpg exif.jpg lossy.webp lossless.webp alpha.webp; do
  out=$(run before "$img/$f"); rc=$?
  copy=$(cut -f1 <<< "$out")
  w=$(magick identify -format %w "$img/$f"); h=$(magick identify -format %h "$img/$f")
  expect "$f: accepted, size ${w}x$h" '[[ $rc == 0 && $(cut -f2,3 <<< "$out") == "$w	$h" ]]'
  expect "$f: same pixels" '[[ $(magick compare -metric AE "$img/$f" "$copy" null: 2>&1) == 0* ]]'
  expect "$f: no comment left" '! magick identify -verbose "$copy" 2>/dev/null | grep -qi "comment"'
  read -r st dims mb <<< "$(qt_load "$copy")"
  expect "$f: Qt loads the copy" '[[ $st == ready ]]'
done

echo "== the type comes from the bytes, not the name"
cp "$img/baseline.jpg" "$img/really-a-jpeg.png"
out=$(run before "$img/really-a-jpeg.png"); rc=$?
expect "a JPEG named .png becomes a .jpg copy" '[[ $rc == 0 && $(cut -f4 <<< "$out") == jpg && $(cut -f1 <<< "$out") == *.jpg ]]'
printf 'not an image' > "$img/fake.png"
run before "$img/fake.png" >/dev/null; rc=$?
expect "text named .png refused" '[[ $rc == 1 ]] && grep -q "not a PNG, JPEG or WebP" "$work/err.txt"'

echo "== files that are not plain images are refused without hanging"
mkfifo "$img/fifo.png"
timeout 10 "$preview" before "$img/fifo.png" "$cache" >/dev/null 2>&1; rc=$?
expect "a FIFO: refused, no hang" '[[ $rc == 1 ]]'
timeout 10 "$preview" before /dev/zero "$cache" >/dev/null 2>&1; rc=$?
expect "a device: refused" '[[ $rc == 1 ]]'
head -c 300 "$img/base.png" > "$img/truncated.png"
run before "$img/truncated.png" >/dev/null; rc=$?
expect "a truncated PNG: refused" '[[ $rc == 1 ]] && grep -q "ends early" "$work/err.txt"'
magick "$img/base.png" \( +clone -negate \) -loop 0 "$img/anim.webp"
run before "$img/anim.webp" >/dev/null; rc=$?
expect "an animated WebP: refused" '[[ $rc == 1 ]] && grep -q "animated" "$work/err.txt"'

echo "== the cache keeps one copy per slot, written privately"
rm -rf "$cache/preview"
run before "$img/base.png" > /dev/null; run before "$img/lossy.webp" > /dev/null; run after "$img/base.png" > /dev/null
expect "one before, one after" '[[ $(ls "$cache/preview" | grep -c "^before-") == 1 && $(ls "$cache/preview" | grep -c "^after-") == 1 ]]'
expect "no temporaries left" '[[ -z $(ls -A "$cache/preview" | grep "^\.") ]]'
expect "copies are private (0600)" '[[ $(stat -c %a "$cache/preview"/before-*) == 600 ]]'
rm -rf "$cache/preview" && mkdir -p "$work/elsewhere" && ln -s "$work/elsewhere" "$cache/preview"
run before "$img/base.png" >/dev/null; rc=$?
expect "a symlinked preview folder is refused" '[[ $rc == 2 && -z $(ls -A "$work/elsewhere") ]]'

echo "passed $pass, failed $fail"
[[ $fail == 0 ]]
