//! Core Audio capture from the Snapcaster virtual device.
//!
//! The HAL driver loops everything played to the "Snapcaster" output back to
//! its input stream; we open that input with cpal and convert the f32 frames
//! to little-endian signed PCM for the sink.

use anyhow::{Context, bail};
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use std::sync::mpsc::SyncSender;

pub struct Capture {
    // Held so the Core Audio stream keeps running; dropped = stopped.
    _stream: cpal::Stream,
    pub sample_rate: u32,
    pub channels: u16,
}

pub fn find_device(name: &str) -> anyhow::Result<cpal::Device> {
    let host = cpal::default_host();
    host.input_devices()
        .context("enumerating input devices")?
        .find(|d| d.name().map(|n| n == name).unwrap_or(false))
        .with_context(|| {
            format!(
                "capture device {name:?} not found — install the virtual driver first: \
                 scripts/install-driver.sh"
            )
        })
}

/// Start capturing; converted PCM chunks are pushed to `tx`. If the sink can't
/// keep up the chunk is dropped rather than blocking the audio thread.
///
/// Requesting a `sample_rate` different from the device's current one makes
/// cpal set the device's nominal sample rate and wait for the switch, which
/// our HAL driver applies through RequestDeviceConfigurationChange.
pub fn start(
    device: &cpal::Device,
    sample_rate: u32,
    bits: u8,
    tx: SyncSender<Vec<u8>>,
) -> anyhow::Result<Capture> {
    let default = device
        .default_input_config()
        .context("querying device input format")?;
    if default.sample_format() != cpal::SampleFormat::F32 {
        bail!(
            "unexpected sample format {:?} from the virtual device (expected f32)",
            default.sample_format()
        );
    }
    let channels = default.channels();
    let config = cpal::StreamConfig {
        channels,
        sample_rate: cpal::SampleRate(sample_rate),
        buffer_size: cpal::BufferSize::Default,
    };

    let stream = device
        .build_input_stream(
            &config,
            move |data: &[f32], _| {
                let mut chunk = Vec::with_capacity(data.len() * (bits as usize / 8));
                match bits {
                    16 => {
                        for s in data {
                            let v = (s.clamp(-1.0, 1.0) * i16::MAX as f32) as i16;
                            chunk.extend_from_slice(&v.to_le_bytes());
                        }
                    }
                    _ => {
                        for s in data {
                            let v = (s.clamp(-1.0, 1.0) as f64 * i32::MAX as f64) as i32;
                            chunk.extend_from_slice(&v.to_le_bytes());
                        }
                    }
                }
                if tx.try_send(chunk).is_err() {
                    // Sink is down or slow; drop audio instead of blocking the
                    // realtime thread. The writer logs the reconnect story.
                }
            },
            |e| tracing::warn!("capture: stream error: {e}"),
            None,
        )
        .context("building input stream")?;
    stream.play().context("starting input stream")?;

    Ok(Capture {
        _stream: stream,
        sample_rate,
        channels,
    })
}

pub fn list_devices() -> anyhow::Result<()> {
    let host = cpal::default_host();
    println!("input devices:");
    for d in host.input_devices().context("enumerating input devices")? {
        if let Ok(name) = d.name() {
            println!("  {name}");
        }
    }
    println!("output devices:");
    for d in host
        .output_devices()
        .context("enumerating output devices")?
    {
        if let Ok(name) = d.name() {
            println!("  {name}");
        }
    }
    Ok(())
}
