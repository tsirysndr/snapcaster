#!/bin/bash
# Remove the Snapcaster HAL driver and restart coreaudiod.
set -euo pipefail

echo "==> removing /Library/Audio/Plug-Ins/HAL/SnapcasterAudio.driver (sudo required)"
sudo rm -rf /Library/Audio/Plug-Ins/HAL/SnapcasterAudio.driver

echo "==> restarting coreaudiod"
# SIP forbids kickstarting coreaudiod; killing it works — launchd relaunches it.
sudo killall coreaudiod

echo "==> done"
