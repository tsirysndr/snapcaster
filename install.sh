#!/bin/bash
# Snapcaster one-line installer.
#
#   curl -fsSL https://raw.githubusercontent.com/tsirysndr/snapcaster/main/install.sh | bash
#
# Downloads the latest universal build from GitHub Releases, ad-hoc code-signs
# the HAL driver, installs it into /Library/Audio/Plug-Ins/HAL, drops the
# `snapcaster` CLI into /usr/local/bin, and restarts coreaudiod. Needs sudo.
#
# Override the version with:  SNAPCASTER_VERSION=v0.1.0 bash install.sh
set -euo pipefail

REPO="tsirysndr/snapcaster"
BUNDLE_NAME="SnapcasterAudio.driver"
HAL_DIR="/Library/Audio/Plug-Ins/HAL"
BIN_DIR="/usr/local/bin"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# macOS only — the whole thing is built on the Core Audio HAL.
os="$(uname -s)"
if [[ "$os" != "Darwin" ]]; then
  err "unsupported OS: $os — snapcaster only runs on macOS (it is built on the Core Audio HAL)"
fi

for tool in curl tar codesign; do
  command -v "$tool" >/dev/null 2>&1 || err "missing required tool: $tool"
done

# Resolve the download URL for the universal tarball.
version="${SNAPCASTER_VERSION:-}"
if [[ -n "$version" ]]; then
  asset="snapcaster-${version}-macos-universal.tar.gz"
  url="https://github.com/${REPO}/releases/download/${version}/${asset}"
else
  info "finding latest release"
  api="https://api.github.com/repos/${REPO}/releases/latest"
  url="$(curl -fsSL "$api" \
    | grep -o '"browser_download_url": *"[^"]*macos-universal\.tar\.gz"' \
    | head -n1 | sed 's/.*"browser_download_url": *"\([^"]*\)"/\1/')"
  [[ -n "$url" ]] || err "could not find a macos-universal asset in the latest release of $REPO"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

info "downloading $(basename "$url")"
curl -fsSL -o "$tmp/snapcaster.tar.gz" "$url"

info "extracting"
tar -xzf "$tmp/snapcaster.tar.gz" -C "$tmp"

bundle="$tmp/$BUNDLE_NAME"
cli="$tmp/snapcaster"
[[ -d "$bundle" ]] || err "$BUNDLE_NAME not found in the downloaded archive"
[[ -f "$cli" ]]   || err "snapcaster CLI not found in the downloaded archive"

info "code-signing the driver (ad-hoc)"
codesign --force --sign - "$bundle"

info "installing driver to $HAL_DIR (sudo required)"
sudo mkdir -p "$HAL_DIR"
sudo rm -rf "$HAL_DIR/$BUNDLE_NAME"
sudo cp -R "$bundle" "$HAL_DIR/$BUNDLE_NAME"

info "installing snapcaster CLI to $BIN_DIR"
sudo mkdir -p "$BIN_DIR"
sudo install -m 0755 "$cli" "$BIN_DIR/snapcaster"

info "restarting coreaudiod"
# SIP forbids kickstarting coreaudiod; killing it works — launchd relaunches it.
sudo killall coreaudiod

cat <<'DONE'

==> Snapcaster installed.

Next steps:
  1. System Settings → Sound → Output → select "Snapcaster"
     (or ⌥-click the volume menu-bar icon).
  2. Point the bridge at your server, e.g.:
       snapcaster -s tcp://127.0.0.1:4711     # squeezed / Squeezebox
       snapcaster -s tcp://127.0.0.1:4953     # Snapcast
  3. Allow the microphone prompt on first run — that's the loopback capture.

Uninstall:  sudo rm -rf /Library/Audio/Plug-Ins/HAL/SnapcasterAudio.driver && sudo killall coreaudiod
DONE
