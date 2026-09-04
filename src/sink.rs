//! PCM sinks.
//!
//! Every sink is just a byte pipe: the same raw PCM works for a Snapcast
//! `tcp://` / `pipe://` stream source and for a SlimProto server like squeezed
//! (`tcp` / `unix` input). The writer thread reconnects forever, discarding
//! audio while the sink is down so capture never blocks.

use anyhow::{Context, bail};
use std::io::Write;
use std::net::TcpStream;
use std::os::unix::net::UnixStream;
use std::sync::mpsc::Receiver;
use std::time::Duration;

const RECONNECT_DELAY: Duration = Duration::from_secs(2);

#[derive(Debug, Clone)]
pub enum Sink {
    /// Connect to a listening TCP server (snapserver tcp source, squeezed tcp input).
    Tcp(String),
    /// Connect to a listening unix socket (e.g. squeezed unix input).
    Unix(String),
    /// Open a FIFO for writing (e.g. snapserver's /tmp/snapfifo).
    Pipe(String),
}

impl Sink {
    pub fn parse(uri: &str) -> anyhow::Result<Self> {
        if let Some(addr) = uri.strip_prefix("tcp://") {
            if addr.is_empty() {
                bail!("tcp sink needs host:port, e.g. tcp://127.0.0.1:4953");
            }
            Ok(Sink::Tcp(addr.to_string()))
        } else if let Some(path) = uri.strip_prefix("unix://") {
            Ok(Sink::Unix(path.to_string()))
        } else if let Some(path) = uri.strip_prefix("pipe://") {
            Ok(Sink::Pipe(path.to_string()))
        } else {
            bail!("unsupported sink {uri:?} — use tcp://host:port, unix:///path or pipe:///path");
        }
    }

    pub fn describe(&self) -> String {
        match self {
            Sink::Tcp(addr) => format!("tcp://{addr}"),
            Sink::Unix(path) => format!("unix://{path}"),
            Sink::Pipe(path) => format!("pipe://{path}"),
        }
    }

    fn connect(&self) -> anyhow::Result<Box<dyn Write + Send>> {
        match self {
            Sink::Tcp(addr) => {
                let stream = TcpStream::connect(addr)
                    .with_context(|| format!("connecting to tcp://{addr}"))?;
                stream.set_nodelay(true).ok();
                Ok(Box::new(stream))
            }
            Sink::Unix(path) => {
                let stream = UnixStream::connect(path)
                    .with_context(|| format!("connecting to unix://{path}"))?;
                Ok(Box::new(stream))
            }
            Sink::Pipe(path) => {
                // Opening a FIFO for writing blocks until a reader (snapserver)
                // opens the other end — that is the behavior we want.
                let file = std::fs::OpenOptions::new()
                    .write(true)
                    .open(path)
                    .with_context(|| format!("opening FIFO {path} for writing"))?;
                Ok(Box::new(file))
            }
        }
    }
}

/// Drain PCM chunks from `rx` into the sink, reconnecting on failure.
/// Runs until the capture side hangs up.
pub fn run_writer(sink: Sink, rx: Receiver<Vec<u8>>) {
    loop {
        let mut conn = match sink.connect() {
            Ok(conn) => {
                tracing::info!("sink: connected to {}", sink.describe());
                conn
            }
            Err(e) => {
                tracing::warn!("sink: {e:#}; retrying in {RECONNECT_DELAY:?}");
                // Keep draining while down so the capture channel never backs up.
                let deadline = std::time::Instant::now() + RECONNECT_DELAY;
                while let Ok(_) =
                    rx.recv_timeout(deadline.saturating_duration_since(std::time::Instant::now()))
                {
                }
                continue;
            }
        };
        loop {
            match rx.recv() {
                Ok(chunk) => {
                    if let Err(e) = conn.write_all(&chunk) {
                        tracing::warn!("sink: write failed ({e}); reconnecting");
                        break;
                    }
                }
                Err(_) => {
                    tracing::info!("sink: capture ended, closing");
                    return;
                }
            }
        }
    }
}
