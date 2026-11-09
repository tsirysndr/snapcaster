module CI.Snapcaster (macosRelease) where

import Prelude
import CI.Support as S
import Data.Foldable (traverse_)
import Data.String as String
import Effect (Effect)
import Effect.Exception (throw)

-- | Build both macOS architectures and package the universal CLI and HAL driver.
-- | @param source Release source checkout; tooling may come from another revision.
-- | @param version Release tag used in the archive filename.
macosRelease :: { source :: String, version :: String } -> Effect Unit
macosRelease args = do
  unless (S.validVersion args.version) (throw "Invalid release version")
  host <- S.os
  unless (S.isMac host) (throw "Universal Snapcaster releases require macOS")
  source <- S.absolute args.source
  traverse_ (\target -> S.runIn source
    [ [ "cargo", "build", "--release", "--locked", "--target", target, "--bin", "snapcaster" ]
    , [ "cargo", "build", "--release", "--locked", "--target", target, "-p", "snapcaster-driver" ]
    ]) [ "aarch64-apple-darwin", "x86_64-apple-darwin" ]
  temporary <- String.trim <$> S.captureIn source [ "mktemp", "-d" ]
  let stage = temporary <> "/staging"
      bundle = stage <> "/SnapcasterAudio.driver"
      executable = stage <> "/snapcaster"
      driver = bundle <> "/Contents/MacOS/SnapcasterAudio"
      output = source <> "/dist/snapcaster-" <> args.version <> "-macos-universal.tar.gz"
      arm = source <> "/target/aarch64-apple-darwin/release/"
      intel = source <> "/target/x86_64-apple-darwin/release/"
  S.run [ "mkdir", "-p", source <> "/dist", bundle <> "/Contents/MacOS" ]
  S.run [ "lipo", "-create", "-output", executable, arm <> "snapcaster", intel <> "snapcaster" ]
  S.run [ "cp", source <> "/driver/Info.plist", bundle <> "/Contents/Info.plist" ]
  S.run [ "lipo", "-create", "-output", driver, arm <> "libsnapcaster_driver.dylib", intel <> "libsnapcaster_driver.dylib" ]
  traverse_ (\binary -> S.run [ "lipo", "-verify_arch", "arm64", "x86_64", binary ]) [ executable, driver ]
  S.run [ "codesign", "--force", "--sign", "-", bundle ]
  S.run [ "codesign", "--verify", "--strict", bundle ]
  S.run [ "cp", source <> "/scripts/install-prebuilt.sh", stage <> "/install.sh" ]
  S.run [ "cp", source <> "/scripts/uninstall-driver.sh", stage <> "/uninstall.sh" ]
  S.run [ "cp", source <> "/dist/com.tsirysndr.snapcaster.plist", source <> "/README.md", source <> "/LICENSE", stage <> "/" ]
  S.run [ "chmod", "0755", stage <> "/install.sh", stage <> "/uninstall.sh" ]
  S.run [ "tar", "-C", stage, "-czf", output, "." ]
  S.checksum output
  S.run [ "lipo", "-info", executable, driver ]
