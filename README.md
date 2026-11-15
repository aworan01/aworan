# Watchly for Apple TV

Native tvOS port of the supplied Watchly Android TV project. Target: Apple TV 4K (2022), tvOS 16 or later. SwiftUI interface, libtorrent 2.0.11 streaming, and VLCKit 3.6 playback. This is a development preview, not a verified feature-complete replacement for the Android app.

## What the source implements

- Movie/series catalogue, genre browsing, search, title details, seasons and episodes using Cinemeta.
- Separate local profiles, optional four-digit profile PINs, My List, watch history and resume.
- Stremio-compatible source selection (Torrentio is the initial configurable provider), with file indices retained for season packs.
- Direct HTTP(S) playback, magnet links and remote `.torrent` files.
- On-device BitTorrent, DHT/tracker discovery, verified-piece reads, video file selection and seeking through a loopback-only HTTP range server.
- Streaming storage limit, with deletion/restart at the current read location when the limit is reached. Brief buffering is expected on rollover.
- Siri Remote playback controls, audio/subtitle track selection, IntroDB skip-intro data and next-episode source selection.
- macOS build scripts and GitHub Actions workflow producing an **unsigned tvOS device IPA** for a sideloading tool.

## Important differences from Android

This initial port does not reproduce every Android feature. It does not include all seven original torrent indexes, raw torrent-name search, external subtitle-provider search/download, offline downloads, Chromecast, Android data migration, custom avatars, theme switching, or all of the original player's controls/statistics. Embedded subtitle tracks work through VLCKit. External providers can be configured using the compatible stream endpoint.

Profile PINs are a convenience lock, not strong security or parental controls. Profiles and history are local, not cloud-synced. tvOS may evict cache data. HDR/Dolby Vision, Atmos/passthrough, codec performance, and remote focus behaviour need testing on the actual device; they are not promised by the source alone. Peer availability and third-party APIs affect playback.

## Build on GitHub (no personal Mac required)

1. Put the contents of this folder at the root of a GitHub repository.
2. Open **Actions → Build Watchly for Apple TV → Run workflow**. Pushes to `main` also build automatically.
3. Wait for the entire workflow to succeed. A compile failure means no usable IPA has been produced; inspect the failing step.
4. Download the **Watchly-tvOS-unsigned** artifact and unzip it to obtain `Watchly-tvOS-unsigned.ipa`.
5. Open atvloadly on a computer on the same local network as the Apple TV. Pair the device, provide your signing identity in atvloadly, select the IPA and install it.

Apple credentials and certificates are **not** required in GitHub. Signing happens in atvloadly. Keep authentication and two-factor codes in that app. For private repositories, download the workflow artifact while signed in; do not assume atvloadly can track private GitHub releases.

Pushing a tag beginning with `tvos-v` runs the build and publishes a **prerelease** with the IPA, suitable for a compatible release-tracking setup. Do this only after a successful build and device test. Release visibility follows repository visibility. No release tag is needed for manual sideloading.

## Build on a Mac

Install Xcode with the tvOS platform and its command-line tools, plus Homebrew. In Terminal:

```sh
brew install cmake ninja xcodegen
swift test
python3 -m unittest discover -s scripts/tests -v
bash scripts/build-ipa.sh
```

The script fetches pinned libtorrent/OpenSSL sources and checksum-verifies Boost, builds ARM64 tvOS static libraries, generates the Xcode project, resolves the pinned player package and builds the app. It uses the selected Xcode, which must include a tvOS SDK. Build output is `build/Watchly-tvOS-unsigned.ipa`.

For an Apple Silicon Mac simulator build:

```sh
bash scripts/build-native.sh appletvsimulator
xcodegen generate
xcodebuild -project Watchly.xcodeproj -scheme Watchly -configuration Debug \
  -sdk appletvsimulator -destination 'generic/platform=tvOS Simulator' \
  -derivedDataPath build/Simulator CODE_SIGNING_ALLOWED=NO ARCHS=arm64 build
```

Simulator builds cannot be installed on a physical Apple TV. The packaging script explicitly rejects them. Intel simulator builds are not configured.

## Source layout

| Location | Purpose |
| --- | --- |
| `Sources/Core` | Codable models, episode matching and HTTP byte-range validation |
| `Sources/Services` | Catalogue requests, profiles/library, async torrent wrapper and local range server |
| `Sources/Views` | Native TV browsing, details, settings and playback |
| `Native` | Objective-C++ bridge and CMake target for libtorrent |
| `scripts` | Dependency build, app build, IPA packaging and packaging tests |
| `Tests` | Swift tests for ranges, episode selection and magnet construction |
| `.github/workflows/tvos.yml` | macOS build and optional tagged prerelease |

## Validation and installation

See `VALIDATION.md` for the checks actually run and the outstanding device test plan. A generated source tree is not proof of a working Apple TV binary. No installed or tested app should be claimed until the corresponding build and device checks have passed.

## Attribution

The input Watchly project includes the MIT license reproduced in `LICENSE`. Its architecture and behaviour informed this port. Third-party libraries retain their own licenses; see `THIRD-PARTY-NOTICES.md` and `Resources/Licenses`. Use content you have permission to access.
