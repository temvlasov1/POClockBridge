# Build status

## COMPILED AND VERIFIED — portable realtime core

Environment: Windows 11, MSVC 19.29, C++17, Release `/O2 /W4 /permissive-`.

Exact verification command:

```bat
call "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
cl.exe /nologo /std:c++17 /EHsc /O2 /W4 /permissive- Core\POClockEngine.cpp Tests\test_engine.cpp /Fe:poclock_tests.exe
poclock_tests.exe
```

Result: all 13 test groups passed. The groups cover every required acceptance
scenario, including five steady tempos, two jitter levels, missing/extra pulses,
tempo step, dropout/restart, polarity, sample rates, adaptive threshold, tap-only,
Auto PPQN, and a simulated 10-minute drift assertion.

## REQUIRES GITHUB macOS RUN — iOS app and AUv3

Windows cannot run Xcode. `.github/workflows/build-ios.yml` calls `./build.sh` on
GitHub's macOS 26 image. The script:

1. reruns core tests;
2. generates the project with XcodeGen;
3. runs a Release `generic/platform=iOS` build with signing disabled;
4. requires `POClockBridgeApp.app/PlugIns/POClockBridgeAU.appex`;
5. validates plist type `aumf` and arm64 executables;
6. packages `POClockBridge-unsigned.ipa` and SHA-256.

The GitHub result and exact Xcode command/output will be recorded in the uploaded
`xcodebuild.log` artifact.

## REQUIRES DEVICE TEST

Host discovery, real AI-Micro channel order, physical pulse levels, AUM MIDI
routing, and long-run hardware phase are covered by `DEVICE_TEST_CHECKLIST_RU.md`.
