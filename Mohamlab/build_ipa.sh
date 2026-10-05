#!/usr/bin/env bash
# Construit MohamLab.ipa (non signé) sur un Mac avec Xcode 15+.
# Ensuite : Sideloadly, AltStore ou SideStore le signent avec ton identifiant Apple.
set -euo pipefail
cd "$(dirname "$0")"

command -v xcodegen >/dev/null || { echo "→ installation de XcodeGen"; brew install xcodegen; }
xcodegen generate

xcodebuild \
  -project MohamLab.xcodeproj \
  -scheme MohamLab \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build

rm -rf Payload MohamLab.ipa
mkdir Payload
cp -R build/Build/Products/Release-iphoneos/MohamLab.app Payload/
zip -qry MohamLab.ipa Payload
rm -rf Payload
echo "✓ MohamLab.ipa prêt ($(du -h MohamLab.ipa | cut -f1))"
