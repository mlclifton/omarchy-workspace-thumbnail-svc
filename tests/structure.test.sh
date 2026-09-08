#!/usr/bin/env bash
# Structural invariants for the plugin.
#
# These are cheap and they guard the architecture rather than the behaviour.
# The layering below is what makes the rest of the suite possible at all: if
# WorkspaceThumbnail.qml ever imports Quickshell, tst_thumbnail.qml stops being
# runnable headless and the layout coverage silently disappears.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "fail: $*" >&2; exit 1; }
pass() { echo "  ok: $*"; }

# ---------------------------------------------------------------- manifest
[[ -f manifest.json ]] || fail "manifest.json missing"
command -v jq >/dev/null || fail "jq is required"

id=$(jq -r .id manifest.json)
[[ "$id" == "mlclifton.workspace-thumbnails" ]] || fail "manifest id is '$id'"
[[ "$(jq -r .schemaVersion manifest.json)" == "1" ]] || fail "schemaVersion must be 1"
jq -e '.kinds | index("service")' manifest.json >/dev/null || fail "kinds must include 'service'"

entry=$(jq -r .entryPoints.service manifest.json)
[[ -n "$entry" && "$entry" != "null" ]] || fail "entryPoints.service missing"
[[ -f "$entry" ]] || fail "entryPoints.service points at missing file '$entry'"
[[ "$entry" != /* && "$entry" != *..* ]] || fail "entryPoints.service must be a relative path inside the plugin"
pass "manifest declares a service entry point at $entry"

for required in LICENSE README.md IMPLEMENTATION.md Service.qml WorkspaceThumbnail.qml WindowTile.qml lib/Geometry.js; do
  [[ -f "$required" ]] || fail "$required missing"
done
pass "all expected files present"

# ------------------------------------------------------------------ layering
#
# Three rules, each protecting a different test lane. These inspect code only:
# the files document their own layering in comments, and a naive grep would
# match the prose describing the rule it is enforcing.
code_of() { sed -e 's|//.*||' "$1"; }

# 1. Geometry.js must stay pure JavaScript: no QML types, no singletons. This is
#    what lets tests/geometry.test.mjs load it into node.
if code_of lib/Geometry.js | grep -nE '\b(Hyprland|Quickshell|Qt\.|Style|Color)\b'; then
  fail "lib/Geometry.js must stay pure JS - the node suite loads it outside QML"
fi
grep -q '^\.pragma library' lib/Geometry.js || fail "lib/Geometry.js must declare '.pragma library'"
pass "lib/Geometry.js is pure JavaScript"

# 2. WorkspaceThumbnail.qml must import only QtQuick and the geometry module.
#    This is what lets tst_thumbnail.qml run headless with a stub tile.
if grep -nE '^import (Quickshell|.*Wayland|qs\.)' WorkspaceThumbnail.qml; then
  fail "WorkspaceThumbnail.qml must not import Quickshell - move it to WindowTile.qml or Service.qml"
fi
grep -q 'property Component tileComponent' WorkspaceThumbnail.qml \
  || fail "WorkspaceThumbnail.qml must accept an injected tileComponent"
pass "WorkspaceThumbnail.qml is QtQuick-only and takes an injected tile"

# 3. Only WindowTile.qml may touch screencopy, and only Service.qml may touch
#    Hyprland. Keeps the compositor surface area to two small files.
for f in Service.qml WorkspaceThumbnail.qml lib/Geometry.js; do
  code_of "$f" | grep -q 'ScreencopyView' && fail "ScreencopyView belongs in WindowTile.qml, found in $f"
done
code_of WindowTile.qml | grep -q 'ScreencopyView' || fail "WindowTile.qml should own the ScreencopyView"

for f in WorkspaceThumbnail.qml WindowTile.qml; do
  grep -qE '^import Quickshell\.Hyprland' "$f" && fail "Hyprland access belongs in Service.qml, found in $f"
done
pass "compositor access is confined to Service.qml and WindowTile.qml"

# ------------------------------------------------------------------- service
grep -q 'property var shell' Service.qml \
  || fail "Service.qml must expose 'shell' for omarchy-shell's service loader to inject"
grep -q 'function frameFor' Service.qml || fail "Service.qml must expose frameFor()"
grep -q 'thumbnailComponent' Service.qml || fail "Service.qml must expose thumbnailComponent"
pass "service exposes the documented API"

echo "structure: ok"
