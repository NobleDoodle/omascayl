import assert from "node:assert/strict"
import { readFileSync, readdirSync } from "node:fs"
import { join } from "node:path"
import { fileURLToPath } from "node:url"
import { test } from "node:test"

const rootPath = fileURLToPath(new URL("../", import.meta.url))

function qmlFiles(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap(entry => {
    if (entry.name.startsWith(".") || entry.name === "node_modules") return []
    const path = join(dir, entry.name)
    if (entry.isDirectory()) return qmlFiles(path)
    return entry.name.endsWith(".qml") ? [path] : []
  })
}

// Qt 6.12 adds a QtQuick type named Color, which shadows the qs.Commons Color
// singleton: a bare `Color.foreground` evaluates to undefined and the app
// draws without its theme. Reach the singleton through the module alias instead.
test("QML reaches the Commons Color singleton through its alias", () => {
  for (const path of qmlFiles(rootPath)) {
    const source = readFileSync(path, "utf8")
    const bare = source.split("\n").filter(line => /(^|[^A-Za-z0-9_.])Color\./.test(line))
    assert.deepEqual(bare, [], `${path} uses a bare Color.`)
    if (source.includes("Commons.Color."))
      assert.match(source, /^import qs\.Commons as Commons$/m, `${path} lacks the Commons alias`)
  }
})
