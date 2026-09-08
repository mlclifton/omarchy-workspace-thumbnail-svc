#!/usr/bin/env bash
# Full test suite. Runs offline and headless - no compositor, no running shell.
#
#   tests/run.sh          everything
#   tests/run.sh unit     node tests of lib/Geometry.js only (fastest loop)
#
# Four lanes, cheapest first:
#   structure  architectural invariants that keep the other lanes runnable
#   unit       lib/Geometry.js under node, where the maths is covered in depth
#   lint       qmllint against the real Quickshell and qs.Commons modules
#   qml        qmltestrunner: the JS module in QML's engine, plus layout
set -euo pipefail
cd "$(dirname "$0")/.."

QT_BIN=${QT_BIN:-/usr/lib/qt6/bin}
OMARCHY_SHELL=${OMARCHY_SHELL:-/usr/share/omarchy/shell}
lane=${1:-all}
failed=0

step() { printf '\n\033[1m== %s\033[0m\n' "$1"; }
softfail() { echo "FAIL: $1" >&2; failed=1; }

if [[ "$lane" == "all" || "$lane" == "structure" ]]; then
  step "structure"
  bash tests/structure.test.sh || softfail "structure"
fi

if [[ "$lane" == "all" || "$lane" == "unit" ]]; then
  step "unit (node)"
  if command -v node >/dev/null; then
    node --test "tests/**/*.test.mjs" || softfail "unit"
  else
    echo "SKIP: node not found"
  fi
fi

if [[ "$lane" == "all" || "$lane" == "lint" ]]; then
  step "lint (qmllint)"
  if [[ -x "$QT_BIN/qmllint" ]]; then
    # Quickshell exposes the shell root as the `qs` module, so qmllint needs a
    # directory containing `qs` on its import path to resolve qs.Commons.
    shim=$(mktemp -d)
    trap 'rm -rf "$shim"' EXIT
    if [[ -d "$OMARCHY_SHELL" ]]; then
      ln -sfn "$OMARCHY_SHELL" "$shim/qs"
    else
      echo "note: $OMARCHY_SHELL not found; linting without qs.Commons"
    fi
    "$QT_BIN/qmllint" -I "$shim" -I /usr/lib/qt6/qml \
      Service.qml WorkspaceThumbnail.qml WindowTile.qml || softfail "lint"
  else
    echo "SKIP: qmllint not found (set QT_BIN)"
  fi
fi

if [[ "$lane" == "all" || "$lane" == "qml" ]]; then
  step "qml (qmltestrunner)"
  if [[ -x "$QT_BIN/qmltestrunner" ]]; then
    QT_QPA_PLATFORM=offscreen "$QT_BIN/qmltestrunner" -input tests/ || softfail "qml"
  else
    echo "SKIP: qmltestrunner not found (set QT_BIN)"
  fi
fi

if (( failed )); then
  printf '\n\033[31msuite failed\033[0m\n'
  exit 1
fi
printf '\n\033[32mall green\033[0m\n'
