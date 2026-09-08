# Implementation notes

Working notes for `mlclifton.workspace-thumbnails`. Written for whoever (or
whatever) picks this up next — read this before changing code.

## What this is and why it exists

A **service** plugin that renders monitor-shaped thumbnails of Hyprland
workspaces. It draws nothing itself; it hands consumers a component.

It exists because four installed plugins had each independently reimplemented
the same thumbnail:

| plugin | kind | what it built |
| --- | --- | --- |
| `io.github.sirmenef.workspace-overview` | overlay | live capture per window, grid tiles |
| `expose.window-overview` | overlay | live capture per window |
| `pablopunk.workspace-overview` | panel | wallpaper + tiles, hardcoded 16:9 |
| `io.github.anooplamba.workspace-preview` | bar-widget | wallpaper + tiles, per-monitor aspect |

None of them shared anything, and Omarchy has no cross-plugin preview API. A
bar widget cannot reach into another plugin's directory either —
`PluginRegistry.isSafeEntryPoint` / `entryPointUrl` sandbox entry points to
their own `sourceDir`. A service is the supported way across that boundary.

## The one hard rule: three layers, and why

```
lib/Geometry.js         pure JS        no QML, no singletons, no compositor
WorkspaceThumbnail.qml  QtQuick only   layout; takes its window tile injected
WindowTile.qml          Wayland        the ScreencopyView, and nothing else
Service.qml             Hyprland       singletons, wallpaper, wiring
```

This is not aesthetic. **Each boundary buys a test lane**, and breaking one
silently deletes that lane's coverage:

- `Geometry.js` stays pure → `tests/geometry.test.mjs` loads the *real file*
  into node and covers the maths in depth, in ~50ms, with no display.
- `WorkspaceThumbnail.qml` imports only QtQuick and takes `tileComponent` as a
  property → `tests/tst_thumbnail.qml` runs it headless under `qmltestrunner`
  with a stub `Rectangle` tile, and asserts on real laid-out geometry.
- `WindowTile.qml` isolates the one type that genuinely needs a compositor.

`tests/structure.test.sh` enforces all three mechanically. If you find yourself
adding `import Quickshell` to `WorkspaceThumbnail.qml`, the thing you want
belongs in `WindowTile.qml` or `Service.qml` instead.

## Coordinate spaces

Three, and conflating them is the bug you will actually write:

| space | meaning |
| --- | --- |
| device | `monitor.width/height` as the compositor reports them |
| logical | `device / scale`, minus reserved strips (the bar) |
| frame | thumbnail pixels; `logical * (frameWidth / logicalWidth)` |

Hyprland reports **window** geometry in *global logical* coordinates, so a
window box needs the monitor origin **and** the monitor's reserved top-left
subtracted before it means anything inside a thumbnail. `windowBox()` does
both; `tests/geometry.test.mjs` pins it with this machine's real layout
(`HDMI-A-1` at x=-1920, `DP-2` at x=3440, two monitors at y=-20).

Reserved space lives on `monitor.lastIpcObject.reserved` as
`[left, top, right, bottom]` — it is not a typed property, and it is absent
until the monitor has been seen once.

Windows are **not** clamped to the monitor. One straddling two outputs should
visibly hang off the edge; the thumbnail clips it. Clamping would silently
misreport the layout.

## The empty-workspace placeholder is not a special case

It falls out of the design: `buildFrame()` returns `windows: []`, the Repeater
renders nothing, and the wallpaper is left showing at the monitor's aspect.
There is no branch to maintain. Two distinct "empty" cases both work:

- **an empty workspace that exists** — has its own `monitor`, so the aspect is exact.
- **a workspace Hyprland has not created** — has no monitor at all, which is why
  `frameFor(id, monitorName)` takes the caller's connector hint. `resolveMonitor`
  falls back: workspace's own monitor → caller's hint → focused monitor.

`buildFrame()` never returns null. Worst case (no compositor state whatsoever)
is a 16:9 wallpaper-only frame, so consumers never need a null branch.

## Consuming the service

```qml
readonly property var thumbs: bar && bar.shell && typeof bar.shell.serviceFor === "function"
  ? bar.shell.serviceFor("mlclifton.workspace-thumbnails") : null

Loader {
  sourceComponent: thumbs ? thumbs.thumbnailComponent : null
  onLoaded: {
    item.frame = Qt.binding(function() { return thumbs.frameFor(wsId, monitorName) })
    item.wallpaper = Qt.binding(function() { return thumbs.wallpaper })
  }
}
```

Surface:

| member | notes |
| --- | --- |
| `frameFor(id, monitorName)` | frame descriptor; `monitorName` shapes uncreated workspaces |
| `aspectForMonitor(name)` | just the aspect, for sizing a popup before building a frame |
| `wallpaper` | live URL, tracks theme switches |
| `thumbnailComponent` | `WorkspaceThumbnail` with `WindowTile` already injected |
| `revision` | change counter; see below |

`thumbnailComponent` exists so consumers never hardcode a path into this
plugin's directory, and so `WindowTile` gets wired in without
`WorkspaceThumbnail.qml` importing Wayland.

### Why `revision` exists

`frameFor()` returns a plain JS object. QML cannot see through that to know when
to re-evaluate, so `frameFor()` reads `root.revision` on entry, and the
`Connections` blocks bump it on Hyprland events. Any binding that calls
`frameFor()` therefore captures `revision` as a dependency and re-runs.

**Anything new that a frame depends on must also bump `revision`, or thumbnails
silently stop updating.** This is the same trick as the `sink` loop in
`jordan.workspaces`' `items` property.

