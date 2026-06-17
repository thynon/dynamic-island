# File Shelf Overlay Design

## Goal

Add a temporary file shelf to Island. Users can drag files to the notch area, pause briefly, and drop files into a dedicated shelf view. The shelf is an overlay mode that can cover `Status`, `Stats`, and `Tools` content without becoming a new first-level feature.

## Confirmed Behavior

- Dragging one or more files to the notch/Island area and holding for about `1s` expands Island into the file shelf overlay.
- While files are being dragged, the expanded panel shows a dedicated drop interface instead of the current first-level feature content.
- After files are dropped, Island may collapse when the mouse leaves.
- If the shelf contains files, a `Files` button appears in the expanded top-left safe band, beside the camera housing in the user-marked location.
- Clicking `Files` opens the shelf overlay and pins Island open. In this pinned state, mouse exit does not auto-collapse the panel.
- If all temporary files are removed, the shelf unpins, the `Files` button disappears, and Island returns to the normal default behavior.
- Files are retained only while the app process is alive.
- Restarting Island clears the shelf.
- During one app run, files expire after at most `24h` and are removed automatically.

## Out Of Scope For First Version

- Persisting shelf contents across app restarts.
- Copying files into an Island-owned storage folder.
- Cloud sync, AirDrop, share sheet, compression, tagging, folders, search, or preview editing.
- Adding `Files` as a permanent first-level `Status / Stats / Tools` feature.

## Architecture

### Core Model

Add a small pure model in `IslandCore`:

- `TemporaryShelfItem`: stable ID, original file URL, display name, optional file extension, added date, expiry date.
- `TemporaryShelf`: ordered item list plus helpers for add, remove, clear, prune expired, and `hasItems`.

The model must not import AppKit or SwiftUI.

### App Layer Store

Add an in-memory `TemporaryFileShelfStore` in `Sources/Island/Support/`.

- Stores file URLs only for the current process lifetime.
- Deduplicates by file URL when adding the same file again.
- Sets `expiresAt = addedAt + 24h`.
- Prunes expired items on add, on periodic polling, and when opening the shelf.

No JSON persistence is needed.

### Drag And Drop

Use AppKit dragging support at the island panel/hosting view level, because the collapsed target must react before SwiftUI content is expanded.

Flow:

1. Detect file URLs in the dragging pasteboard.
2. If the drag remains over the notch/Island target for about `1s`, expand Island and switch overlay mode to file shelf drop mode.
3. On drop, add file URLs to the shelf store and show the shelf content.
4. If the drag exits before the hold delay completes, cancel the pending expansion.

### Overlay State

Extend `IslandOverlayState` with file shelf state:

- `fileShelfItems`
- `isFileShelfOverlayVisible`
- `isFileShelfPinnedOpen`
- `isFileDropTargetActive`

The overlay mode takes precedence over normal `DataPanelView` content. `Status / Stats / Tools` selection remains remembered and unchanged underneath.

### Top Safe-Band Button

Place the `Files` button inside `IslandTopStatusBandLayout.leftStatusRegion`, near the camera housing side of that region. It must not enter `cameraHousingRegion`.

Display rule:

- Show only when `fileShelfItems` is not empty.
- Hide immediately when the shelf becomes empty.

Click behavior:

- Set `isFileShelfOverlayVisible = true`.
- Set `isFileShelfPinnedOpen = true`.
- Expand Island if needed.

### Auto-Collapse Rules

- Normal hover behavior remains unchanged when the shelf is empty or not pinned.
- Dropping files does not permanently pin the shelf.
- Clicking the `Files` button pins the shelf open.
- Removing all files clears the pin and allows collapse.

## UI

The shelf overlay should match the existing dark Island visual language:

- Compact header inside the content area.
- Dashed or softly outlined drop zone while dragging.
- File tiles/list with file icon, filename, and lightweight metadata.
- Actions: open, remove, clear all.
- Drag-out support should be included if feasible in the first implementation; otherwise keep the source URL available and prioritize click-to-open and remove.

The UI must avoid the physical camera housing and should not move the established right-side `Status / Stats / Tools` switcher.

## Error Handling

- Ignore non-file pasteboard items.
- If a dropped file URL no longer exists, keep the item only until the user opens/removes it, then remove stale items when detected.
- If opening a file fails, leave the item in the shelf.

## Testing

Add `IslandCoreChecks` coverage for:

- Shelf item expiry at 24h.
- Deduping by file URL.
- Removing/clearing items.
- `Files` button placement stays inside `leftStatusRegion` and outside `cameraHousingRegion`.
- Source-level checks that shelf state is in-memory only and no restart persistence file is introduced.

Manual verification:

- Drag a file to the notch and hold about `1s`: Island expands into shelf overlay.
- Drop files: files appear.
- Move mouse away: Island collapses if not pinned.
- Hover/open and click `Files`: shelf opens and stays expanded.
- Remove all files: button disappears and Island can collapse.
- Restart app: shelf is empty.

