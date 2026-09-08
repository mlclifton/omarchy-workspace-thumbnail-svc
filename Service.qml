pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "lib/Geometry.js" as Geometry

// Workspace thumbnails, as a shared service.
//
// Loaded by omarchy-shell's generic service loader (shell.qml ensureService)
// because the manifest declares kind "service". Any plugin reaches it with:
//
//   readonly property var thumbs: bar && bar.shell
//     ? bar.shell.serviceFor("mlclifton.workspace-thumbnails") : null
//
// and then renders one with:
//
//   Loader {
//     sourceComponent: thumbs ? thumbs.thumbnailComponent : null
//     onLoaded: {
//       item.frame = Qt.binding(function() { return thumbs.frameFor(wsId, monName) })
//       item.wallpaper = Qt.binding(function() { return thumbs.wallpaper })
//     }
//   }
//
// This file owns everything singleton-shaped: Hyprland lookups, the wallpaper
// source, and the change signal consumers bind against. The maths lives in
// lib/Geometry.js so it can be tested without a compositor.

Item {
  id: root

  // Injected by omarchy-shell's service loader.
  property var shell: null
  property var manifest: null

  readonly property int maxWindows: 32

  // Bumped whenever anything a frame depends on changes. Consumers bind to it
  // (see frameFor) so their thumbnails re-evaluate; QML cannot see through the
  // plain-object return value on its own.
  property int revision: 0

  // ---------------------------------------------------------------- wallpaper
  //
  // omarchy.background is itself a service and already tracks the current
  // wallpaper across theme switches, so read it rather than polling the
  // symlink. It may not be constructed yet when we are, hence the fallback.
  readonly property var backgroundService: root.shell && typeof root.shell.serviceFor === "function"
    ? root.shell.serviceFor("omarchy.background") : null
  property string fallbackBackgroundPath: ""
  readonly property string backgroundPath: {
    var fromService = root.backgroundService ? String(root.backgroundService.currentBackground || "") : ""
    if (fromService !== "") return fromService
    return root.fallbackBackgroundPath
  }
  readonly property url wallpaper: root.backgroundPath === "" ? "" : Qt.resolvedUrl("file://" + root.backgroundPath)

  // Only runs if omarchy.background is unavailable or has not resolved a path.
  Process {
    id: backgroundProbe
    running: root.backgroundService === null
    command: ["readlink", "-f", Quickshell.env("HOME") + "/.local/state/omarchy/current/background"]
    stdout: StdioCollector {
      onStreamFinished: root.fallbackBackgroundPath = String(text).trim()
    }
  }

  // ------------------------------------------------------------------- frames

  // Describe one workspace. `monitorName` is the connector the caller believes
  // the workspace belongs to; it is what shapes the thumbnail for a workspace
  // Hyprland has not created yet, which is the empty-workspace case.
  function frameFor(workspaceId, monitorName) {
    root.revision
    return Geometry.buildFrame({
      workspaceId: workspaceId,
      monitorName: monitorName,
      workspaces: Hyprland.workspaces ? Hyprland.workspaces.values : [],
      monitors: Hyprland.monitors ? Hyprland.monitors.values : [],
      focusedMonitor: Hyprland.focusedMonitor,
      maxWindows: root.maxWindows
    })
  }

  // Convenience for consumers that only want to know the shape of a monitor,
  // without building a whole frame.
  function aspectForMonitor(monitorName) {
    root.revision
    var monitors = Hyprland.monitors ? Hyprland.monitors.values : []
    var monitor = Geometry.findMonitorByName(monitors, monitorName)
    return Geometry.aspectOf(monitor || Hyprland.focusedMonitor)
  }

  // ---------------------------------------------------------------- component

  // Handed to consumers so they never have to reach into this plugin's
  // directory. WindowTile is wired in here, keeping WorkspaceThumbnail.qml free
  // of Wayland imports and therefore testable headless.
  readonly property Component thumbnailComponent: thumbnailFactory

  Component {
    id: tileFactory
    WindowTile {}
  }

  Component {
    id: thumbnailFactory
    WorkspaceThumbnail {
      tileComponent: tileFactory
    }
  }

  // ------------------------------------------------------------------ signals

  Connections {
    target: Hyprland
    function onRawEvent(event) { root.revision++ }
  }

  Connections {
    target: Hyprland.workspaces
    function onValuesChanged() { root.revision++ }
  }

  Connections {
    target: Hyprland.monitors
    function onValuesChanged() { root.revision++ }
  }
}
