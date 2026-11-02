#!/bin/sh
# SVG からアプリのアイコン(.icns)とメニューバーのアイコン(PNG)を書き出す。出力: .build/icon/
# sips は macOS に入っているので、追加のインストールは要らない。qlmanage(透過しない)と ImageMagick(クリップと線が崩れる)は使えない。
set -eu
cd "$(dirname "$0")/.."
OUT=".build/icon"
ICONSET="$OUT/AppIcon.iconset"

# 使い方: render 元のSVG 画素数 出力
render() {
  sips -s format png -z "$2" "$2" "$1" --out "$3" >/dev/null
  [ "$(sips -g pixelWidth "$3" | awk '/pixelWidth/ {print $2}')" = "$2" ]
}

rm -rf "$OUT"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  render App/AppIcon.svg "$size" "$ICONSET/icon_${size}x${size}.png"
  render App/AppIcon.svg "$((size * 2))" "$ICONSET/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$ICONSET" -o "$OUT/AppIcon.icns"

render App/MenuBarIcon.svg 18 "$OUT/MenuBarIcon.png"
render App/MenuBarIcon.svg 36 "$OUT/MenuBarIcon@2x.png"
echo "$OUT"
