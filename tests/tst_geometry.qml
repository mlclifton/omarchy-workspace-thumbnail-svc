import QtQuick
import QtTest
import "../lib/Geometry.js" as Geometry

// Runs the geometry module through QML's own JavaScript engine.
//
// tests/geometry.test.mjs already covers the maths in depth under node. This
// file exists because node and QML's engine are not the same interpreter: it
// proves the file actually parses as a QML JS resource (`.pragma library` and
// all), that it is importable the way the components import it, and that the
// results agree with the node suite. Keep these assertions coarse - depth
// belongs in the node tests, which are far faster to run.

TestCase {
  id: suite
  name: "Geometry"

  function monitor() {
    return {
      name: "DP-1",
      x: 0,
      y: 0,
      width: 1920,
      height: 1080,
      scale: 1,
      transform: 0,
      lastIpcObject: { reserved: [0, 40, 0, 0] }
    }
  }

  function test_module_loads_in_qml_engine() {
    verify(typeof Geometry.buildFrame === "function")
    verify(typeof Geometry.aspectOf === "function")
    verify(typeof Geometry.fitBox === "function")
  }

  function test_logical_size_matches_node_suite() {
    compare(Geometry.logicalWidth(suite.monitor()), 1920)
    compare(Geometry.logicalHeight(suite.monitor()), 1040)
    compare(Geometry.aspectOf(suite.monitor()), 1920 / 1040)
  }

  function test_fit_box_letterboxes() {
    var box = Geometry.fitBox(16 / 9, 300, 100)
    compare(box.height, 100)
    verify(Math.abs(box.width - 100 * (16 / 9)) < 1e-9)
  }

  function test_window_box_is_monitor_local() {
    var mon = suite.monitor()
    mon.x = -1920
    var box = Geometry.windowBox({ lastIpcObject: { at: [-1820, 100], size: [800, 600] } }, mon)
    compare(box.x, 100)
    compare(box.y, 60)
  }

  function test_empty_workspace_frame_is_monitor_shaped() {
    var mon = suite.monitor()
    var frame = Geometry.buildFrame({
      workspaceId: 4,
      workspaces: [{ id: 4, monitor: mon, toplevels: { values: [] } }],
      monitors: [mon]
    })
    compare(frame.exists, true)
    compare(frame.occupied, false)
    compare(frame.windows.length, 0)
    compare(frame.aspect, 1920 / 1040)
  }

  function test_uncreated_workspace_uses_monitor_hint() {
    var mon = suite.monitor()
    mon.name = "HDMI-A-1"
    var frame = Geometry.buildFrame({
      workspaceId: 9,
      workspaces: [],
      monitors: [mon],
      monitorName: "HDMI-A-1"
    })
    compare(frame.exists, false)
    compare(frame.monitorName, "HDMI-A-1")
    compare(frame.aspect, 1920 / 1040)
  }

  function test_build_frame_survives_empty_input() {
    var frame = Geometry.buildFrame({})
    compare(frame.exists, false)
    compare(frame.aspect, 16 / 9)
    compare(frame.windows.length, 0)
  }
}
