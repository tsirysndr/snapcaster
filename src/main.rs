//! `snapcaster` — redirect macOS audio to Snapcast or Squeezebox.
//!
//! A HAL virtual driver (see `driver/`) publishes a "Snapcaster" output device.
//! Whatever macOS plays to it is looped back to the device's input, captured
//! here, converted to raw PCM, and pushed to a Snapcast server, a SlimProto
//! server (e.g. squeezed), a unix socket, or a FIFO.

#[cfg(not(target_os = "macos"))]
compile_error!("snapcaster only supports macOS — it is built on the Core Audio HAL");

mod capture;
mod cli;
mod sink;

use clap::Parser;
use cli::{Cli, Command};
use sink::Sink;
use std::sync::mpsc;

fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();
    init_tracing();

    match cli.command {
        Some(Command::Devices) => capture::list_devices(),
        None => stream(cli.stream),
    }
}

fn stream(args: cli::StreamArgs) -> anyhow::Result<()> {
    if args.bits != 16 && args.bits != 32 {
        anyhow::bail!("--bits must be 16 or 32");
    }
    if ![44100, 48000, 88200, 96000].contains(&args.sample_rate) {
        anyhow::bail!("--sample-rate must be 44100, 48000, 88200 or 96000");
    }
    let sink = Sink::parse(&args.sink)?;
    let device = capture::find_device(&args.device)?;

    // Keep only a few chunks between the audio thread and the writer so a brief
    // sink stall can't build a latency backlog; beyond this we drop.
    let (tx, rx) = mpsc::sync_channel::<Vec<u8>>(8);
    let cap = capture::start(&device, args.sample_rate, args.bits, tx)?;

    tracing::info!(
        "snapcaster {}: capturing {:?} at {} Hz / {} ch / {}-bit → {}",
        env!("CARGO_PKG_VERSION"),
        args.device,
        cap.sample_rate,
        cap.channels,
        args.bits,
        sink.describe(),
    );
    tracing::info!(
        "server sampleformat must match: snapserver `sampleformat={}:{}:{}`, \
         squeezed `--sample-rate {} --bits {} --channels {}`",
        cap.sample_rate,
        args.bits,
        cap.channels,
        cap.sample_rate,
        args.bits,
        cap.channels,
    );
    tracing::info!("select 'Snapcaster' as the output device in System Settings → Sound");

    // The writer owns reconnection; when it returns the capture ended.
    sink::run_writer(sink, rx);
    Ok(())
}

fn init_tracing() {
    use tracing_subscriber::{EnvFilter, fmt};
    let filter = EnvFilter::try_from_env("SNAPCASTER_LOG")
        .or_else(|_| EnvFilter::try_new("info"))
        .unwrap();
    fmt().with_env_filter(filter).with_target(false).init();
}
