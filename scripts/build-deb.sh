#!/bin/sh
# Build the official SoftEther VPN .deb packages with the local patches applied.
#
# Environment:
#   SOFTETHER_VERSION   upstream tag to build (default 5.2.5189)
#   DISTRO, DISTRO_RELEASE  only used to name the output directory / artifact
#   WORK                scratch directory (default /tmp/softether-build)
set -eu

SOFTETHER_VERSION=${SOFTETHER_VERSION:-5.2.5189}
DISTRO=${DISTRO:-unknown}
DISTRO_RELEASE=${DISTRO_RELEASE:-unknown}
WORK=${WORK:-/tmp/softether-build}
REPO_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT="$REPO_DIR/out/$DISTRO-$DISTRO_RELEASE"

TARBALL="SoftEtherVPN-${SOFTETHER_VERSION}.tar.xz"
URL="https://github.com/softethervpn/softethervpn/releases/download/${SOFTETHER_VERSION}/${TARBALL}"

echo "::group::fetch the official source"
mkdir -p "$WORK"
cd "$WORK"
if [ ! -f "$TARBALL" ]; then
    curl -fsSL -o "$TARBALL" "$URL"
fi
sha256sum "$TARBALL"
echo "::endgroup::"

echo "::group::unpack"
rm -rf tree
mkdir tree
tar -xJf "$TARBALL" -C tree --strip-components=1
cd tree
echo "::endgroup::"

echo "::group::apply patches"
for p in "$REPO_DIR"/patches/*.patch; do
    echo "--- $(basename "$p")"
    patch -p1 --batch --forward <"$p"
done
if grep -q '^[[:space:]]*is_restricted = SiIsEnterpriseFunctionsRestrictedOnOpenSource' \
        src/Cedar/Server.c; then
    echo "ERROR: is_restricted is still assigned in src/Cedar/Server.c" >&2
    exit 1
fi
echo "is_restricted assignments commented out: OK"
echo "::endgroup::"

echo "::group::configure"
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
echo "::endgroup::"

echo "::group::build"
cmake --build build --parallel "$(nproc)"
echo "::endgroup::"

echo "::group::package (CPack / DEB)"
( cd build && cpack -G DEB )
echo "::endgroup::"

echo "::group::collect"
mkdir -p "$OUT"
find build -name '*.deb' -exec cp -v {} "$OUT/" \;
cd "$OUT"
ls -l
for deb in ./*.deb; do
    dpkg-deb -f "$deb" Package Version Architecture
done
sha256sum ./*.deb >SHA256SUMS
cat SHA256SUMS
echo "::endgroup::"
