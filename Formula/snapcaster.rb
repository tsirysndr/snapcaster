class Snapcaster < Formula
  desc "macOS virtual audio device that streams system audio to Snapcast or Squeezebox"
  homepage "https://github.com/tsirysndr/snapcaster"
  url "https://github.com/tsirysndr/snapcaster/releases/download/v0.1.0/snapcaster-v0.1.0-macos-universal.tar.gz"
  version "0.1.0"
  sha256 "474ce92375d1bd9565ae44a9dc30937443fa6f3197b18e1cea713726ecc11a4b"
  license "MIT"

  # Built on the Core Audio HAL — macOS only. The bottle is a universal binary.
  depends_on :macos

  # snapcaster streams to a SlimProto server; ship squeezed so a local
  # Mac → Squeezebox setup works out of the box.
  depends_on "tsirysndr/tap/squeezed"

  def install
    bin.install "snapcaster"

    # The HAL driver can't be installed by brew (it lives in /Library, needs
    # sudo + a coreaudiod restart). Stage the bundle and install a helper that
    # does the privileged step on demand.
    libexec.install "SnapcasterAudio.driver"

    (bin/"snapcaster-install-driver").write <<~SH
      #!/bin/bash
      set -euo pipefail
      BUNDLE="#{libexec}/SnapcasterAudio.driver"
      HAL="/Library/Audio/Plug-Ins/HAL"
      echo "==> code-signing driver (ad-hoc)"
      codesign --force --sign - "$BUNDLE"
      echo "==> installing to $HAL (sudo required)"
      sudo mkdir -p "$HAL"
      sudo rm -rf "$HAL/SnapcasterAudio.driver"
      sudo cp -R "$BUNDLE" "$HAL/SnapcasterAudio.driver"
      echo "==> restarting coreaudiod"
      # SIP forbids kickstarting coreaudiod; killing it works — launchd relaunches it.
      sudo killall coreaudiod
      echo "==> done — select 'Snapcaster' in System Settings → Sound"
    SH
    (bin/"snapcaster-install-driver").chmod 0755

    (bin/"snapcaster-uninstall-driver").write <<~SH
      #!/bin/bash
      set -euo pipefail
      echo "==> removing /Library/Audio/Plug-Ins/HAL/SnapcasterAudio.driver (sudo required)"
      sudo rm -rf /Library/Audio/Plug-Ins/HAL/SnapcasterAudio.driver
      echo "==> restarting coreaudiod"
      sudo killall coreaudiod
    SH
    (bin/"snapcaster-uninstall-driver").chmod 0755
  end

  def caveats
    <<~EOS
      The Snapcaster audio driver must be installed into /Library (needs sudo):

        sudo snapcaster-install-driver

      Then select "Snapcaster" in System Settings → Sound → Output and run, e.g.:

        snapcaster -s tcp://127.0.0.1:4711     # squeezed / Squeezebox
        snapcaster -s tcp://127.0.0.1:4953     # Snapcast

      Allow the microphone prompt on first run — that's the loopback capture.
      Remove the driver later with:  sudo snapcaster-uninstall-driver
    EOS
  end

  test do
    assert_match "snapcaster", shell_output("#{bin}/snapcaster --help")
  end
end
