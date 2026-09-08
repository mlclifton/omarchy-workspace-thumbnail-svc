# Workspace Thumbnails

A shared Omarchy **service** that renders monitor-shaped thumbnails of Hyprland
workspaces. It has no bar widget and no UI of its own — it hands other plugins a
ready-made thumbnail component so they stop reimplementing one each.

- Each thumbnail uses **its own monitor's aspect ratio**, with the bar's reserved
  space subtracted — an ultrawide workspace looks ultrawide, a portrait monitor
  looks portrait.
- **Empty workspaces render the current wallpaper** as a placeholder, at that
  same aspect. So do workspaces Hyprland has not created yet, as long as the
  caller says which monitor they belong to.
- Windows are drawn as live screencopy tiles at their real positions, including
  on **workspaces you are not currently looking at**.
- The wallpaper tracks theme switches, read from the `omarchy.background` service.

## Install

```sh
omarchy plugin add https://github.com/mlclifton/omarchy-workspace-thumbnail-svc.git
```

A service is enabled by a top-level entry in `~/.config/omarchy/shell.json`:

```json
{ "plugins": [ { "id": "mlclifton.workspace-thumbnails" } ] }
```

Then `omarchy restart shell`. Confirm it loaded with:

```sh
omarchy plugin list | grep thumbnails    # enabled  third-party  service
```

Nothing will appear on screen by itself — a consumer plugin has to ask for a
thumbnail.

## Using it from a plugin

```qml
readonly property var thumbs: bar && bar.shell && typeof bar.shell.serviceFor === "function"
  ? bar.shell.serviceFor("mlclifton.workspace-thumbnails") : null

Loader {
  sourceComponent: thumbs ? thumbs.thumbnailComponent : null
  onLoaded: {
    item.frame = Qt.binding(function() { return thumbs.frameFor(workspaceId, monitorName) })
    item.wallpaper = Qt.binding(function() { return thumbs.wallpaper })
  }
}
```

| member | description |
| --- | --- |
| `frameFor(id, monitorName)` | Frame descriptor for one workspace. `monitorName` is the connector the caller believes it belongs to, which is what shapes a workspace that does not exist yet. |
| `aspectForMonitor(name)` | The monitor's aspect alone, for sizing a container before building a frame. |
| `wallpaper` | Current wallpaper URL, live. |
| `thumbnailComponent` | `WorkspaceThumbnail` with the window tile already wired in. |

`frameFor()` never returns null: with no compositor state at all you still get a
16:9 wallpaper-only frame, so there is no null case to handle.

Sizing is up to you — give the thumbnail a bounding box via `width`/`height` and
it letterboxes itself to the monitor's aspect inside it.

## Requirements

- Omarchy with the Quickshell bar, and Hyprland
- No additional services or packages

## Development

```sh
tests/run.sh          # full suite: structure, node units, qmllint, qmltestrunner
tests/run.sh unit     # fast loop
```

The suite runs headless with no compositor. See [IMPLEMENTATION.md](IMPLEMENTATION.md)
for the architecture, the layering rules the tests enforce, and the manual
verification recipe.

## Removal

```sh
omarchy plugin remove mlclifton.workspace-thumbnails
```

Remember to drop its entry from `shell.json`'s `plugins[]` too.

## License

MIT. See [LICENSE](LICENSE).
