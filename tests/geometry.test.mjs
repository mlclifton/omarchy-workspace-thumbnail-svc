// Unit tests for lib/Geometry.js, run under `node --test`.
//
// These exercise the real module (see load-qml-js.mjs), using plain objects
// shaped like the Hyprland types Quickshell exposes. The fixtures below mirror
// this machine's actual layout because the three-monitor, mixed-origin case is
// where the coordinate maths earns its keep.

import test from "node:test"
import assert from "node:assert/strict"
import { loadQmlJs } from "./load-qml-js.mjs"

const G = loadQmlJs("lib/Geometry.js")

// A 1080p monitor with a 40px bar reserved at the top.
function monitor(overrides = {}) {
  return {
    name: "DP-1",
    x: 0,
    y: 0,
    width: 1920,
    height: 1080,
    scale: 1,
    transform: 0,
    lastIpcObject: { reserved: [0, 40, 0, 0] },
    ...overrides
  }
}

function toplevel(at, size, extra = {}) {
  return {
    title: "window",
    lastIpcObject: { at, size, ...extra },
    ...extra
  }
}

function workspace(id, mon, toplevels = []) {
  return { id, monitor: mon, toplevels: { values: toplevels } }
}

test("logical size subtracts reserved strips", () => {
  assert.equal(G.logicalWidth(monitor()), 1920)
  assert.equal(G.logicalHeight(monitor()), 1040)
})

test("logical size divides by monitor scale before subtracting reserved", () => {
  // A 3840x2160 panel at 2x is a 1920x1080 logical desktop; the 40px bar is
  // reserved in logical pixels, so it comes off after the divide.
  const m = monitor({ width: 3840, height: 2160, scale: 2 })
  assert.equal(G.logicalWidth(m), 1920)
  assert.equal(G.logicalHeight(m), 1040)
})

test("aspect reflects the usable area, not the panel", () => {
  assert.equal(G.aspectOf(monitor()), 1920 / 1040)
})

test("a side bar reserves horizontal space", () => {
  // Omarchy's bar can sit left or right, which reserves columns rather than
  // rows. Without this case a fixture that only reserves the top lets the
  // left/right subtraction rot unnoticed.
  const left = monitor({ lastIpcObject: { reserved: [60, 0, 0, 0] } })
  assert.equal(G.logicalWidth(left), 1860)
  assert.equal(G.logicalHeight(left), 1080)
  assert.equal(G.aspectOf(left), 1860 / 1080)

  const right = monitor({ lastIpcObject: { reserved: [0, 0, 60, 0] } })
  assert.equal(G.logicalWidth(right), 1860)

  const both = monitor({ lastIpcObject: { reserved: [60, 0, 40, 0] } })
  assert.equal(G.logicalWidth(both), 1820)
})

test("a bottom bar reserves from the height", () => {
  const bottom = monitor({ lastIpcObject: { reserved: [0, 0, 0, 40] } })
  assert.equal(G.logicalHeight(bottom), 1040)
  assert.equal(G.logicalWidth(bottom), 1920)
})

test("all four reserved edges apply together", () => {
  const m = monitor({ lastIpcObject: { reserved: [10, 20, 30, 40] } })
  assert.equal(G.logicalWidth(m), 1920 - 10 - 30)
  assert.equal(G.logicalHeight(m), 1080 - 20 - 40)
})

test("aspect swaps for 90 and 270 degree transforms", () => {
  const portrait = G.aspectOf(monitor({ transform: 1 }))
  assert.equal(portrait, 1040 / 1920)
  assert.ok(portrait < 1, "rotated monitor should be taller than wide")
  // 4 is a flipped-but-not-rotated transform and must not swap.
  assert.equal(G.aspectOf(monitor({ transform: 4 })), 1920 / 1040)
})

test("missing or malformed monitors fall back to 16:9 rather than dividing by zero", () => {
  assert.equal(G.aspectOf(null), 16 / 9)
  // A monitor reporting a zero panel size falls back to 1920x1080 device, but
  // its reserved strips still apply on top of that fallback.
  assert.equal(G.aspectOf(monitor({ width: 0, height: 0 })), 1920 / 1040)
  assert.equal(G.aspectOf(monitor({ width: 0, height: 0, lastIpcObject: null })), 16 / 9)
  assert.ok(Number.isFinite(G.aspectOf(monitor({ scale: 0 }))))
  assert.ok(Number.isFinite(G.aspectOf(monitor({ lastIpcObject: null }))))
})

