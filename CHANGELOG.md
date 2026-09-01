# Changelog

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
