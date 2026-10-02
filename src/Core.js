.pragma library

// Pure logic shared by the UI and the job runner: the model catalog, the
// upscayl-bin argument lists, output naming and progress/error parsing.
// It ports Upscayl's electron/utils/get-arguments, electron/commands/*-upscayl
// and common/* modules, and stays free of QML types so tests/core.test.mjs
// can load it in node.

// Every command runs by absolute path, with this PATH for anything it starts
// itself. A bare name would be resolved through omarchy-shell's inherited
// PATH, which can hold user-writable directories; both directories here are
// root-owned on Omarchy. BIN is the one place commands are looked up.
var BIN = "/usr/bin/"
var TRUSTED_PATH = "/usr/bin:/usr/share/omarchy/bin"

function bin(name) { return BIN + name }

function isAbsolutePath(path) {
  return typeof path === "string" && path.length > 1 && path.charAt(0) === "/" && path.indexOf("\0") === -1
}

var IMAGE_EXTENSIONS = ["png", "jpg", "jpeg", "jfif", "webp"]
var FORMATS = ["png", "jpg", "webp"]

// Upscayl's built-in models, in the order its model picker lists them.
var MODELS = [
  { id: "upscayl-standard-4x", name: "Upscayl Standard", description: "Suitable for most images." },
  { id: "upscayl-lite-4x", name: "Upscayl Lite", description: "Suitable for most images. High-speed upscaling with minimal quality loss." },
  { id: "high-fidelity-4x", name: "High Fidelity", description: "For all kinds of images with a focus on realistic details and smooth textures." },
  { id: "remacri-4x", name: "Remacri (Non-Commercial)", description: "For natural images. Added sharpness and detail. No commercial use." },
  { id: "ultramix-balanced-4x", name: "Ultramix (Non-Commercial)", description: "For natural images with a balance of sharpness and detail." },
  { id: "ultrasharp-4x", name: "Ultrasharp (Non-Commercial)", description: "For natural images with a focus on sharpness." },
  { id: "digital-art-4x", name: "Digital Art", description: "For digital art and illustrations." }
]

var DEFAULT_MODEL = "upscayl-standard-4x"

function modelInfo(id) {
  for (var i = 0; i < MODELS.length; i++) if (MODELS[i].id === id) return MODELS[i]
  return { id: id, name: id, description: "Custom model." }
}

// The scale a model upscales by natively, read from its name the way
// Upscayl (and upscayl-bin itself) does: "x2"/"2x" -> 2, "x3"/"3x" -> 3, else 4.
function modelScale(model) {
  var name = String(model || "").toLowerCase()
  if (name.indexOf("x2") !== -1 || name.indexOf("2x") !== -1) return "2"
  if (name.indexOf("x3") !== -1 || name.indexOf("3x") !== -1) return "3"
  return "4"
}

// Model names from a directory listing: every *.param / *.bin basename,
// deduplicated, in listing order.
function modelNamesFromFiles(files) {
  var names = []
  for (var i = 0; i < files.length; i++) {
    var f = String(files[i])
    if (!/\.(param|bin)$/i.test(f)) continue
    var name = f.substring(0, f.lastIndexOf(".")) || f
    if (names.indexOf(name) === -1) names.push(name)
  }
  return names
}

// Built-in models first (in catalog order, only the installed ones), then
// any other model found next to them.
function orderInstalledModels(names) {
  var out = []
  for (var i = 0; i < MODELS.length; i++)
    if (names.indexOf(MODELS[i].id) !== -1) out.push(MODELS[i].id)
  for (var j = 0; j < names.length; j++)
    if (out.indexOf(names[j]) === -1) out.push(names[j])
  return out
}

function baseName(path) {
  var p = String(path || "").replace(/\/+$/, "")
  return p.substring(p.lastIndexOf("/") + 1)
}

function dirName(path) {
  var p = String(path || "").replace(/\/+$/, "")
  var i = p.lastIndexOf("/")
  if (i < 0) return "."
  return i === 0 ? "/" : p.substring(0, i)
}

function stem(path) {
  var base = baseName(path)
  var dot = base.lastIndexOf(".")
  return dot > 0 ? base.substring(0, dot) : base
}

function extensionOf(path) {
  var base = baseName(path)
  var dot = base.lastIndexOf(".")
  return dot > 0 ? base.substring(dot + 1).toLowerCase() : ""
}

function isImagePath(path) {
  return IMAGE_EXTENSIONS.indexOf(extensionOf(path)) !== -1
}

function joinPath(dir, name) {
  return (dir === "/" ? "" : String(dir).replace(/\/+$/, "")) + "/" + name
}