## Service loading mechanics

- `manifest.kinds` must contain `"service"` with `entryPoints.service`.
- `shell.qml` (`ensureService`, ~line 285) loads it generically and injects
  `shell`, `manifest`, `pluginRegistry`, `barWidgetRegistry` if those properties
  exist. This file declares `shell` and `manifest`.
- **A third-party service is only enabled by an entry in `shell.json`'s
  top-level `plugins[]` array.** Being installed is not enough; it will silently
  never load.
- `shell.serviceFor(id)` returns a **single global instance**, not one per
  monitor. That is fine for popups because `PopupCard` anchors off
  `anchorItem.QsWindow.window`, so the popup still lands on the anchor's screen.

## Gotchas that cost time

1. **Hidden workspaces ARE capturable.** `ScreencopyView` on a toplevel sitting
   on a non-visible workspace returns real content — verified on this machine
   against a workspace on another monitor. Do not add a fallback path for
   "unfocused workspace"; it was assumed once and it is simply wrong.
   (`sirmenef`'s overview carries the same note.)
2. **The wallpaper is global, not per-monitor.**
   `~/.local/state/omarchy/current/background` is one symlink, and
   `Background.qml` paints the same path across a `Variants` over all screens.
   Read it from the `omarchy.background` service rather than polling the
   symlink; the `readlink` `Process` here is only a fallback for when that
   service has not resolved a path yet.
3. **Hyprland 0.56.2 uses the Lua dispatcher API.** Legacy
   `hyprctl dispatch workspace 3` is a Lua syntax error now. The working form is
   `hyprctl dispatch 'hl.dsp.focus({ workspace = "3" })'`. This matters for any
   consumer doing click-to-focus, and it is why `omarchy-workspace-preview`
   shells out the way it does.
4. **`qmllint` needs a `qs` shim.** Quickshell exposes the shell root as the
   `qs` module, so linting anything importing `qs.Commons` needs a directory
   containing a `qs` symlink on the import path. `tests/run.sh` builds one in a
   tempdir.
5. **`Style.space()` is theme-scaled**, not pixels. Never hardcode.

## Testing

```bash
tests/run.sh              # everything, ~2s, no compositor needed
tests/run.sh unit         # node only — the fast loop while editing Geometry.js
tests/run.sh structure    # layering invariants
tests/run.sh lint         # qmllint
tests/run.sh qml          # qmltestrunner, headless
```

Four lanes, cheapest first: `structure`, `unit` (node, 29 assertions),
`lint`, `qml` (qmltestrunner, 20 assertions).

`tests/load-qml-js.mjs` is the bridge that lets node load a QML JS resource: it
strips `.pragma` / `.import` directives and compiles the rest with
`new Function`, returning the declarations. It deliberately does **not** use
`node:vm` — a vm context is a separate realm, so its arrays and objects fail
`assert.deepStrictEqual` against structurally identical host values.

`tst_geometry.qml` re-runs a coarse subset of the node assertions through QML's
own JS engine. That is not redundant: it proves the file still parses as a QML
JS resource and that the two interpreters agree. Keep depth in the node suite,
which is far faster.

### Mutation-test anything you add here

The suite was checked by breaking the code on purpose and confirming failures.
That found a real hole: the original fixtures only reserved the *top* edge, so
deleting the left/right reserved subtraction passed 25/25. Omarchy supports
left- and right-positioned bars, so that path is real. Fixtures now cover all
four edges.

Three mutations currently caught, worth re-running after edits — each must turn
the node suite red:

```
width - reserved[LEFT] - reserved[RIGHT]  ->  width          # 2 failures
- originX - reserved[RESERVED_LEFT]       ->  - originX      # 1 failure
if (isRotated(monitor))                   ->  if (false)     # 1 failure
```

### Verifying visually

Automated tests cannot cover screencopy or popup placement. To check by hand,
drive the pointer and screenshot — note the table argument, `cursor.move(x, y)`
is rejected:

```bash
hyprctl dispatch 'hl.dsp.cursor.move({ x = 600, y = 400 })'   # move away first
hyprctl dispatch 'hl.dsp.cursor.move({ x = 91, y = 12 })'     # onto the pill
sleep 1.5
grim -g "0,0 560x230" /tmp/preview.png
```

A single `cursor.move` onto the target is enough, but moving away first makes
the hover transition unambiguous.

Screenshot **every** monitor: each runs its own bar and they legitimately
differ. This machine is `HDMI-A-1` at x=-1920, `DP-1` at x=0 (ultrawide
3440x1440, primary), `DP-2` at x=3440, the latter two at y=-20, all reserving
24px at the top.

## Install for development

There is no `omarchy plugin` dev-link subcommand, so copy and enable:

```bash
DEST=~/.config/omarchy/plugins/mlclifton.workspace-thumbnails
mkdir -p "$DEST" && cp -r manifest.json *.qml lib LICENSE "$DEST/"
# then add {"id": "mlclifton.workspace-thumbnails"} to shell.json's plugins[]
omarchy restart shell
```

Confirm it actually loaded — a service that fails to load is silent:

```bash
omarchy plugin list | grep thumbnails      # expect: enabled third-party service
journalctl --user --since "2 minutes ago" | grep -i "service plugin load failed"
```

## History

- Built 2026-09-08 after auditing the four duplicate implementations above.
- First consumer is the `jordan.workspaces` fork at `~/Projects/mybarwidget`;
  see its `implementation.md` for the hover wiring.
