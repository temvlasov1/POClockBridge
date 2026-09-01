# Architecture

## Realtime path

```text
host input AudioBufferList
        │
        ├── unchanged mono/stereo passthrough ──────────────► host output
        │
        └── selected L/R channel
                │
                ▼
          optional DC blocker
                │
                ▼
    adaptive/manual Schmitt detector + refractory window
                │
                ▼
      robust 7-interval median + missing/false rejection
                │
                ▼
          smoothed period + phase correction
                │
                ├── 24 PPQN F8 + FA/FC
                └── quarter-note note 60 on/off
                         │
                         ▼
              AUMIDIOutputEventBlock with sample timestamps
```

`Core/POClockEngine.*` has no Apple dependencies. Once configured it does not
allocate, lock, log, perform I/O, or call Objective-C/Swift. MIDI events use a
fixed 512-entry array. Interval statistics use a fixed seven-value array.

`POClockDSPKernelAdapter.mm` owns one preallocated scratch buffer for selecting a
channel from interleaved stereo. Parameter changes enter through atomics and are
applied only when a generation counter changes, at a render-block boundary.
Status leaves the render thread through relaxed atomics for the UI timer.

## Start and stop semantics

The first valid edge only arms the estimator. The second valid edge establishes
period and phase, then emits one `FA`, the first `F8`, and a Tap. No clocks are
predicted from Initial BPM before an observed interval.

If no accepted pulse arrives for the configured number of estimated input
periods, the engine emits one `FC`, clears timing/PLL state, retains safe Schmitt
gate behavior, and requires a fresh pair of edges.

## AUv3 packaging

- Component type: `aumf`
- Subtype: `pclk`
- Manufacturer: `POCB`
- Extension point: `com.apple.AudioUnit-UI`
- Container bundle: `com.poclockbridge.app`
- Extension bundle: `com.poclockbridge.app.au`
- Deployment target: iOS 16

XcodeGen creates the Xcode project from `project.yml`. The application target has
an embed dependency on the extension. `build.sh` fails unless the finished app
contains `PlugIns/POClockBridgeAU.appex`, both executables include arm64, and the
extension plist still declares `aumf`.
