#!/bin/sh
# 配布用の .dmg を作る。出力: .build/TorqueController-<版>.dmg
set -eu
cd "$(dirname "$0")/.."
IDENTITY="TorqueController Local Signing"
APP=".build/app/TorqueController.app"
STAGE=".build/dmg"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' App/Info.plist)"
DMG=".build/TorqueController-$VERSION.dmg"
GUIDE="はじめにお読みください.rtf"

scripts/build-app.sh

# build-app.sh は証明書がないとアドホック署名に落とす。その版を渡すと、入れ替えのたびに許可が外れる
if ! codesign -dvv "$APP" 2>&1 | grep -qx "Authority=$IDENTITY"; then
  echo "$IDENTITY で署名されていないので、.dmg を作りません。" >&2
  exit 1
fi

rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/TorqueController.app"
ln -s /Applications "$STAGE/Applications"
textutil -convert rtf -inputencoding UTF-8 -output "$STAGE/$GUIDE" App/ReadMe-ja.html

hdiutil create -volname "TorqueController $VERSION" -srcfolder "$STAGE" -format ULMO -ov "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null
rm -rf "$STAGE"
du -h "$DMG"
