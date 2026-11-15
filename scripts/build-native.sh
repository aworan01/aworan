#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${1:-appletvos}"
case "$SDK" in
  appletvos) TRIPLE=arm64-apple-tvos16.0 ;;
  appletvsimulator) TRIPLE=arm64-apple-tvos16.0-simulator ;;
  *) echo 'Use appletvos or appletvsimulator' >&2; exit 2 ;;
esac
[[ "$(uname -s)" == Darwin ]] || { echo 'Run this build on macOS with Xcode.' >&2; exit 1; }
for tool in cmake ninja git curl perl; do command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 1; }; done
SYSROOT="$(xcrun --sdk "$SDK" --show-sdk-path)"
JOBS="$(sysctl -n hw.ncpu)"
VENDOR="$ROOT/vendor"
DEST="$VENDOR/native/$SDK"
BUILD="$ROOT/build/native-$SDK"
mkdir -p "$VENDOR" "$DEST" "$BUILD" "$ROOT/Resources/Licenses"

checkout() {
  local url="$1" tag="$2" sha="$3" directory="$4"
  if [[ ! -d "$directory/.git" ]]; then git clone --depth 1 --branch "$tag" "$url" "$directory"; fi
  [[ "$(git -C "$directory" rev-parse HEAD)" == "$sha" ]] || { echo "Unexpected dependency revision: $directory" >&2; exit 1; }
}
checkout https://github.com/arvidn/libtorrent.git v2.0.11 9d7443f467147d1784fb7516d2a882db1abb5a8b "$VENDOR/libtorrent"
git -C "$VENDOR/libtorrent" submodule update --init --recursive --depth 1
checkout https://github.com/openssl/openssl.git openssl-3.5.9 45e844fa2a14ec92d146bd8f5778ac130b6625fb "$VENDOR/openssl"
if [[ ! -d "$VENDOR/boost_1_85_0" ]]; then
  curl --fail --location --retry 3 https://archives.boost.io/release/1.85.0/source/boost_1_85_0.tar.gz -o "$VENDOR/boost.tar.gz"
  printf '%s  %s\n' be0d91732d5b0cc6fbb275c7939974457e79b54d6f07ce2e3dfdd68bef883b0b "$VENDOR/boost.tar.gz" | shasum -a 256 --check
  tar -xzf "$VENDOR/boost.tar.gz" -C "$VENDOR"
fi

# A dedicated Apple TV target avoids accidentally linking an iOS or macOS slice.
cat > "$VENDOR/openssl/Configurations/99-watchly-tvos.conf" <<'PERL'
my %targets = (
    "watchly-tvos" => {
        inherit_from => [ "ios-common" ],
        CC => "clang",
        bn_ops => "SIXTY_FOUR_BIT_LONG",
    },
);
PERL
OPENSSL_BUILD="$BUILD/openssl"
OPENSSL_INSTALL="$BUILD/openssl-install"
mkdir -p "$OPENSSL_BUILD"
(
  cd "$OPENSSL_BUILD"
  CC="$(xcrun --sdk "$SDK" --find clang)" \
  CFLAGS="-target $TRIPLE -isysroot $SYSROOT -fPIC" \
  "$VENDOR/openssl/Configure" watchly-tvos no-shared no-tests no-apps no-ui-console no-module no-dso no-asm \
    --prefix="$OPENSSL_INSTALL" --libdir=lib
  make -j "$JOBS"
  make install_sw
)

cmake -S "$ROOT/Native" -B "$BUILD/bridge" -G Ninja \
  -DCMAKE_SYSTEM_NAME=tvOS -DCMAKE_OSX_SYSROOT="$SYSROOT" \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_DEFAULT_CMP0167=OLD \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DLIBTORRENT_SOURCE="$VENDOR/libtorrent" \
  -DBOOST_ROOT="$VENDOR/boost_1_85_0" -DBoost_NO_BOOST_CMAKE=ON \
  -DBoost_INCLUDE_DIR="$VENDOR/boost_1_85_0" \
  -DBoost_NO_SYSTEM_PATHS=ON \
  -DOPENSSL_ROOT_DIR="$OPENSSL_INSTALL" -DOPENSSL_USE_STATIC_LIBS=TRUE \
  -DOPENSSL_INCLUDE_DIR="$OPENSSL_INSTALL/include" \
  -DOPENSSL_SSL_LIBRARY="$OPENSSL_INSTALL/lib/libssl.a" \
  -DOPENSSL_CRYPTO_LIBRARY="$OPENSSL_INSTALL/lib/libcrypto.a"
cmake --build "$BUILD/bridge" --parallel "$JOBS"
cp "$BUILD/bridge/libWatchlyTorrent.a" "$DEST/"
cp "$BUILD/bridge/libtorrent/libtorrent-rasterbar.a" "$DEST/"
cp "$OPENSSL_INSTALL/lib/libssl.a" "$OPENSSL_INSTALL/lib/libcrypto.a" "$DEST/"
cp "$VENDOR/libtorrent/COPYING" "$ROOT/Resources/Licenses/libtorrent.txt"
cp "$VENDOR/openssl/LICENSE.txt" "$ROOT/Resources/Licenses/OpenSSL.txt"
cp "$VENDOR/boost_1_85_0/LICENSE_1_0.txt" "$ROOT/Resources/Licenses/Boost.txt"
# Export Apple's public roots for OpenSSL HTTPS tracker verification.
security find-certificate -a -p /System/Library/Keychains/SystemRootCertificates.keychain > "$ROOT/Resources/cacert.pem"
test -s "$ROOT/Resources/cacert.pem"
echo "Native libraries prepared for $SDK."
