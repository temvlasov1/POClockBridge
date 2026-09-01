# Changelog

## 0.4.0

- Fixed AUv3 MIDI output discovery when a host installs its callback after it
  has already fetched the render block.
- Added a render-thread `SEND TEST C4` diagnostic, MIDI connection/error status,
  and a successful-event counter.
- Added safe 4 Hz live UI updates for running tempo, tempo changes, clock stop,
  and restart without the UIKit animation timer that caused build 5 to crash.
- Tap messages now use an explicit MIDI note-off for host-control compatibility.
- Corrected note 60 naming to C4 as displayed by AUM.

## 0.2.1

- Fixed AUv3 invalidation in hosts that provide null output buffer pointers on
  entry to the render block, including the AUM device graph.
- Added preallocated render-lifetime audio storage and safe silent rendering
  while an effect input is temporarily disconnected.

## 0.2.0

- Replaced guessed first-pulse clock start with deterministic two-pulse lock.
- Added fixed-storage robust median interval estimator, missing-pulse recovery,
  early-transient rejection, smoothing, phase correction, and dropout re-arm.
- Added adaptive Schmitt threshold, polarity-independent detection, refractory
  window, optional DC blocker, peak/threshold/jitter/phase telemetry.
- Moved quarter-note Tap output onto the sample-timestamped 24-PPQN scheduler.
- Added Auto/1/2/4/12/24/48 PPQN selection and documented Auto ambiguity.
- Refactored AUv3 adapter to preallocate scratch memory and apply atomic parameter
  snapshots only at render-block boundaries.
- Added mono/stereo Float32 format validation, discontinuity reset, parameter
  persistence, minimal AU UI, and containing-app registration/setup screen.
- Added 13 deterministic test groups and strict compiler warnings.
- Added macOS `build.sh`, GitHub Actions unsigned IPA pipeline, disabled
  TestFlight workflow template, Windows sideload guide, Link feasibility result,
  known limitations, architecture notes, and hardware device checklist.
