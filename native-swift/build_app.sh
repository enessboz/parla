#!/bin/bash
# Usage: ./build_app.sh   -> builds EnglishPractice.app in this folder
set -e
cd "$(dirname "$0")"
swift build -c release
APP=EnglishPractice.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/EnglishPractice "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Hazır: $APP  (açmak için: open $APP)"
