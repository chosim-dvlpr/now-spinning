#!/bin/sh
# 사용: ./release.sh 0.2.0  → Info.plist 버전 갱신, 빌드, zip, 커밋/태그, GitHub Release 생성
set -e
cd "$(dirname "$0")"
V="$1"; [ -n "$V" ] || { echo "usage: ./release.sh <version>"; exit 1; }
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $V" Info.plist
./build.sh
rm -f NowSpinning.zip
ditto -c -k --keepParent NowSpinning.app NowSpinning.zip
git add Info.plist && git commit -m "v$V" && git tag "v$V" && git push && git push --tags
gh release create "v$V" NowSpinning.zip --title "v$V" --generate-notes
echo "released v$V"
