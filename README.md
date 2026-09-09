# Workspace Thumbnails

A component that renders monitor-shaped thumbnails of Hyprland workspaces for an
Omarchy plugin. It has no UI of its own — it hands its host a ready-made
thumbnail component instead of that plugin reimplementing one.

- Each thumbnail uses **its own monitor's aspect ratio**, with the bar's reserved
  space subtracted — an ultrawide workspace looks ultrawide, a portrait monitor
  looks portrait.
- **Empty workspaces render the current wallpaper** as a placeholder, at that
  same aspect. So do workspaces Hyprland has not created yet, as long as the
  caller says which monitor they belong to.
- Windows are drawn as live screencopy tiles at their real positions, including
  on **workspaces you are not currently looking at**.

## This is not an installable plugin

**Do not run `omarchy plugin add` on this repo.** It has no `manifest.json`.

Omarchy 4.0.3 restricted third-party plugins to looking up their *own* service,
so a shared thumbnail service is no longer reachable by anyone. This repo is
therefore vendored into its consumer and mounted under that plugin's id.

That restriction landed as a security fix (upstream PR 9618). It is not coming
back, and there is no manifest flag that opts out. The full reasoning, and the
code path that enforces it, are in
[IMPLEMENTATION.md](IMPLEMENTATION.md#why-this-is-vendored).

## Install into a consumer

```sh
./install.sh ~/Projects/mybarwidget
```

That copies `Service.qml`, `WorkspaceThumbnail.qml`, `WindowTile.qml` and
`lib/Geometry.js` into `<consumer>/thumbnails/`, then checks the consumer's
manifest declares the service. Merge `manifest.fragment.json` into that manifest
first:

```json
{
  "kinds": ["bar-widget", "service"],
  "keepLoaded": true,
  "entryPoints": { "service": "thumbnails/Service.qml" }
}
```

Re-run `install.sh` after any change here to carry it across.

## Using it from the host plugin

The host asks for **its own plugin id**, because that is what the service is
mounted under:

```qml
readonly property var thumbs: bar && bar.shell && typeof bar.shell.serviceFor === "function"
  ? bar.shell.serviceFor("mlclifton.workspaces") : null

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
| `wallpaper` | Current wallpaper URL. |
| `refreshWallpaper()` | Re-reads the wallpaper. Call it as a preview opens; nothing pushes theme changes any more. |
| `thumbnailComponent` | `WorkspaceThumbnail` with the window tile already wired in. |

`frameFor()` never returns null: with no compositor state at all you still get a
16:9 wallpaper-only frame, so there is no null case to handle.

Sizing is up to you — give the thumbnail a bounding box via `width`/`height` and
it letterboxes itself to the monitor's aspect inside it.

## Requirements

- Omarchy 4.0.3 or later with the Quickshell bar, and Hyprland
- No additional services or packages

## Development

```sh
tests/run.sh          # full suite: structure, node units, qmllint, qmltestrunner
tests/run.sh unit     # fast loop
```

The suite runs headless with no compositor, against the files in this repo
rather than the vendored copies. See [IMPLEMENTATION.md](IMPLEMENTATION.md) for
the architecture, the layering rules the tests enforce, and the manual
verification recipe.

## Removal

Delete the vendored directory from the consumer and drop the `service` entry
from its manifest:

```sh
rm -rf ~/Projects/mybarwidget/thumbnails
```

## License

MIT. See [LICENSE](LICENSE).
