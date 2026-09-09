#!/usr/bin/env bash
# Vendor this component into a consuming Omarchy plugin.
#
#   ./install.sh ~/Projects/mybarwidget [vendor-subdir]
#
# Copies the component into <target>/<vendor-subdir>/ (default "thumbnails")
# and then checks the target's manifest declares the service entry point.
#
# Why a copy rather than a cross-plugin service: since Omarchy 4.0.3 a
# third-party plugin may only look up its OWN service, so the thumbnail service
# has to ship inside its consumer and share that plugin's id. See
# IMPLEMENTATION.md, "Why this is vendored".
set -euo pipefail
cd "$(dirname "$0")"

target=${1:-}
vendor=${2:-thumbnails}

if [[ -z "$target" ]]; then
  echo "usage: $0 <path-to-consumer-plugin-repo> [vendor-subdir]" >&2
  exit 2
fi
[[ -d "$target" ]] || { echo "fail: '$target' is not a directory" >&2; exit 1; }
[[ -f "$target/manifest.json" ]] || { echo "fail: '$target/manifest.json' not found - is that a plugin repo?" >&2; exit 1; }

# Everything the service needs at runtime. Deliberately not the tests, notes,
# or this script: the consumer vendors code, not the development lane.
files=(Service.qml WorkspaceThumbnail.qml WindowTile.qml lib/Geometry.js)

dest="$target/$vendor"
mkdir -p "$dest/lib"

changed=0
for f in "${files[@]}"; do
  [[ -f "$f" ]] || { echo "fail: $f missing from this repo" >&2; exit 1; }
  if ! cmp -s "$f" "$dest/$f"; then
    cp "$f" "$dest/$f"
    echo "  updated $vendor/$f"
    changed=1
  fi
done

if (( changed )); then
  echo "vendored into $dest"
else
  echo "already up to date at $dest"
fi

# ------------------------------------------------------------------- manifest
#
# The consumer owns its manifest, so report rather than rewrite it.
if ! command -v jq >/dev/null; then
  echo "note: jq not found, skipping manifest check" >&2
  exit 0
fi

want_entry="$vendor/Service.qml"
problems=0

jq -e '.kinds | index("service")' "$target/manifest.json" >/dev/null 2>&1 || {
  echo "fail: $target/manifest.json kinds must include \"service\"" >&2
  problems=1
}

have_entry=$(jq -r '.entryPoints.service // ""' "$target/manifest.json")
if [[ "$have_entry" != "$want_entry" ]]; then
  echo "fail: $target/manifest.json entryPoints.service is '$have_entry', expected '$want_entry'" >&2
  problems=1
fi

if (( problems )); then
  echo "" >&2
  echo "Merge manifest.fragment.json into $target/manifest.json, then re-run." >&2
  exit 1
fi

echo "manifest ok: service mounts from $want_entry"
