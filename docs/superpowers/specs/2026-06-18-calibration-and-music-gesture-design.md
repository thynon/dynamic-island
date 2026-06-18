# Calibration And Music Gesture Design

## Goal

Add a hidden calibration mode for notch and non-notch display alignment, and make music skip gestures flow through one explicit state machine.

## Calibration Mode

Calibration is a debug-only overlay opened with `ISLAND_DEBUG_CALIBRATION=1`. It must not appear in normal launches. The overlay renders inside the island shell and shows:

- the current shell clipping outline
- the 5pt content boundary
- the camera housing forbidden region when the current display reports a real camera housing
- the left and right top safe regions from `IslandTopStatusBandLayout`
- a compact metrics label with shell size, camera width, safe inset, and display type

On non-notch displays, the camera region is not marked as a physical forbidden region. The overlay still shows the shell and 5pt boundary so the release layout can be checked on external monitors.

## Music Gesture State Machine

Horizontal music skipping should be driven by a single state machine instead of scattered booleans. The states are:

- `idle`
- `tracking(direction, progress)`
- `armed(direction, progress)`
- `cancelled(direction)`
- `committed(direction)`

Once a horizontal gesture locks to `previous` or `next`, the direction cannot flip until the gesture resets. Sliding back only lowers progress. If the gesture was armed and returns to the cancel boundary, it becomes cancelled and does not trigger the opposite icon or a skip command. A skip commits only on gesture end or fallback reset.

Vertical gestures remain separate after axis lock. Hidden shell state stays highest priority and only accepts downward restore.

## Verification

Core checks must cover:

- calibration layout uses a 5pt boundary
- real camera housing displays get a camera forbidden region
- non-notch displays do not get a physical camera forbidden region
- horizontal skip direction locks for the gesture
- rollback cancels without flipping direction
- armed gestures commit only on finish

App verification must include `swift build --product DynamicIsland`, `./script/build_and_run.sh --verify`, normal launch, a calibration debug launch screenshot, and CPU sampling.
