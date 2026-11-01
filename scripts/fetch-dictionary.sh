#!/bin/sh
# Mozc の dictionary_oss を固定した版で Data/mozc/ に取得し、ハッシュを検証する。
set -eu
cd "$(dirname "$0")/.."
COMMIT="e5f1494923a0a624d01f19c50d57bbdfa03ea5ba"
BASE="https://raw.githubusercontent.com/google/mozc/$COMMIT/src/data/dictionary_oss"
mkdir -p Data/mozc
for file in dictionary00.txt dictionary01.txt dictionary02.txt dictionary03.txt dictionary04.txt \
            dictionary05.txt dictionary06.txt dictionary07.txt dictionary08.txt dictionary09.txt \
            connection_single_column.txt id.def; do
  curl -sSfL -o "Data/mozc/$file" "$BASE/$file"
done
(cd Data/mozc && shasum -a 256 -c ../mozc.sha256 --quiet)
echo "取得しました: Data/mozc"
