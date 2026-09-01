# Known limitations — PO Clock Bridge 0.2

## Ableton Link is intentionally not advertised

The AUv3 executes inside its host process while the containing app is normally
not running. Apple documents that an extension has no direct communication with
its containing app and that the containing app is typically not active at the
same time. An App Group can share state or IPC primitives, but it does not grant
the containing app an always-running realtime lifecycle.

Driving Link from periodically written shared state would therefore produce a
misleading and potentially unstable Link timeline. LinkKit also requires local
network consent and Apple's multicast networking entitlement on current iOS.
Version 0.2 keeps Link off instead of faking support. AUM can follow the AUv3's
quarter-note Tap output; clock-capable apps can consume 24-PPQN MIDI Clock.

References:

- https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionOverview.html
- https://developer.apple.com/documentation/Xcode/configuring-app-groups
- https://ableton.github.io/linkkit/
- https://github.com/Ableton/LinkKit

## Automatic PPQN is heuristic

Pulse spacing alone cannot uniquely identify both tempo and PPQN. Auto chooses
the supported PPQN whose BPM is closest to **Auto PPQN Reference BPM**, with a
small preference for the PO default (2 PPQN). Set PPQN explicitly for a known
source; the default is 2.

## AUM host behavior

AUM is not treated as a generic MIDI Clock slave by this project. Use MIDI Learn
to map note 60/C3 to Tap Tempo. Exact MIDI routing labels can vary by AUM version.
Other hosts must expose MIDI output from an `aumf` AUv3 for Clock/Tap routing.

## Sideloading and capabilities

The GitHub artifact is unsigned and cannot launch until a legitimate signing
tool signs the app and embedded extension. A free Apple ID has a seven-day
provisioning lifetime; the AUv3 consumes an additional App ID. There is no
permanent unsigned installation path on stock iOS.

Some paid-program entitlements, notably multicast networking for Link, cannot be
added by a free sideloading profile. Version 0.2 does not request them.

## Hardware latency and signal quality

There is no automatic round-trip latency calibration. The generated grid follows
the input buffer's sample timeline; physical cable/interface/host input latency
remains as a fixed offset. Auto threshold is designed for line-level PO pulses,
but severely clipped, very quiet, or crosstalk-contaminated inputs may require a
manual threshold and correct stereo cabling.

## Verification boundary

The C++ realtime core is deterministic and covered by automated synthetic tests.
GitHub Actions compiles and inspects the device app/AUv3 bundle. A real iPhone,
current AUM, RØDE AI-Micro, cable, and Pocket Operator are still required for the
device checklist; CI cannot prove host discovery, hardware channel order, or
physical timing.
