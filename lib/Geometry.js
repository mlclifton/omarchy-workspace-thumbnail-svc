.pragma library

// Pure geometry for workspace thumbnails.
//
// Every function here takes plain objects and returns plain objects. Nothing
// touches a QML singleton, the compositor, or the filesystem, which is what
// makes tests/geometry.test.mjs able to load this file into node and assert on
// it directly. Keep it that way: anything that needs Hyprland belongs in
// Service.qml, anything that needs a scene graph belongs in the QML components.
//
// Coordinate spaces, in order:
//   device   - monitor.width/height, as the compositor reports them
//   logical  - device / scale, minus the reserved strips (bar, etc.)
//   frame    - the thumbnail's own pixels; logical * (frameWidth / logicalWidth)
//
// Window geometry from Hyprland arrives in *global logical* coordinates, so it
// is offset by the monitor origin and the monitor's reserved top-left before it
// means anything inside a thumbnail.

var FALLBACK_ASPECT = 16 / 9
var FALLBACK_WIDTH = 1920
var FALLBACK_HEIGHT = 1080

// Hyprland's reserved array is [left, top, right, bottom].
var RESERVED_LEFT = 0
var RESERVED_TOP = 1
var RESERVED_RIGHT = 2
var RESERVED_BOTTOM = 3

function finiteOr(value, fallback) {
  var n = Number(value)
  return isFinite(n) ? n : fallback
}

function positiveOr(value, fallback) {
  var n = Number(value)
  return isFinite(n) && n > 0 ? n : fallback
}

function monitorScale(monitor) {
  return monitor ? positiveOr(monitor.scale, 1) : 1
}

// Hyprland exposes reserved space on the raw IPC object rather than as a typed
// property, and it is absent until the monitor has been seen at least once.
function reservedOf(monitor) {
  var raw = monitor && monitor.lastIpcObject ? monitor.lastIpcObject.reserved : null
  if (!raw || raw.length < 4) return [0, 0, 0, 0]
  return [
    finiteOr(raw[RESERVED_LEFT], 0),
    finiteOr(raw[RESERVED_TOP], 0),
    finiteOr(raw[RESERVED_RIGHT], 0),
    finiteOr(raw[RESERVED_BOTTOM], 0)
  ]
}

function logicalWidth(monitor) {
  if (!monitor) return FALLBACK_WIDTH
  var reserved = reservedOf(monitor)
  var width = positiveOr(monitor.width, FALLBACK_WIDTH) / monitorScale(monitor)
  return Math.max(1, width - reserved[RESERVED_LEFT] - reserved[RESERVED_RIGHT])
}

function logicalHeight(monitor) {
  if (!monitor) return FALLBACK_HEIGHT
  var reserved = reservedOf(monitor)
  var height = positiveOr(monitor.height, FALLBACK_HEIGHT) / monitorScale(monitor)
  return Math.max(1, height - reserved[RESERVED_TOP] - reserved[RESERVED_BOTTOM])
}

// A monitor rotated 90/270 degrees reports device dimensions in its unrotated
// orientation, so the transform decides which way round the aspect goes.
function isRotated(monitor) {
  if (!monitor) return false
  var transform = finiteOr(monitor.transform, 0)
  return transform === 1 || transform === 3 || transform === 5 || transform === 7
}

function aspectOf(monitor) {
  if (!monitor) return FALLBACK_ASPECT
  var width = logicalWidth(monitor)
  var height = logicalHeight(monitor)
  if (isRotated(monitor)) {
    var swap = width
    width = height
    height = swap
  }
  if (height <= 0) return FALLBACK_ASPECT
  return width / height
}

// Fit an aspect-correct box inside the space a consumer offers. Either bound
// may be non-positive, meaning "unconstrained in this direction".
function fitBox(aspect, maxWidth, maxHeight) {
  var ratio = positiveOr(aspect, FALLBACK_ASPECT)
  var boundW = Number(maxWidth)
  var boundH = Number(maxHeight)
  var hasW = isFinite(boundW) && boundW > 0
  var hasH = isFinite(boundH) && boundH > 0

  if (!hasW && !hasH) return { width: 0, height: 0 }
  if (!hasH) return { width: boundW, height: boundW / ratio }
  if (!hasW) return { width: boundH * ratio, height: boundH }

  var width = Math.min(boundW, boundH * ratio)
  return { width: width, height: width / ratio }
}

