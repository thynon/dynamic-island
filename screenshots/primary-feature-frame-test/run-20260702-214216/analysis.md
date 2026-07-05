# Primary Feature Frame Test

- Capture path: `screenshots/primary-feature-frame-test/run-20260702-214216`
- Capture method: DynamicIsland rendered its own `IslandTrackingHostingView` to ordered PNG frames through the explicit `ISLAND_DEBUG_PRIMARY_FEATURE_FRAME_CAPTURE_DIR` debug path.
- System `screencapture` could not create an image from the display in this environment, so the accepted evidence is app-rendered frames rather than a macOS screen recording.
- Contact sheet: `primary-feature-contact-sheet-wide.png`
- Pixel first-visible order:
  - Tasks: frame-007
  - Data: frame-008
  - Tools: frame-009
  - Settings: frame-011
- Result: The current rendered animation appears left to right, not right to left.
