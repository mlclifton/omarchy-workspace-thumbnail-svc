import QtQuick
import Quickshell.Wayland

// One window inside a thumbnail: a live screencopy of the toplevel, with a
// title-and-frame fallback for anything that cannot be captured.
//
// This is the only file in the plugin that touches Wayland, which is why it is
// separate from WorkspaceThumbnail.qml. Position and size come from the parent
// Loader, so this file only decides what fills that box.
//
// Hidden workspaces ARE capturable: Hyprland services screencopy for toplevels
// on non-visible workspaces, so a thumbnail of a workspace you are not looking
// at still shows real window content. Do not "optimise" this into a fallback
// path for unfocused workspaces - that was tried, and it is simply wrong.

Item {
  id: root

  // A frame window entry from Geometry.buildFrame().
  property var entry: null
  property var toplevel: entry ? entry.toplevel : null
  // Live capture costs a compositor readback per frame. Consumers that show a
  // thumbnail transiently (a hover popup) should leave this false; a persistent
  // overview may want it true.
  property bool live: false
  property color tileColor: "#22000000"
  property color frameColor: "#33ffffff"
  property color textColor: "#ffffff"

  readonly property var captureSource: root.toplevel && root.toplevel.wayland ? root.toplevel.wayland : null
  readonly property bool hasCapture: view.hasContent

  function recapture() {
    if (view.captureSource && view.captureFrame) view.captureFrame()
  }

  Rectangle {
    anchors.fill: parent
    color: root.tileColor
    border.color: root.frameColor
    border.width: 1
    clip: true

    ScreencopyView {
      id: view
      anchors.fill: parent
      captureSource: root.captureSource
      live: root.live
    }

    // Shown only when there is nothing to show: an XWayland surface without a
    // wayland handle, or a capture that has not arrived yet.
    Text {
      anchors.centerIn: parent
      width: Math.max(1, parent.width - 8)
      visible: !view.hasContent
      text: root.entry ? root.entry.title : ""
      textFormat: Text.PlainText
      color: root.textColor
      opacity: 0.7
      elide: Text.ElideRight
      maximumLineCount: 2
      wrapMode: Text.WordWrap
      horizontalAlignment: Text.AlignHCenter
      font.pixelSize: Math.max(7, Math.min(11, parent.height / 6))
    }
  }
}
