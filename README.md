# snapcaster

**Turn your Mac's audio output into a [Snapcast](https://github.com/badaix/snapcast) or
Squeezebox stream.**

snapcaster installs a virtual audio output device named **Snapcaster** on macOS. Pick it in
*System Settings → Sound* like any other speaker, and everything your Mac plays — Spotify,
YouTube, system sounds, all of it — is forwarded as raw PCM to:

- a **Snapcast** server (`snapserver`), for synchronized multiroom audio on any snapclient,
- a **SlimProto** server such as [squeezed](https://github.com/tsirysndr/squeezed), which
  serves any Squeezelite / Squeezebox player,
- or any TCP socket, unix socket, or FIFO of your own.

> **macOS only.** snapcaster is built on the Core Audio HAL and supports nothing else, on
> purpose. On Linux, snapserver can read from ALSA/PipeWire directly.

## How it works

```
                 macOS apps (Spotify, browser, system sounds…)
                                   │  play to selected output
                                   ▼
                  ┌─────────────────────────────────┐
                  │  "Snapcaster" virtual device    │   HAL driver (driver/)
                  │  output stream ──► ring buffer  │   inside coreaudiod
                  │  input  stream ◄── (loopback)   │
                  └─────────────────────────────────┘
                                   │  captured with Core Audio
                                   ▼
                  ┌─────────────────────────────────┐
                  │  snapcaster CLI (this crate)    │   user space
                  │  f32 → s16le/s32le conversion   │
                  └─────────────────────────────────┘
                                   │  raw PCM bytes
                     ┌─────────────┼─────────────────┐
                     ▼             ▼                 ▼
              tcp://host:port  unix:///path    pipe:///path
              (snapserver,     (squeezed)      (/tmp/snapfifo)
               squeezed)
```

Two pieces, and the split is forced by macOS, not by taste:

1. **`driver/`** — a Core Audio HAL `AudioServerPlugIn` (Rust `cdylib` packaged as
   `SnapcasterAudio.driver`). It publishes the selectable output device and loops whatever is
   played into a hidden input stream. It runs inside `coreaudiod`, whose sandbox **forbids
   network access** — so the driver cannot talk to your server itself.
2. **`snapcaster` CLI** — a normal user-space process that opens the loopback input, converts
   the audio, and does the networking, with automatic reconnection.

## Installation

### Homebrew

```sh
brew install tsirysndr/tap/snapcaster
sudo snapcaster-install-driver   # installs the HAL driver into /Library, restarts coreaudiod
```

`brew install` puts the `snapcaster` CLI on your `PATH` and pulls in
[squeezed](https://github.com/tsirysndr/squeezed) as a dependency. The audio driver lives in
`/Library` and needs `sudo`, so it's a separate one-time step — `snapcaster-install-driver`
ad-hoc code-signs the bundle, installs it, and restarts coreaudiod. Remove it later with
`sudo snapcaster-uninstall-driver`.

### One-line install

```sh
curl -fsSL https://raw.githubusercontent.com/tsirysndr/snapcaster/main/install.sh | bash
```

This downloads the latest universal build from
[GitHub Releases](https://github.com/tsirysndr/snapcaster/releases), ad-hoc code-signs the
driver, installs it plus the `snapcaster` CLI, and restarts coreaudiod (it will prompt for
`sudo`). Pin a version with `SNAPCASTER_VERSION=v0.1.0` in front of the command. macOS only —
the script refuses to run on anything else.

### From a release tarball

Download `snapcaster-<version>-macos-universal.tar.gz` from the
[releases page](https://github.com/tsirysndr/snapcaster/releases), then:

```sh
tar -xzf snapcaster-*-macos-universal.tar.gz
cd snapcaster-*-macos-universal   # or wherever it extracted
./install.sh                      # installs driver + CLI, restarts coreaudiod (sudo)
```

The binaries are universal (Apple Silicon + Intel). Uninstall with `./uninstall.sh`.

### From source

Requirements: macOS, Rust (stable), `sudo` for the driver install.

```sh
git clone https://github.com/tsirysndr/snapcaster
cd snapcaster

# 1. Build + install the virtual audio driver, restart coreaudiod (sudo)
./scripts/install-driver.sh

# 2. Install the CLI
cargo install --path .
```

After step 1, **Snapcaster** appears as an output device in *System Settings → Sound* and in
the volume menu (⌥-click the menu bar icon). The driver is ad-hoc signed, which is fine for a
locally built install.

The first time the CLI runs, macOS shows a **microphone permission** prompt — that is the
capture side of the loopback device, not an actual microphone. Allow it or you'll get silence.

## Quick start

Snapcast server on another machine (e.g. `192.168.1.10`):

```sh
# on the server
snapserver   # with the [stream] config below

# on the Mac
snapcaster --sink tcp://192.168.1.10:4953
```

Then select **Snapcaster** as the output device and press play on anything.

## Usage

```
snapcaster [OPTIONS] [COMMAND]

Commands:
  devices   List audio devices visible to Core Audio

Options:
  -s, --sink <URI>         Sink for the PCM stream         [default: tcp://127.0.0.1:4953]
  -d, --device <NAME>      Capture device name             [default: Snapcaster]
  -b, --bits <BITS>        PCM depth, 16 or 32 (LE signed) [default: 16]
  -r, --sample-rate <HZ>   44100, 48000, 88200 or 96000    [default: 44100]
```

### Sink URIs

| URI                        | Meaning                                                        |
| -------------------------- | -------------------------------------------------------------- |
| `tcp://host:port`          | Connect to a listening TCP server (snapserver tcp source, squeezed tcp input) |
| `unix:///path/to.sock`     | Connect to a listening unix socket (squeezed unix input)       |
| `pipe:///path/to/fifo`     | Open a FIFO for writing (snapserver pipe source)               |

The stream is always **raw PCM, interleaved, little-endian signed**, 2 channels.
`--sample-rate` switches the virtual device to the requested rate (default 44100 Hz), so no
trip to Audio MIDI Setup is needed. snapcaster logs the exact format at startup; the
receiving server must be configured to match.

### Examples

```sh
# Snapcast, local server, defaults (tcp://127.0.0.1:4953, 44100:16:2)
snapcaster

# 48 kHz instead of the 44.1 kHz default
snapcaster --sample-rate 48000 --sink tcp://192.168.1.10:4953

# Snapcast on the network
snapcaster --sink tcp://192.168.1.10:4953

# Snapcast on the same Mac via FIFO
snapcaster --sink pipe:///tmp/snapfifo

# squeezed / Squeezebox players
snapcaster --sink tcp://192.168.1.10:4711
snapcaster --sink unix:///tmp/squeezed.sock

# 32-bit PCM instead of 16
snapcaster --bits 32 --sink tcp://192.168.1.10:4953

# verbose logging
SNAPCASTER_LOG=debug snapcaster
```

## Server configuration

### Snapcast (`snapserver`)

`sampleformat` must match what snapcaster logs at startup:

```ini
# /etc/snapserver.conf
[stream]
# snapcaster connects to this port:
source = tcp://0.0.0.0:4953?name=Snapcaster&mode=server&sampleformat=44100:16:2

# — or, same machine via FIFO —
source = pipe:///tmp/snapfifo?name=Snapcaster&sampleformat=44100:16:2
```

### squeezed (Squeezebox / Squeezelite)

```sh
squeezed --source tcp --tcp-bind 0.0.0.0:4711 \
         --sample-rate 44100 --bits 16 --channels 2

# — or via unix socket —
squeezed --source unix --path /tmp/squeezed.sock \
         --sample-rate 44100 --bits 16 --channels 2
```

## Run at login (launchd)

A LaunchAgent example ships in
[`dist/com.tsirysndr.snapcaster.plist`](dist/com.tsirysndr.snapcaster.plist). Edit its
`--sink` argument for your server, then:

```sh
cp dist/com.tsirysndr.snapcaster.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.tsirysndr.snapcaster.plist
```

It must be a **per-user LaunchAgent**, not a system LaunchDaemon: audio capture needs your
login session and the microphone permission granted to your user. Logs go to
`/tmp/snapcaster.log`; stop it with:

```sh
launchctl bootout gui/$(id -u)/com.tsirysndr.snapcaster
```

## Audio format details

- The virtual device runs 2 channels of 32-bit float internally.
- Supported sample rates: **44100 (default), 48000, 88200, 96000 Hz** — set with
  `--sample-rate`, which switches the device itself; remember to keep the server's
  `sampleformat` in sync.
- `--bits` converts to 16-bit (default) or 32-bit signed little-endian on the way out.
- The macOS volume slider, volume keys and mute work on the Snapcaster device and scale the
  audio *sent to the server* (applied in the driver with a perceptual s³ curve, -96..0 dB).
- Latency: the driver adds none of its own (zero latency / zero safety offset); end-to-end
  delay is dominated by the server's buffering (snapserver defaults to ~1 s for multiroom
  sync).

## Troubleshooting

**"Snapcaster" doesn't appear in Sound settings.**
Re-run `./scripts/install-driver.sh` and check the system log: open Console.app and search
for `Snapcaster driver` (the driver logs through syslog) or run
`log show --last 5m --predicate 'process == "coreaudiod"'`.

**The CLI says the capture device is not found.**
The driver isn't installed, or `coreaudiod` wasn't restarted. Run `snapcaster devices` — the
input list must contain `Snapcaster`.

**Connected, but the server plays silence.**
Snapcaster must be the *selected* output device, and the CLI needs microphone permission
(*System Settings → Privacy & Security → Microphone* — your terminal must be allowed).

**Audio is distorted / plays at the wrong speed.**
Sample-format mismatch. Make the server's `sampleformat` (or squeezed's
`--sample-rate/--bits/--channels`) match exactly what snapcaster logs at startup.

**Sink down?**
snapcaster keeps capturing, drops the audio, and retries the connection every 2 s — it logs
each reconnect.

## Uninstall

```sh
./scripts/uninstall-driver.sh                                  # driver + coreaudiod restart
launchctl bootout gui/$(id -u)/com.tsirysndr.snapcaster 2>/dev/null || true
cargo uninstall snapcaster
```

## Development

```sh
cargo build                              # CLI
cargo build --release -p snapcaster-driver   # HAL driver cdylib
./scripts/install-driver.sh              # assemble bundle + install + restart coreaudiod
```

Workspace layout:

```
src/            CLI: cli.rs (clap), capture.rs (cpal), sink.rs (tcp/unix/pipe writer)
driver/         HAL AudioServerPlugIn cdylib + Info.plist (CFPlugIn factory)
scripts/        install-driver.sh / uninstall-driver.sh
dist/           launchd LaunchAgent example
```

The driver is modeled on Apple's NullAudio sample / BlackHole: one device object, one output
and one input stream sharing a 16384-frame ring buffer, zero-timestamps derived from
`mach_absolute_time`, and sample-rate changes via the host's
`RequestDeviceConfigurationChange`.

One non-obvious detail: on current macOS the HAL delivers the mixed system output through the
`ProcessOutput` and `'rite'` IO operations, **not** `WriteMix`. The driver must return `true`
from `WillDoIOOperation` for those ops or macOS silently refuses to start the output IOProc
(output plays to nowhere and capture reads only silence). We capture the post-mix audio from
`WriteMix`/`'rite'` and merely accept `ProcessOutput` (it is per-stream pre-mix, so writing it
to the ring would drop other apps' audio when several play at once).

## License

MIT
