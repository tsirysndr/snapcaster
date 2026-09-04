#!/bin/bash
# Build the Snapcaster HAL driver, assemble the .driver bundle, install it into
# /Library/Audio/Plug-Ins/HAL and restart coreaudiod so the "Snapcaster" device
# appears in System Settings → Sound. Requires sudo for the install step.
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE_NAME="SnapcasterAudio.driver"
BUNDLE="target/$BUNDLE_NAME"
HAL_DIR="/Library/Audio/Plug-Ins/HAL"

echo "==> building driver"
cargo build --release -p snapcaster-driver

echo "==> assembling $BUNDLE"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
cp driver/Info.plist "$BUNDLE/Contents/Info.plist"
cp target/release/libsnapcaster_driver.dylib "$BUNDLE/Contents/MacOS/SnapcasterAudio"
codesign --force --sign - "$BUNDLE"

echo "==> installing to $HAL_DIR (sudo required)"
sudo mkdir -p "$HAL_DIR"
sudo rm -rf "$HAL_DIR/$BUNDLE_NAME"
sudo cp -R "$BUNDLE" "$HAL_DIR/$BUNDLE_NAME"

echo "==> restarting coreaudiod"
# SIP forbids kickstarting coreaudiod; killing it works — launchd relaunches it.
sudo killall coreaudiod

echo "==> done — 'Snapcaster' should now appear as an output device"