// Translate one window from Hyprland's global logical coordinates into the
// monitor-local logical box the thumbnail represents. Windows are not clamped
// to the monitor: a window straddling two outputs should visibly hang off the
// edge, and the thumbnail clips it.
function windowBox(toplevel, monitor) {
  var ipc = toplevel && toplevel.lastIpcObject ? toplevel.lastIpcObject : null
  var width = logicalWidth(monitor)
  var height = logicalHeight(monitor)

  // No IPC geometry yet (a window mapped this frame). A centred 80% box reads
  // as "a window is here" without pretending to know where.
  if (!ipc || !ipc.at || !ipc.size || ipc.at.length < 2 || ipc.size.length < 2) {
    return {
      x: width * 0.1,
      y: height * 0.1,
      width: width * 0.8,
      height: height * 0.8,
      estimated: true
    }
  }

  var reserved = reservedOf(monitor)
  var originX = monitor ? finiteOr(monitor.x, 0) : 0
  var originY = monitor ? finiteOr(monitor.y, 0) : 0

  return {
    x: finiteOr(ipc.at[0], 0) - originX - reserved[RESERVED_LEFT],
    y: finiteOr(ipc.at[1], 0) - originY - reserved[RESERVED_TOP],
    width: Math.max(1, positiveOr(ipc.size[0], 1)),
    height: Math.max(1, positiveOr(ipc.size[1], 1)),
    estimated: false
  }
}

// Scale a logical box into frame pixels. Tiles get a 2px floor so a minimised
// or zero-size window still occupies something hit-testable.
function scaleBox(box, logicalW, logicalH, frameW, frameH) {
  var sx = positiveOr(logicalW, FALLBACK_WIDTH) > 0 ? frameW / positiveOr(logicalW, FALLBACK_WIDTH) : 1
  var sy = positiveOr(logicalH, FALLBACK_HEIGHT) > 0 ? frameH / positiveOr(logicalH, FALLBACK_HEIGHT) : 1
  return {
    x: finiteOr(box.x, 0) * sx,
    y: finiteOr(box.y, 0) * sy,
    width: Math.max(2, finiteOr(box.width, 0) * sx),
    height: Math.max(2, finiteOr(box.height, 0) * sy)
  }
}

function connectorName(value) {
  var name = String(value === undefined || value === null ? "" : value)
  if (!/^[A-Za-z0-9][A-Za-z0-9._:-]{0,31}$/.test(name)) return ""
  return name
}

function findWorkspace(workspaces, id) {
  var target = Number(id)
  if (!workspaces || !isFinite(target)) return null
  for (var i = 0; i < workspaces.length; i++) {
    if (workspaces[i] && Number(workspaces[i].id) === target) return workspaces[i]
  }
  return null
}

function findMonitorByName(monitors, name) {
  var wanted = connectorName(name)
  if (!monitors || wanted === "") return null
  for (var i = 0; i < monitors.length; i++) {
    if (monitors[i] && connectorName(monitors[i].name) === wanted) return monitors[i]
  }
  return null
}

// The monitor a thumbnail should be shaped like, most authoritative first:
// the workspace's own monitor, the name the caller asked about, then the
// focused monitor. An empty workspace that Hyprland has not created yet has no
// monitor of its own, which is exactly why the caller's hint matters.
function resolveMonitor(workspace, monitors, monitorName, focusedMonitor) {
  if (workspace && workspace.monitor) return workspace.monitor
  var named = findMonitorByName(monitors, monitorName)
  if (named) return named
  return focusedMonitor || null
}

function windowsOf(workspace) {
  if (!workspace || !workspace.toplevels || !workspace.toplevels.values) return []
  return workspace.toplevels.values
}

// The descriptor a thumbnail renders. Always returns a usable frame: an
// unknown workspace on an unknown monitor still yields a 16:9 wallpaper-only
// placeholder rather than a null the consumer has to special-case.
function buildFrame(options) {
  var opts = options || {}
  var workspace = findWorkspace(opts.workspaces, opts.workspaceId)
  var monitor = resolveMonitor(workspace, opts.monitors, opts.monitorName, opts.focusedMonitor)
  var toplevels = windowsOf(workspace)
  var logicalW = logicalWidth(monitor)
  var logicalH = logicalHeight(monitor)

  var windows = []
  var cap = Math.min(toplevels.length, positiveOr(opts.maxWindows, 32))
  for (var i = 0; i < cap; i++) {
    var toplevel = toplevels[i]
    if (!toplevel) continue
    windows.push({
      toplevel: toplevel,
      box: windowBox(toplevel, monitor),
      title: toplevel.title ? String(toplevel.title) : "",
      floating: !!(toplevel.lastIpcObject && toplevel.lastIpcObject.floating)
    })
  }

  return {
    workspaceId: Number(opts.workspaceId),
    exists: workspace !== null,
    monitorName: monitor ? connectorName(monitor.name) : "",
    monitor: monitor,
    aspect: aspectOf(monitor),
    logicalWidth: logicalW,
    logicalHeight: logicalH,
    occupied: windows.length > 0,
    windows: windows
  }
}
