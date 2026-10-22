#!/bin/sh
set -e
cd "$(dirname "$0")"
APP=NowSpinning.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
swiftc -O -parse-as-library -target arm64-apple-macos14.2 \
  -framework SwiftUI -framework CoreAudio -framework AudioToolbox \
  Sources/*.swift -o "$APP/Contents/MacOS/NowSpinning"
cp Info.plist "$APP/Contents/"
codesign -s - --force --options runtime "$APP"   # ad-hoc 서명 + hardened runtime (권한 기억, 코드 인젝션 차단)
echo "built $APP  →  open $APP"
