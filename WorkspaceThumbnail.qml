pragma ComponentBehavior: Bound

import QtQuick
import "lib/Geometry.js" as Geometry

// One monitor-shaped thumbnail of a single workspace.
//
// Deliberately imports nothing but QtQuick. Everything compositor-shaped
// arrives as plain data in `frame` (built by Service.buildFrame), and the one
// piece that genuinely needs Wayland - the per-window screencopy tile - is
// injected as `tileComponent`. That is what lets tests/tst_thumbnail.qml load
// this file headless and assert on the layout with a stub tile.
//
// Sizing: the caller gives a bounding box via width/height, and the content
// letterboxes itself to the monitor's aspect inside it. An empty workspace
// renders the wallpaper alone, which is the placeholder by construction rather
// than by special case.

Item {
  id: root

  // Frame descriptor from Service.buildFrame(). Never null in normal use.
  property var frame: null
  // Wallpaper image URL. Empty renders the flat background colour instead.
  property url wallpaper: ""
  // Component instantiated per window. Given `modelData` (a frame window entry)
  // and sized/positioned by this file. Service supplies the real WindowTile.
  property Component tileComponent: null
  // Painted behind the wallpaper, and visible if the wallpaper fails to load.
  property color backgroundColor: "#1a1a1a"
  property color borderColor: "#00000000"
  property real borderWidth: 0
  property real radius: 0

  readonly property real frameAspect: root.frame ? Number(root.frame.aspect) : 16 / 9
  readonly property var fitted: Geometry.fitBox(root.frameAspect, root.width, root.height)
  readonly property real contentWidth: root.fitted.width
  readonly property real contentHeight: root.fitted.height
  readonly property var windowList: root.frame && root.frame.windows ? root.frame.windows : []
  readonly property bool occupied: root.windowList.length > 0

  implicitWidth: 320
  implicitHeight: 320 / root.frameAspect

  Item {
    id: content

    width: root.contentWidth
    height: root.contentHeight
    anchors.centerIn: parent

    Rectangle {
      id: surface
      anchors.fill: parent
      color: root.backgroundColor
      border.color: root.borderColor
      border.width: root.borderWidth
      radius: root.radius
      clip: true

      Image {
        anchors.fill: parent
        source: root.wallpaper
        // The thumbnail is already the monitor's aspect, so a crop is a no-op
        // for the common case and only bites when the wallpaper itself differs.
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        cache: true
        visible: root.wallpaper.toString() !== ""
      }

      Item {
        id: windowLayer
        anchors.fill: parent

        Repeater {
          id: tiles
          model: root.windowList

          delegate: Loader {
            id: tileLoader

            required property var modelData
            required property int index

            readonly property var scaled: Geometry.scaleBox(
              tileLoader.modelData.box,
              root.frame ? root.frame.logicalWidth : 1920,
              root.frame ? root.frame.logicalHeight : 1080,
              windowLayer.width,
              windowLayer.height)

            x: tileLoader.scaled.x
            y: tileLoader.scaled.y
            width: tileLoader.scaled.width
            height: tileLoader.scaled.height
            // Hyprland hands back toplevels in stacking order; floating windows
            // belong above tiled ones regardless of where they sit in the list.
            z: tileLoader.modelData.floating ? 1000 + tileLoader.index : tileLoader.index

            sourceComponent: root.tileComponent
            onLoaded: {
              if (!item) return
              if ("entry" in item) item.entry = tileLoader.modelData
              if ("toplevel" in item) item.toplevel = tileLoader.modelData.toplevel
            }
          }
        }
      }
    }
  }
}
