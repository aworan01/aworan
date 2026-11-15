Watchly tvOS 0.2.1 development preview for Apple TV HD/4K running tvOS 16 or later.

This asset is an unsigned tvOS device IPA. Use atvloadly to sign and install it. It is not an Android APK or an iPhone IPA.

Includes catalogue browsing, profiles, My List, watch history/resume, source selection, on-device torrent streaming and VLCKit playback. The Android feature set is not fully reproduced. See the repository README and validation report for limitations and verified checks.

New in 0.2.0: horizontal top navigation with Discover, backdrop-led browsing, movie/series and genre filters, per-profile Discover selections, sorting of loaded catalogue results, compact transport with preview seeking and auto-hide, audio/subtitle/info/speed panels, and IntroDB intro/outro skipping for supported movies and episodes. Reported post-credit scenes are preserved. Timing coverage varies; full TMDB filtering is not included.

New in 0.2.1: cancellable torrent reads, startup prebuffering, retained torrent sessions at storage limits with an increase-limit action, direct-URL preference, transport/decoder diagnostics and an Apple HLS control test in Settings. The player remains VLCKit. These changes require device testing and do not guarantee that unavailable torrents or unsupported releases will play.

Device compatibility, playback and installation must be tested on the intended Apple TV. The build workflow itself does not certify runtime behaviour.
