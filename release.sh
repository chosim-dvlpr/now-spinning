#!/bin/sh
# 사용: ./release.sh 0.2.0
# Info.plist 버전 갱신 → 빌드 → zip → 커밋/태그/push → GitHub Release → homebrew-tap cask 버전·sha256 갱신·push
set -e
cd "$(dirname "$0")"
V="$1"; [ -n "$V" ] || { echo "usage: ./release.sh <version>"; exit 1; }
TAP="../homebrew-tap"; CASK="$TAP/Casks/now-spinning.rb"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $V" Info.plist
./build.sh
rm -f NowSpinning.zip
ditto -c -k --keepParent NowSpinning.app NowSpinning.zip
SHA=$(shasum -a 256 NowSpinning.zip | cut -d' ' -f1)

git add Info.plist && git commit -m "v$V" && git tag "v$V" && git push && git push --tags
gh release create "v$V" NowSpinning.zip --title "v$V" --generate-notes

sed -i '' "s/^  version \".*\"/  version \"$V\"/; s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"
git -C "$TAP" add Casks && git -C "$TAP" commit -m "now-spinning $V" && git -C "$TAP" push
echo "released v$V  sha256=$SHA"
