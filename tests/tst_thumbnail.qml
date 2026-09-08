import QtQuick
import QtTest

// Layout tests for WorkspaceThumbnail.qml, headless.
//
// This works only because WorkspaceThumbnail.qml imports nothing but QtQuick
// and takes its window tile as an injected Component. A stub tile stands in for
// WindowTile here, so no Wayland connection and no compositor is needed. If a
// change to WorkspaceThumbnail.qml ever makes this file fail to load, the cause
// is almost certainly a new Quickshell import that belongs in WindowTile.qml or
// Service.qml instead.

TestCase {
  id: suite
  name: "WorkspaceThumbnail"
  when: windowShown

  Component {
    id: stubTile
    Rectangle {
      property var entry: null
      property var toplevel: null
      color: "red"
    }
  }

  Component {
    id: thumbnailComponent
    Loader {
      source: Qt.resolvedUrl("../WorkspaceThumbnail.qml")
    }
  }

  function frame(aspectW, aspectH, windows) {
    return {
      workspaceId: 1,
      exists: true,
      monitorName: "DP-1",
      monitor: null,
      aspect: aspectW / aspectH,
      logicalWidth: aspectW,
      logicalHeight: aspectH,
      occupied: windows.length > 0,
      windows: windows
    }
  }

  function windowEntry(x, y, w, h, floating) {
    return {
      toplevel: null,
      box: { x: x, y: y, width: w, height: h, estimated: false },
      title: "stub",
      floating: floating === true
    }
  }

  // Instantiate the component under test with a stub tile and let bindings settle.
  function makeThumbnail(width, height, frameData) {
    var host = createTemporaryObject(thumbnailComponent, suite)
    verify(host !== null, "thumbnail loader failed to create")
    tryVerify(function() { return host.item !== null }, 2000,
      "WorkspaceThumbnail.qml failed to load: " + host.sourceComponent)
    var item = host.item
    item.tileComponent = stubTile
    item.width = width
    item.height = height
    item.frame = frameData
    waitForItemPolished(item)
    return item
  }

  function test_loads_without_quickshell() {
    var item = makeThumbnail(320, 320, frame(1920, 1080, []))
    verify(item !== null)
  }

  function test_content_letterboxes_to_monitor_aspect_when_width_bound() {
    // A 16:9 workspace in a 320x320 box is width-bound: full width, short.
    var item = makeThumbnail(320, 320, frame(1920, 1080, []))
    compare(item.contentWidth, 320)
    fuzzyCompare(item.contentHeight, 320 / (1920 / 1080), 0.001)
  }

  function test_content_letterboxes_to_monitor_aspect_when_height_bound() {
    // A 9:16 portrait workspace in the same box is height-bound instead.
    var item = makeThumbnail(320, 320, frame(1080, 1920, []))
    compare(item.contentHeight, 320)
    fuzzyCompare(item.contentWidth, 320 * (1080 / 1920), 0.001)
  }

  function test_ultrawide_and_portrait_differ() {
    // The whole point of the service: two monitors of different shapes must not
    // produce identically shaped thumbnails.
    var wide = makeThumbnail(400, 400, frame(3440, 1440, []))
    var tall = makeThumbnail(400, 400, frame(1440, 3440, []))
    verify(wide.contentWidth > wide.contentHeight)
    verify(tall.contentHeight > tall.contentWidth)
  }

  function test_empty_workspace_renders_no_tiles() {
    var item = makeThumbnail(320, 180, frame(1920, 1080, []))
    compare(item.occupied, false)
    // The wallpaper surface still exists at full content size: that is the
    // placeholder.
    verify(item.contentWidth > 0)
    verify(item.contentHeight > 0)
  }

  function test_windows_scale_into_frame_pixels() {
    // A window filling the right half of a 1920x1080 workspace should fill the
    // right half of a 320x180 thumbnail.
    var item = makeThumbnail(320, 180, frame(1920, 1080, [windowEntry(960, 0, 960, 1080)]))
    compare(item.occupied, true)

    var tile = findTile(item, 0)
    verify(tile !== null, "expected one tile")
    fuzzyCompare(tile.x, 160, 0.5)
    fuzzyCompare(tile.y, 0, 0.5)
    fuzzyCompare(tile.width, 160, 0.5)
    fuzzyCompare(tile.height, 180, 0.5)
  }

  function test_floating_windows_stack_above_tiled_ones() {
    var item = makeThumbnail(320, 180, frame(1920, 1080, [
      windowEntry(0, 0, 960, 1080, true),
      windowEntry(960, 0, 960, 1080, false)
    ]))
    var floating = findTile(item, 0)
    var tiled = findTile(item, 1)
    verify(floating !== null && tiled !== null)
    verify(floating.z > tiled.z, "floating window must render above tiled ones")
  }

  function test_zero_size_window_still_gets_a_hittable_tile() {
    var item = makeThumbnail(320, 180, frame(1920, 1080, [windowEntry(0, 0, 0, 0)]))
    var tile = findTile(item, 0)
    verify(tile !== null)
    verify(tile.width >= 2 && tile.height >= 2)
  }

  function test_null_frame_falls_back_to_16_9_rather_than_breaking() {
    var item = makeThumbnail(320, 320, null)
    fuzzyCompare(item.frameAspect, 16 / 9, 0.001)
    fuzzyCompare(item.contentHeight, 320 / (16 / 9), 0.001)
  }

  // Walk down to the Repeater's delegate Loaders. Depth is an implementation
  // detail of WorkspaceThumbnail, so search rather than index blindly.
  function findTile(item, index) {
    var loaders = collectLoaders(item, [])
    return index < loaders.length ? loaders[index] : null
  }

  function collectLoaders(node, out) {
    if (!node || !node.children) return out
    for (var i = 0; i < node.children.length; i++) {
      var child = node.children[i]
      if (child === null) continue
      // Delegate Loaders are the only children carrying a `scaled` property.
      if (child.scaled !== undefined) out.push(child)
      collectLoaders(child, out)
    }
    return out
  }
}
