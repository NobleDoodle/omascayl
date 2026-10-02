// node --test tests/
// Loads src/Core.js (a QML ".pragma library" script) into a plain context.
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

const source = readFileSync(new URL("../src/Core.js", import.meta.url), "utf8")
  .replace(/^\.pragma library$/m, "")
const Core = {}
const raw = {}
vm.runInNewContext(source + "\n;Object.assign(__out, { IMAGE_EXTENSIONS, FORMATS, MODELS, DEFAULT_MODEL, modelInfo, modelScale, modelNamesFromFiles, orderInstalledModels, baseName, dirName, stem, extensionOf, isImagePath, joinPath, pathFromUrl, fileUrl, sizeTag, outputFile, batchOutputDir, buildArgs, targetSize, parseLine, describeError, formatDuration })", { __out: raw })
// Results cross a vm context; JSON makes them plain objects for deepEqual.
for (const [k, v] of Object.entries(raw)) Core[k] = typeof v === "function" ? (...a) => { const r = v(...a); return r && typeof r === "object" ? JSON.parse(JSON.stringify(r)) : r } : JSON.parse(JSON.stringify(v))

const base = {
  input: "/pics/cat.png", output: "/out/cat_upscayl_4x_upscayl-standard-4x.png",
  modelsPath: "/usr/share/upscayl/models", model: "upscayl-standard-4x", scale: "4",
  gpuId: "", format: "png", useCustomWidth: false, customWidth: 0,
  compression: 0, tileSize: 0, tta: false,
}

test("model scale comes from the name", () => {
  assert.equal(Core.modelScale("upscayl-standard-4x"), "4")
  assert.equal(Core.modelScale("RealESRGAN_x2plus"), "2")
  assert.equal(Core.modelScale("my-3x-model"), "3")
  assert.equal(Core.modelScale("whatever"), "4")
})

test("single image arguments match Upscayl", () => {
  assert.deepEqual(Core.buildArgs(base, "single"), [
    "-i", "/pics/cat.png", "-o", "/out/cat_upscayl_4x_upscayl-standard-4x.png",
    "-m", "/usr/share/upscayl/models", "-n", "upscayl-standard-4x", "-f", "png", "-c", "0"])
})

test("scale, gpu, width, tile and tta flags", () => {
  assert.deepEqual(Core.buildArgs({ ...base, scale: "2", gpuId: "1", tileSize: 256, tta: true, compression: 30 }, "single"), [
    "-i", "/pics/cat.png", "-o", base.output, "-s", "2", "-m", base.modelsPath, "-n", base.model,
    "-g", "1", "-f", "png", "-c", "30", "-t", "256", "-x"])
  // A custom width replaces the scale.
  assert.deepEqual(Core.buildArgs({ ...base, scale: "2", useCustomWidth: true, customWidth: 1920 }, "single"), [
    "-i", "/pics/cat.png", "-o", base.output, "-m", base.modelsPath, "-n", base.model,
    "-f", "png", "-w", "1920", "-c", "0"])
})

test("double upscayl: first pass skips width, compression and tta", () => {
  const opts = { ...base, scale: "2", compression: 10, tta: true, useCustomWidth: true, customWidth: 800 }
  assert.deepEqual(Core.buildArgs(opts, "double1"), [
    "-i", "/pics/cat.png", "-o", base.output, "-m", base.modelsPath, "-n", base.model, "-f", "png"])
  assert.deepEqual(Core.buildArgs({ ...opts, input: base.output }, "double2"), [
    "-i", base.output, "-o", base.output, "-m", base.modelsPath, "-n", base.model,
    "-f", "png", "-w", "800", "-c", "10", "-x"])
})

test("output naming", () => {
  const o = { input: "/a/b/my.photo.jpeg", outputDir: "/out/", model: "remacri-4x", format: "webp", scale: "8" }
  assert.equal(Core.outputFile(o), "/out/my.photo_upscayl_8x_remacri-4x.webp")
  assert.equal(Core.outputFile({ ...o, useCustomWidth: true, customWidth: 1000 }), "/out/my.photo_upscayl_1000px_remacri-4x.webp")
  assert.equal(Core.batchOutputDir({ ...o, outputDir: "/" }), "/upscayl_webp_remacri-4x_8x")
})

test("paths and urls", () => {
  assert.equal(Core.pathFromUrl("file:///home/me/My%20Pics/a%23b.png"), "/home/me/My Pics/a#b.png")
  assert.equal(Core.pathFromUrl("file://localhost/tmp/x.png"), "/tmp/x.png")
  assert.equal(Core.pathFromUrl("/plain/path.png"), "/plain/path.png")
  assert.equal(Core.pathFromUrl("https://example.com/x.png"), "")
  assert.equal(Core.fileUrl("/home/me/My Pics/a#b.png"), "file:///home/me/My%20Pics/a%23b.png")
  assert.equal(Core.dirName("/x.png"), "/")
  assert.equal(Core.dirName("/a/b/"), "/a")
  assert.ok(Core.isImagePath("/a/B.JFIF"))
  assert.ok(!Core.isImagePath("/a/b.gif"))
  assert.ok(!Core.isImagePath("/a/.png"))
})

test("models from a folder listing", () => {
  const names = Core.modelNamesFromFiles(["x.param", "x.bin", "README.md", "y.BIN", "digital-art-4x.param"])
  assert.deepEqual(names, ["x", "y", "digital-art-4x"])
  assert.deepEqual(Core.orderInstalledModels(["zzz", "digital-art-4x", "upscayl-lite-4x"]),
    ["upscayl-lite-4x", "digital-art-4x", "zzz"])
  assert.equal(Core.modelInfo("remacri-4x").name, "Remacri (Non-Commercial)")
  assert.equal(Core.modelInfo("custom").name, "custom")
})

test("target size", () => {
  assert.deepEqual(Core.targetSize(100, 50, { scale: "4" }), { width: 400, height: 200 })
  assert.deepEqual(Core.targetSize(100, 50, { scale: "4", doubleUpscayl: true }), { width: 1600, height: 800 })
  assert.deepEqual(Core.targetSize(100, 50, { scale: "4", useCustomWidth: true, customWidth: 333 }), { width: 333, height: 167 })
  assert.equal(Core.targetSize(0, 0, { scale: "4" }), null)
})

test("stderr lines", () => {
  assert.deepEqual(Core.parseLine("12.34%"), { kind: "progress", percent: 12.34 })
  assert.deepEqual(Core.parseLine("100.00%"), { kind: "progress", percent: 100 })
  assert.equal(Core.parseLine("🚨 Error: Invalid GPU Device").kind, "error")
  assert.equal(Core.parseLine("fopen /m/bogus.param failed").kind, "error")
  assert.deepEqual(Core.parseLine("[1 NVIDIA GeForce MX350]  queueC=2[8]  queueG=0[16]"), { kind: "gpu", id: 1, name: "NVIDIA GeForce MX350" })
  assert.equal(Core.parseLine("🏞️ Resizing image according to output scale").kind, "resizing")
  assert.equal(Core.parseLine("🙌 Upscayled Successfully!").kind, "success")
  assert.equal(Core.parseLine("✨ Detected scale x4").kind, "info")
})

test("error descriptions follow Upscayl's mapping", () => {
  assert.equal(Core.describeError("🚨 Error: Invalid GPU Device").title, "GPU Error")
  assert.equal(Core.describeError("🚨 Error: Couldn't read the image 'x'!").title, "Read/Write Error")
  assert.match(Core.describeError("bad tile size").description, /tile size is wrong/)
  assert.equal(Core.describeError("fopen x failed").title, "Error")
})
