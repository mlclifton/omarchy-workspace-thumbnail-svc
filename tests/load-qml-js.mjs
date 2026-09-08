// Loads a QML JavaScript resource (lib/*.js) into node.
//
// QML JS modules are not ES modules and not CommonJS: they are a bare script
// with `.pragma library` at the top and plain function declarations, consumed
// by QML as `import "Geometry.js" as Geometry`. Rather than keep a duplicate
// copy for tests to import, compile the real file and lift its declarations
// out. One source of truth, so a test can never pass against a stale copy.
//
// This deliberately uses `new Function` rather than `node:vm`. A vm context is
// a separate realm, so arrays and objects it builds have different intrinsics
// and `assert.deepStrictEqual` rejects structurally identical values. Compiling
// in the host realm keeps the returned data ordinary.

import { readFileSync } from "node:fs"
import { dirname, resolve } from "node:path"
import { fileURLToPath } from "node:url"

const here = dirname(fileURLToPath(import.meta.url))

export function loadQmlJs(relativePath) {
  const path = resolve(here, "..", relativePath)
  const source = readFileSync(path, "utf8")

  // `.pragma library` / `.import ...` are QML engine directives, not valid
  // JavaScript, so strip them before compiling.
  const stripped = source.replace(/^\s*\.(pragma|import)[^\n]*$/gm, "")

  const names = [...stripped.matchAll(/^function\s+([A-Za-z0-9_$]+)\s*\(/gm)].map((m) => m[1])
  if (names.length === 0) throw new Error(`no top-level functions found in ${relativePath}`)

  const factory = new Function(`${stripped}\nreturn { ${names.join(", ")} };`)
  return factory()
}
