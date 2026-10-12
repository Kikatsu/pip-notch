#!/bin/bash
# Builds a universal Release Pip.app and zips it with the install note into dist/.
# Usage: scripts/package-release.sh   (version comes from project.yml)
set -euo pipefail
cd "$(dirname "$0")/.."

version=$(awk -F'"' '/CFBundleShortVersionString/ {print $2; exit}' project.yml)
xcodegen generate --quiet
xcodebuild -project Pip.xcodeproj -scheme Pip -configuration Release \
  -derivedDataPath build/ReleaseData -destination 'generic/platform=macOS' \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO -quiet build

staging="dist/Pip"
rm -rf "$staging" && mkdir -p "$staging"
ditto build/ReleaseData/Build/Products/Release/Pip.app "$staging/Pip.app"
sed "s/^Pip [0-9.]* (beta)/Pip $version (beta)/" scripts/how-to-open.txt > "$staging/How to open Pip.txt"

zip="dist/Pip-$version.zip"
rm -f "$zip"
ditto -c -k --keepParent "$staging" "$zip"
echo "$zip"
