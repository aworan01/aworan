# Third-party notices

- **Original Watchly source:** supplied `Watchly-main.zip`, MIT. Original notice preserved verbatim in `LICENSE` and `Resources/Licenses/Watchly.txt`.
- **libtorrent:** v2.0.11, commit `9d7443f467147d1784fb7516d2a882db1abb5a8b`, BSD 3-Clause. https://github.com/arvidn/libtorrent
- **Boost:** 1.85.0, Boost Software License 1.0. https://www.boost.org/
- **OpenSSL:** 3.5.9, commit `45e844fa2a14ec92d146bd8f5778ac130b6625fb`, Apache 2.0. https://github.com/openssl/openssl
- **VLCKit / libVLC:** player package pinned to `tylerjonesio/vlckit-spm` commit `e932bbd488872fdb74f6654d28c2f291eae03daf` (3.6.0). https://github.com/tylerjonesio/vlckit-spm and https://code.videolan.org/videolan/VLCKit . LGPL 2.1 terms and included codec-library notices apply to the binary distribution. This source repository does not contain the player binary; Swift Package Manager retrieves the pinned artifact with its declared SHA-256 checksum.
- **Cinemeta, Torrentio and IntroDB:** external services, not included code. Their availability, API contracts, content and usage terms are controlled by their respective operators.

Native library notices are copied into the app's resources during the build. The player license is included in `Resources/Licenses/VLCKit.txt`. The complete application source and build instructions are available for rebuilding; a distributor of binaries must also retain applicable dependency notices and satisfy the corresponding LGPL source/relinking obligations for the exact player and codec build distributed. Do not treat an application-source archive alone as the corresponding source for every bundled codec.

The XcodeGen project and build scripts can be changed to point to a rebuilt VLCKit package. Upstream player source and build instructions: https://code.videolan.org/videolan/VLCKit .
