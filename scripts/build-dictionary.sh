#!/bin/sh
# Data/mozc/ のテキストを、実行時に使うバイナリ .build/dictionary/torque.dict に変換する。
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/dictionary
swift run -c release torque-cli build-dictionary Data/mozc .build/dictionary/torque.dict
