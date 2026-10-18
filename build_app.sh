#!/bin/bash
set -e

echo "=== Building Scad2Stl Release Binary ==="
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
BUILD_DIR="/tmp/Scad2StlBuild"

swift build -c release --build-path "$BUILD_DIR"

APP_BUNDLE="Scad2Stl.app"
echo "=== Packaging $APP_BUNDLE ==="
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/release/Scad2Stl" "$APP_BUNDLE/Contents/MacOS/Scad2Stl"
cp "Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Strip detritus / extended attributes and ad-hoc code sign the bundle
xattr -cr "$APP_BUNDLE"
codesign --force --deep --sign - "$APP_BUNDLE"

echo "=== Successfully built $APP_BUNDLE ==="
ls -lh "$APP_BUNDLE/Contents/MacOS/Scad2Stl"
