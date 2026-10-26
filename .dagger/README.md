# snapcaster CI with PureScript Dagger

GitHub release creation and artifact uploads. Universal binary compilation, lipo, driver assembly and codesigning remain in the existing macOS job. The commented-out Homebrew job remains disabled.

The workflows use Dagger **v1.0.0-beta.21** and the vendored PureScript SDK.
The module lives in `ci/src/`; `Main.purs` exposes typed functions and `CI/`
contains the implementation. Small shell scripts handle native package tools.
Images are pinned in the root `dagger.lock`.

## Run a function

From the repository root, install the checksum-verified CLI, then enter the
workspace. The installer supports Linux and macOS, x86_64 and ARM64.

```sh
bash .dagger/install-dagger.sh
export PATH="$PWD/.dagger/bin:$PATH"
cd .dagger
export GH_TOKEN="..." # a token with contents:write for this repository
# dist/ must already contain the artifacts produced by the macOS job.
dagger api call -m ci publish-release --assets ../dist --tag v0.1.0 \
  --token env://GH_TOKEN --run-id "manual-$(date +%s)"
```

## Develop the pipeline

Dagger installs Node 22, PureScript 0.15.16 and Spago 1.0.5 **inside the SDK
runtime container**, under `/usr/local`; Spago's dependency cache is under
`/root/.cache/spago-nodejs`. Module compilation happens under `/src`. You only
need the Dagger CLI and a supported engine/container runtime on the host.

For a fast type check without starting Dagger, install PureScript and Spago on
your development machine, then run `spago build --strict` in `.dagger/ci`.
The committed bindings and Spago lockfile make this independent of codegen.
Run `node --test .dagger/tests/*.test.mjs` from the repository root for
SDK HTTP deadline/error and isolated release-upload regression checks. To intentionally regenerate
bindings, run `python3 .dagger/generate.py`; this starts Dagger and stages only
the pipeline workspace, not the application tree.

See [SDK provenance and local patches](sdk/purescript/VENDORED.md) before
updating the vendored SDK. Retain its LICENSE, NOTICE and schema license.

The migration was checked with strict PureScript compilation, workflow lint,
shell syntax checks and SDK transport tests. Full Dagger builds and publishing
were deliberately left to GitHub Actions; they were not run locally.
