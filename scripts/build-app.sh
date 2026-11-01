#!/bin/sh
# TorqueController.app をビルドして署名する。出力: .build/app/TorqueController.app
set -eu
cd "$(dirname "$0")/.."
IDENTITY="TorqueController Local Signing"
BUNDLE_ID="com.takeman.torquecontroller"
APP=".build/app/TorqueController.app"
DICTIONARY=".build/dictionary/torque.dict"

if [ ! -f "$DICTIONARY" ]; then
  echo "辞書がありません。scripts/fetch-dictionary.sh と scripts/build-dictionary.sh を実行してください。" >&2
  exit 1
fi

swift build -c release --product TorqueController
BIN="$(swift build -c release --show-bin-path)/TorqueController"

pkill -x TorqueController || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp App/Info.plist "$APP/Contents/Info.plist"
cp "$DICTIONARY" "$APP/Contents/Resources/torque.dict"
cp ThirdParty/Mozc-LICENSE.txt "$APP/Contents/Resources/Mozc-LICENSE.txt"
cp "$BIN" "$APP/Contents/MacOS/TorqueController"

if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
  codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" --timestamp=none "$APP"
else
  # アドホック署名は再ビルドのたびに同一性が変わり、アクセシビリティの許可が外れる
  echo "警告: 証明書がないのでアドホック署名にします。scripts/create-signing-identity.sh を実行してください。" >&2
  codesign --force --sign - --identifier "$BUNDLE_ID" --timestamp=none "$APP"
fi
codesign --verify --strict "$APP"
echo "$APP"
