# Snapcaster PureScript CI

The release workflow calls `fluentci run ci macos-release` to build both macOS
architectures, assemble universal CLI and HAL-driver binaries, verify their CPU
slices, sign the driver, stage installer payloads, archive them, and compute the
checksum. All control flow is PureScript in `ci/src/CI/Snapcaster.purs`; commands
use literal argv. The workflow contains no build loops or packaging shell bodies.

Tooling is checked out at `github.workflow_sha` under `.ci-tooling`, while the
source checkout uses the selected release tag. Artifacts retain the existing
`snapcaster-VERSION-macos-universal.tar.gz` naming and installer layout. The
publishing job uploads selected release assets through the PureScript component.
It no longer installs or invokes Dagger.

The checks workflow compiles the component, tests its universal-build and
packaging contracts without invoking Cargo, lipo, or codesign, and lints the
workflows. The toolchain composite pins Node 24.13.1, Bun, PureScript and Spago,
and generates the local ignored SDK from FluentCI before building the component.

```sh
fluentci run ci macos-release --source . --version v0.1.0
```

The release command performs a real macOS build. Unit tests use a host stub;
GitHub uploads require the workflow's `GH_TOKEN` and contents-write permission.
