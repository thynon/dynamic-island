# 014 — Cache drag-session validation

- **Status**: DONE
- **Commit**: 41b751d
- **Severity**: MEDIUM
- **Category**: Performance
- **Estimated scope**: 3 files, about 45 lines

## Problem

`draggingUpdated` is pointer-frequency work, but both the shell drop target and
the Files AirDrop target decode pasteboard URLs on every callback. The AirDrop
target also standardizes paths, builds a Set, and scans every shelf item each
time.

## Target

- Decode and match drag content once in `draggingEntered`.
- Reuse cached URLs/IDs in `draggingUpdated`.
- Clear the cache on exit, end, and completed drop.
- At `performDragOperation`, use the cache with one defensive decode fallback.

## Repo conventions to follow

- Keep AppKit drag callbacks as the source of truth.
- Preserve current accepted operations and drop-point validation.
- Cache only in memory for the active drag session.

## Steps

1. Add failing checks that `draggingUpdated` no longer reads pasteboard URLs and
   both views expose active-drag caches.
2. Run `swift run DynamicIslandCoreChecks`; expect failure.
3. Cache shell-level file URLs and Files AirDrop matched IDs at drag entry.
4. Clear caches on every terminal drag callback and retain a perform-time
   fallback.
5. Re-run core checks.

## Boundaries

- Do not change file ownership, copying, persistence, or AirDrop behavior.
- Do not cache beyond a single drag session.

## Verification

- **Mechanical**: core checks and app build exit 0.
- **Feel check**: drag files across the shell and AirDrop zone; targeting remains
  continuous and the final drop contains the same items.
- **Done when**: no pointer-frequency drag callback repeats URL decoding or item
  matching.