test("reserved strips that exceed the panel cannot produce a non-positive size", () => {
  const m = monitor({ lastIpcObject: { reserved: [0, 4000, 0, 4000] } })
  assert.ok(G.logicalHeight(m) >= 1)
  assert.ok(Number.isFinite(G.aspectOf(m)))
})

test("fitBox honours whichever bound is tighter", () => {
  // Width-bound: 300 wide at 16:9 needs 168.75 high, which fits in 400.
  assert.deepEqual(G.fitBox(16 / 9, 300, 400), { width: 300, height: 300 / (16 / 9) })
  // Height-bound: 100 high at 16:9 needs 177.8 wide, less than the 300 offered.
  const bounded = G.fitBox(16 / 9, 300, 100)
  assert.equal(bounded.height, 100)
  assert.ok(Math.abs(bounded.width - 100 * (16 / 9)) < 1e-9)
})

test("fitBox treats a non-positive bound as unconstrained", () => {
  assert.deepEqual(G.fitBox(2, 300, 0), { width: 300, height: 150 })
  assert.deepEqual(G.fitBox(2, 0, 150), { width: 300, height: 150 })
  assert.deepEqual(G.fitBox(2, 0, 0), { width: 0, height: 0 })
})

test("window boxes are relative to the monitor origin and its reserved top-left", () => {
  // HDMI-A-1 on this machine sits at x=-1920. A window at global x=-1820 is
  // 100px into that monitor, and 60px below a 40px bar.
  const m = monitor({ name: "HDMI-A-1", x: -1920, y: 0 })
  const box = G.windowBox(toplevel([-1820, 100], [800, 600]), m)
  assert.equal(box.x, 100)
  assert.equal(box.y, 60)
  assert.equal(box.width, 800)
  assert.equal(box.height, 600)
  assert.equal(box.estimated, false)
})

test("window boxes subtract a left-reserved strip as well as a top one", () => {
  // Same gap as the logical-size case: with a side bar, the window origin is
  // offset horizontally too.
  const m = monitor({ lastIpcObject: { reserved: [60, 40, 0, 0] } })
  const box = G.windowBox(toplevel([60, 40], [800, 600]), m)
  assert.equal(box.x, 0)
  assert.equal(box.y, 0)
})

test("window boxes handle a negative y origin", () => {
  // DP-1 and DP-2 sit at y=-20 here, so the origin subtraction must not assume
  // a non-negative offset.
  const m = monitor({ x: 3440, y: -20, lastIpcObject: { reserved: [0, 0, 0, 0] } })
  const box = G.windowBox(toplevel([3440, -20], [100, 100]), m)
  assert.equal(box.x, 0)
  assert.equal(box.y, 0)
})

test("a window with no IPC geometry yet gets a centred estimate, not a crash", () => {
  const box = G.windowBox({ title: "new" }, monitor())
  assert.equal(box.estimated, true)
  assert.ok(box.width > 0 && box.height > 0)
  // Centred: equal margins either side.
  assert.ok(Math.abs(box.x * 2 + box.width - G.logicalWidth(monitor())) < 1e-9)
})

test("windows straddling a monitor edge are not clamped", () => {
  // Clamping would silently misreport the layout; the thumbnail clips instead.
  const box = G.windowBox(toplevel([-100, 0], [800, 600]), monitor())
  assert.equal(box.x, -100)
})

test("scaleBox maps logical coordinates into frame pixels", () => {
  const scaled = G.scaleBox({ x: 960, y: 520, width: 480, height: 260 }, 1920, 1040, 192, 104)
  assert.equal(scaled.x, 96)
  assert.equal(scaled.y, 52)
  assert.equal(scaled.width, 48)
  assert.equal(scaled.height, 26)
})

test("scaleBox floors tiny tiles so they stay visible", () => {
  const scaled = G.scaleBox({ x: 0, y: 0, width: 0, height: 0 }, 1920, 1040, 192, 104)
  assert.equal(scaled.width, 2)
  assert.equal(scaled.height, 2)
})

test("connectorName rejects anything that is not a plain connector", () => {
  assert.equal(G.connectorName("DP-1"), "DP-1")
  assert.equal(G.connectorName("HDMI-A-1"), "HDMI-A-1")
  assert.equal(G.connectorName(""), "")
  assert.equal(G.connectorName(null), "")
  assert.equal(G.connectorName("../etc/passwd"), "")
  assert.equal(G.connectorName("DP-1; rm -rf /"), "")
  assert.equal(G.connectorName("x".repeat(40)), "")
})

