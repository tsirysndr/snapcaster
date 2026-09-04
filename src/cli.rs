//! Command-line interface (clap derive).

use clap::{Parser, Subcommand};

#[derive(Parser, Debug)]
#[command(
    name = "snapcaster",
    version,
    about = "Redirect macOS audio to a Snapcast or Squeezebox (SlimProto) server.",
    long_about = "snapcaster captures audio played to the 'Snapcaster' virtual output device \
(installed by scripts/install-driver.sh) and forwards it as raw PCM to a Snapcast server \
(tcp:// stream source), a SlimProto server such as squeezed (tcp:// / unix:// input), a unix \
socket, or a FIFO like /tmp/snapfifo. Select 'Snapcaster' as the system output device, then \
run `snapcaster` pointing at your server."
)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Option<Command>,

    #[command(flatten)]
    pub stream: StreamArgs,
}

#[derive(Subcommand, Debug)]
pub enum Command {
    /// List audio devices visible to Core Audio.
    Devices,
}

#[derive(Parser, Debug)]
pub struct StreamArgs {
    /// Where to send the PCM stream.
    ///
    /// snapcast:   tcp://127.0.0.1:4953   (snapserver `source = tcp://...` in server mode)
    ///             pipe:///tmp/snapfifo   (snapserver `source = pipe:///tmp/snapfifo`)
    /// squeezebox: tcp://127.0.0.1:4711   (squeezed `--source tcp --tcp-bind 0.0.0.0:4711`)
    ///             unix:///tmp/squeezed.sock (squeezed `--source unix --path ...`)
    #[arg(
        short,
        long,
        value_name = "URI",
        default_value = "tcp://127.0.0.1:4953",
        verbatim_doc_comment
    )]
    pub sink: String,

    /// Name of the virtual capture device to record from.
    #[arg(short, long, value_name = "NAME", default_value = "Snapcaster")]
    pub device: String,

    /// PCM bit depth sent to the sink (16 or 32, little-endian signed).
    #[arg(short, long, value_name = "BITS", default_value_t = 16)]
    pub bits: u8,

    /// Sample rate in Hz; the virtual device is switched to this rate
    /// (44100, 48000, 88200 or 96000).
    #[arg(short = 'r', long, value_name = "HZ", default_value_t = 44100)]
    pub sample_rate: u32,
}