// file:// URL (from a drop, a dialog or text/uri-list) -> local path.
// Plain absolute paths pass through; anything else is rejected with "".
function pathFromUrl(url) {
  var s = String(url || "").trim()
  if (s.indexOf("file://") !== 0) return s.charAt(0) === "/" ? s : ""
  s = s.substring(7)
  if (s.charAt(0) !== "/") s = s.substring(s.indexOf("/"))  // file://host/path
  try { return decodeURIComponent(s) } catch (e) { return s }
}

function fileUrl(path) {
  return "file://" + String(path).split("/").map(encodeURIComponent).join("/")
}

function usesCustomWidth(opts) {
  return !!opts.useCustomWidth && opts.customWidth > 0
}

// The "<scale>x" or "<width>px" tag Upscayl puts in output names.
function sizeTag(opts) {
  return usesCustomWidth(opts) ? opts.customWidth + "px" : opts.scale + "x"
}

// <outputDir>/<name>_upscayl_<4x|1920px>_<model>.<format>
function outputFile(opts) {
  return joinPath(opts.outputDir,
    stem(opts.input) + "_upscayl_" + sizeTag(opts) + "_" + opts.model + "." + opts.format)
}

// <outputDir>/upscayl_<format>_<model>_<4x|1920px>
function batchOutputDir(opts) {
  return joinPath(opts.outputDir,
    "upscayl_" + opts.format + "_" + opts.model + "_" + sizeTag(opts))
}

// opts: { input, output, modelsPath, model, scale, gpuId, format,
//         useCustomWidth, customWidth, compression, tileSize, tta }
// pass: "single" | "batch" | "double1" | "double2"
function buildArgs(opts, pass) {
  var custom = usesCustomWidth(opts)
  var includeScale = modelScale(opts.model) !== String(opts.scale) && !custom
  // Double Upscayl's first pass skips width, compression and TTA; the second
  // pass applies them to the first pass's output, in place.
  var first = pass === "double1"
  var args = ["-i", opts.input, "-o", opts.output]
  if (includeScale) args.push("-s", String(opts.scale))
  args.push("-m", opts.modelsPath, "-n", opts.model)
  if (opts.gpuId !== undefined && opts.gpuId !== null && String(opts.gpuId) !== "")
    args.push("-g", String(opts.gpuId))
  args.push("-f", opts.format)
  if (custom && !first) args.push("-w", String(opts.customWidth))
  if (!first) args.push("-c", String(opts.compression || 0))
  if (opts.tileSize > 0) args.push("-t", String(opts.tileSize))
  if (opts.tta && !first) args.push("-x")
  return args
}

// Final dimensions for "Upscayl from WxH to WxH".
function targetSize(width, height, opts) {
  if (!(width > 0 && height > 0)) return null
  if (usesCustomWidth(opts))
    return { width: opts.customWidth, height: Math.round(height / width * opts.customWidth) }
  var s = parseInt(opts.scale) || 4
  var f = opts.doubleUpscayl ? s * s : s
  return { width: width * f, height: height * f }
}

// One line of upscayl-bin stderr -> what it means for the UI.
//   { kind: "progress", percent }   "12.34%"
//   { kind: "error", message }      Upscayl kills the run on these
//   { kind: "gpu", id, name }       a Vulkan device announcement
//   { kind: "resizing" }            output-scale resize after the model pass
//   { kind: "success" }             one image finished
//   { kind: "info" }                anything else
function parseLine(line) {
  var s = String(line || "").trim()
  var m = /^(\d+(?:\.\d+)?)%$/.exec(s)
  if (m) return { kind: "progress", percent: parseFloat(m[1]) }
  // Upscayl matches these substrings, case-sensitively, on every chunk.
  if (s.indexOf("Error") !== -1 || s.indexOf("failed") !== -1) return { kind: "error", message: s }
  var g = /^\[(\d+) ([^\]]+)\]/.exec(s)
  if (g) return { kind: "gpu", id: parseInt(g[1]), name: g[2] }
  if (s.indexOf("Resizing") !== -1) return { kind: "resizing" }
  if (s.indexOf("Successful") !== -1) return { kind: "success" }
  return { kind: "info" }
}

// Upscayl's error dialog title and description for a backend error.
function describeError(message) {
  var m = String(message || "")
  if (m.indexOf("Invalid GPU") !== -1)
    return { title: "GPU Error", description: "Ran into an issue with the GPU. Please read the docs for troubleshooting! (" + m + ")" }
  if (m.indexOf("write") !== -1 || m.indexOf("read") !== -1)
    return { title: "Read/Write Error", description: "Make sure that the path is correct and you have proper read/write permissions.\n(" + m + ")" }
  if (m.indexOf("tile size") !== -1)
    return { title: "Error", description: "The tile size is wrong. Please change the tile size in the settings or set to 0 (" + m + ")" }
  return { title: "Error", description: m }
}

function formatDuration(ms) {
  if (!(ms > 0)) return "-"
  var s = Math.round(ms / 1000)
  if (s < 60) return s + "s"
  return Math.floor(s / 60) + "m " + (s % 60) + "s"
}