test("resolveMonitor prefers the workspace's own monitor", () => {
  const own = monitor({ name: "DP-2" })
  const other = monitor({ name: "DP-1" })
  const ws = workspace(3, own)
  assert.equal(G.resolveMonitor(ws, [other], "DP-1", other), own)
})

test("resolveMonitor falls back to the caller's monitor hint for a workspace that does not exist", () => {
  // This is the empty-workspace case: Hyprland has no object for workspace 7,
  // but the bar knows which monitor's group it is drawn in.
  const hdmi = monitor({ name: "HDMI-A-1", x: -1920 })
  const dp = monitor({ name: "DP-1" })
  assert.equal(G.resolveMonitor(null, [dp, hdmi], "HDMI-A-1", dp), hdmi)
})

test("resolveMonitor falls back to the focused monitor when nothing else matches", () => {
  const focused = monitor({ name: "DP-1" })
  assert.equal(G.resolveMonitor(null, [], "", focused), focused)
  assert.equal(G.resolveMonitor(null, [], "nope", focused), focused)
  assert.equal(G.resolveMonitor(null, [], "", null), null)
})

test("buildFrame describes an occupied workspace", () => {
  const m = monitor()
  const ws = workspace(1, m, [
    toplevel([0, 40], [960, 1040]),
    toplevel([960, 40], [960, 1040])
  ])
  const frame = G.buildFrame({ workspaceId: 1, workspaces: [ws], monitors: [m] })

  assert.equal(frame.exists, true)
  assert.equal(frame.occupied, true)
  assert.equal(frame.monitorName, "DP-1")
  assert.equal(frame.windows.length, 2)
  assert.equal(frame.windows[0].box.x, 0)
  assert.equal(frame.windows[0].box.y, 0)
  assert.equal(frame.windows[1].box.x, 960)
  assert.equal(frame.aspect, 1920 / 1040)
})

test("buildFrame yields a wallpaper-only placeholder for an empty workspace", () => {
  const m = monitor()
  const ws = workspace(4, m, [])
  const frame = G.buildFrame({ workspaceId: 4, workspaces: [ws], monitors: [m] })

  assert.equal(frame.exists, true)
  assert.equal(frame.occupied, false)
  assert.deepEqual(frame.windows, [])
  // The placeholder must still be monitor-shaped, which is the whole point.
  assert.equal(frame.aspect, 1920 / 1040)
})

test("buildFrame yields a monitor-shaped placeholder for a workspace Hyprland has not created", () => {
  const hdmi = monitor({ name: "HDMI-A-1", x: -1920, width: 2560, height: 1440 })
  const frame = G.buildFrame({
    workspaceId: 9,
    workspaces: [],
    monitors: [hdmi],
    monitorName: "HDMI-A-1"
  })

  assert.equal(frame.exists, false)
  assert.equal(frame.occupied, false)
  assert.equal(frame.monitorName, "HDMI-A-1")
  assert.equal(frame.aspect, 2560 / 1400)
})

test("buildFrame never returns null, even with no compositor state at all", () => {
  const frame = G.buildFrame({})
  assert.equal(frame.exists, false)
  assert.equal(frame.occupied, false)
  assert.equal(frame.aspect, 16 / 9)
  assert.deepEqual(frame.windows, [])
})

test("buildFrame caps the window list", () => {
  const m = monitor()
  const many = Array.from({ length: 200 }, () => toplevel([0, 40], [100, 100]))
  const frame = G.buildFrame({ workspaceId: 1, workspaces: [workspace(1, m, many)], monitors: [m] })
  assert.equal(frame.windows.length, 32)

  const capped = G.buildFrame({
    workspaceId: 1,
    workspaces: [workspace(1, m, many)],
    monitors: [m],
    maxWindows: 4
  })
  assert.equal(capped.windows.length, 4)
})

test("buildFrame skips holes in the toplevel list", () => {
  const m = monitor()
  const ws = workspace(1, m, [toplevel([0, 40], [100, 100]), null, toplevel([0, 40], [100, 100])])
  const frame = G.buildFrame({ workspaceId: 1, workspaces: [ws], monitors: [m] })
  assert.equal(frame.windows.length, 2)
})

test("buildFrame marks floating windows so the renderer can stack them last", () => {
  const m = monitor()
  const ws = workspace(1, m, [
    toplevel([0, 40], [100, 100]),
    toplevel([0, 40], [100, 100], { floating: true })
  ])
  const frame = G.buildFrame({ workspaceId: 1, workspaces: [ws], monitors: [m] })
  assert.equal(frame.windows[0].floating, false)
  assert.equal(frame.windows[1].floating, true)
})
