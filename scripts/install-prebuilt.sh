#!/bin/bash
# Install the prebuilt Snapcaster driver bundle (from a release tarball) into
# /Library/Audio/Plug-Ins/HAL and restart coreaudiod, then drop the `snapcaster`
# CLI into /usr/local/bin. Run this from the extracted tarball directory.
# Requires sudo.
set -euo pipefail
cd "$(dirname "$0")"

BUNDLE_NAME="SnapcasterAudio.driver"
HAL_DIR="/Library/Audio/Plug-Ins/HAL"
BIN_DIR="/usr/local/bin"

if [[ ! -d "$BUNDLE_NAME" ]]; then
  echo "error: $BUNDLE_NAME not found next to this script — run it from the extracted tarball" >&2
  exit 1
fi

echo "==> installing driver to $HAL_DIR (sudo required)"
sudo mkdir -p "$HAL_DIR"
sudo rm -rf "$HAL_DIR/$BUNDLE_NAME"
sudo cp -R "$BUNDLE_NAME" "$HAL_DIR/$BUNDLE_NAME"

echo "==> installing snapcaster CLI to $BIN_DIR"
sudo mkdir -p "$BIN_DIR"
sudo install -m 0755 snapcaster "$BIN_DIR/snapcaster"

echo "==> restarting coreaudiod"
# SIP forbids kickstarting coreaudiod; killing it works — launchd relaunches it.
sudo killall coreaudiod

echo "==> done — 'Snapcaster' should now appear as an output device"
