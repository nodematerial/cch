#!/bin/bash
# Build the source package of cch for one Ubuntu release
#   ppa-source.sh <cch version> <ubuntu version> <ubuntu series> <output dir> [signing key fingerprint]
# Without a key the package is left unsigned, for checking that it builds.
# Each release gets its own version, such as 0.3.1~ubuntu24.04.1, so that it sorts below the plain
# version and below the same cch for a newer Ubuntu, and upgrades across Ubuntu releases work
set -euo pipefail

version="$1" ubuntu="$2" series="$3" out="$4" key="${5:-}"

# The Ubuntu release comes from Launchpad and ends up in file names and the changelog, so accept only
# the shapes it should have
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "bad cch version: $version" >&2; exit 1; }
[[ "$ubuntu" =~ ^[0-9]{2}\.[0-9]{2}$ ]] || { echo "bad Ubuntu version: $ubuntu" >&2; exit 1; }
[[ "$series" =~ ^[a-z]+$ ]] || { echo "bad Ubuntu series: $series" >&2; exit 1; }
deb_version="$version~ubuntu$ubuntu.1"
repo=$(git rev-parse --show-toplevel)
work=$(mktemp -d)
src="$work/cch-$deb_version"
mkdir -p "$src"

# Only tracked files, so nothing from the working tree (caches, editor files) ends up in the upload
git -C "$repo" archive HEAD | tar -x -C "$src"

# The changelog in the repository is for local builds; each upload gets a single entry of its own
maintainer=$(sed -n 's/^Maintainer: //p' "$src/debian/control")
cat > "$src/debian/changelog" <<CHANGELOG
cch ($deb_version) $series; urgency=medium

  * New upstream release $version: https://github.com/nodematerial/cch/releases/tag/v$version

 -- $maintainer  $(date -R)
CHANGELOG

if [ -n "$key" ]; then
  sign=(--sign-key="$key")
else
  sign=(--no-sign)
fi
(cd "$src" && dpkg-buildpackage -S -d "${sign[@]}")

mkdir -p "$out"
cp "$work"/cch_"$deb_version"* "$out"/
rm -rf "$work"
