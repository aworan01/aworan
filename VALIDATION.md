# Validation status

Prepared for Apple TV 4K (2022), user-confirmed tvOS 17. Deployment target remains tvOS 16; Discover uses native menus on tvOS 17+ and fallback pickers on tvOS 16.

## Current release: 0.2.0, build 2

- Successful build: https://github.com/aworan01/aworan/actions/runs/43689661882
- Built source commit: `cd5e969`.
- Seven Swift core tests passed, including catalogue sorting, missing metadata, skip-marker bounds, explicit absent markers and post-credit scene preservation.
- Three IPA packaging tests passed on the Mac runner and locally on Windows.
- Full Apple TV SwiftUI/VLCKit app compiled and linked successfully. Pinned native libraries were restored from the previously built cache.
- Downloaded IPA verified: ZIP integrity, ARM64 Mach-O, AppleTVOS physical-device platform, device family 3, minimum tvOS 16.0, version 0.2.0/build 2, bundled CA certificates and no code signature.
- IPA size: 18,945,650 bytes. SHA-256: `5ea836edbbcc4cdf684216674bc8b0a68bf660aa541eef989d5c8e1ae0101500`.
- No simulator UI review or physical Apple TV installation/playback test was performed. Successful compilation is not evidence of verified remote focus or playback on tvOS 17.

### New-feature acceptance checks on tvOS 17

1. Navigate every top tab; focus posters and verify the backdrop changes. Open and return from title details.
2. In Discover, switch Movies/Series and genres; test catalogue/title/year/rating ordering, reset, empty results and retry. Switch profiles and confirm saved selections are isolated.
3. Verify controls hide after seven idle seconds while playing. Reveal them, preview a seek with Left/Right, confirm with Select, cancel with Back, and move focus away from the timeline.
4. Switch audio and subtitle tracks, disable subtitles, change playback speed and open next-episode source selection from both the transport and settings panel.
5. With a title having IntroDB markers, test intro/outro buttons while transport controls are shown and hidden. Verify a reported post-credit scene is preserved. Test titles with no markers and a timing-service failure; playback should continue without skip buttons.

IntroDB contract checked against https://api.introdb.app/reference/get-segments/. Movie requests use `is_movie=true`; episode requests use season/episode. Timing is community-sourced and can differ between video releases. Discover sorts only the loaded Cinemeta results; full TMDB filters are outside this release.

## Earlier 0.1.0 baseline

## Checks performed locally on Windows

- Inspected the supplied Android TV architecture and source dependencies.
- Confirmed the pinned libtorrent, OpenSSL and player revisions against their upstream repositories.
- Verified Bash syntax for both build scripts.
- Ran three IPA-packaging tests: correct Payload layout, simulator rejection and missing-executable rejection. All passed. These use a fixture, not a compiled Apple TV executable.

## Build and device checks

The first GitHub Actions run (43664801270) failed before any build steps started. GitHub reported failed account payments or a spending-limit restriction. This is an account/runner startup failure, not a compiler result.

After the user authorized public visibility, the macOS build ran successfully:

- Final run: https://github.com/aworan01/aworan/actions/runs/43667478139
- Source commit: `d410fb3`
- Four Swift core tests and three packaging tests passed.
- OpenSSL, libtorrent and the Objective-C++ bridge compiled for ARM64 tvOS.
- The full SwiftUI app compiled and linked successfully with VLCKit.
- An unsigned IPA was generated and downloaded; ZIP integrity, ARM64 executable, physical AppleTVOS platform, device family 3 and tvOS 16.0 deployment target were verified.
- Final bundle version: **0.1.0**, build **1**. The follow-up build explicitly uses the configured preview version rather than XcodeGen's default.

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
