# Validation status

Prepared for Apple TV 4K (2022), tvOS 16+.

## Checks performed locally on Windows

- Inspected the supplied Android TV architecture and source dependencies.
- Confirmed the pinned libtorrent, OpenSSL and player revisions against their upstream repositories.
- Verified Bash syntax for both build scripts.
- Ran three IPA-packaging tests: correct Payload layout, simulator rejection and missing-executable rejection. All passed. These use a fixture, not a compiled Apple TV executable.

## Build and device checks

The first GitHub Actions run (43664801270) failed before any build steps started. GitHub reported failed account payments or a spending-limit restriction. This is an account/runner startup failure, not a compiler result.

The Swift tests, Objective-C++/Swift compilation, dependency linking and IPA generation remain unverified until a macOS runner starts successfully.

No physical Apple TV installation or playback test has been performed.

## Required device acceptance checks

1. Install with atvloadly; launch from the home screen and allow the local-network prompt if displayed.
2. Browse/search, open a film and series, switch seasons, navigate all buttons with the Siri Remote.
3. Create two profiles, save different titles, set a PIN, switch profiles and verify isolation.
4. Play an authorized direct MP4/HLS URL and a known healthy authorized torrent. Test multi-file selection, pause, resume, forward/backward seeking and audio/subtitle selection.
5. Close during metadata discovery and buffering; open another source. Confirm cancellation and cleanup.
6. Let playback cross the configured storage limit, test seeking across that boundary and check remaining device storage.
7. Background/foreground the app, restart it and verify saved progress. Test an unavailable source, provider failure and storage exhaustion.
8. Separately verify 4K/HDR, audio format support and sustained playback on the target TV/audio system.
