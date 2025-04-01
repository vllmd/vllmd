# VLLMD Hypervisor

`VLLMD-hypervisor`: Purpose-built hypervisor for secure machine learning inference workloads. This implementation uses the [Cloud Hypervisor](https://github.com/cloud-hypervisor/cloud-hypervisor) library directly for maximum performance and reliability, focusing on environment-variable driven configuration.

## Purpose

`VLLMD` Hypervisor is a purpose built inference virtualized environment that provides a command-line interface for virtualized environment lifecycle management with a strong focus on minimalism. The primary benefits are:

- Simplified systemd integration (`systemctl status` shows only `vllmd-hypervisor` as a single command).
- Environment variable-based configuration instead of verbose command-line arguments.
- Self-contained binary that handles all lifecycle operations (`start`, `stop`, `status`).
- Direct integration with virtualization technology without shell-out operations.

## Environment variables

The `vllmd-hypervisor` is configured using the following environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `VLLMD_HYPERVISOR_KERNEL_FILEPATH` | Path to kernel/firmware file | Required |
| `VLLMD_HYPERVISOR_SYSTEM_IMAGE_FILEPATH` | Path to primary disk image | Required |
| `VLLMD_HYPERVISOR_CONFIG_IMAGE_FILEPATH` | Path to config disk image (readonly) | Required |
| `VLLMD_HYPERVISOR_CPU_COUNT` | Number of vCPUs to allocate | 4 |
| `VLLMD_HYPERVISOR_MEMORY_CONFIG` | Memory configuration | "size=16G,shared=on" |
| `VLLMD_HYPERVISOR_DEVICE_FILEPATH_LIST` | Comma-separated list of device paths for passthrough | Empty |
| `VLLMD_HYPERVISOR_CMDLINE` | Kernel command line arguments | Empty |
| `VLLMD_HYPERVISOR_LOG_FILEPATH` | Path to log file | /dev/stdout |
| `VLLMD_HYPERVISOR_DEBUG` | Enable debug logging when set | Disabled |

## Commands

The hypervisor supports the following commands:

- `vllmd-hypervisor start`. Start the virtualized environment with the provided configuration.
- `vllmd-hypervisor stop`. Gracefully shut down the virtualized environment.
- `vllmd-hypervisor status`. Check if the virtualized environment is running and display its status.

## Usage in systemd

Example systemd unit file:

```ini
[Unit]
Description=VLLMD Runtime %i

[Service]
Slice=vllmd.slice
Type=simple
Environment=VLLMD_HYPERVISOR_LOG_FILEPATH=%h/.local/log/vllmd/%i.log
EnvironmentFile=%h/.config/vllmd/hypervisor-%i.env

ExecStart=/path/to/vllmd-hypervisor start
ExecStop=/path/to/vllmd-hypervisor stop

Restart=on-failure
RestartSec=5
TimeoutStartSec=300
TimeoutStopSec=30

[Install]
WantedBy=default.target
```

The environment file should contain the required configuration variables.

## Building

### Prerequisites

- Linux with virtualized environment support.
- Rust 2021 edition or newer.
- Required environment variables set.

### Build from source

#### Standard Build

```bash
cargo build --release
```

The binary is emitted to: `target/release/vllmd-hypervisor`.

#### Static Binary Build with musl

For deployment in environments where shared libraries might be unavailable or to create a fully self-contained binary, you can build a static binary using musl:

1. Install the musl target:

```bash
rustup target add x86_64-unknown-linux-musl
```

2. Install musl development tools (on Debian/Ubuntu):

```bash
sudo apt-get install musl-tools
```

3. Build the static binary:

```bash
cargo build --release --target x86_64-unknown-linux-musl
```

The static binary will be emitted to: `target/x86_64-unknown-linux-musl/release/vllmd-hypervisor`

Benefits of static compilation:
- Self-contained binary with no external dependencies
- Can be deployed to any Linux environment regardless of shared library availability
- Ideal for containers and minimal environments
- Simpler deployment process with just a single file

Note: Building with musl may require additional setup for certain dependencies. See the [Rust Embedded Book](https://docs.rust-embedded.org/book/intro/install/linux.html) for more details.

## Features

This implementation supports the core features needed for running specialized virtualized environments:

- Accelerator device passthrough.
- Multiple system and config disks.
- Kenrel and command-line.
- Flexible memory configuration.
- Lifecycle management. (`vllmd-hypervisor start`, `vllmd-hypervisor stop`, `vllmd-hypervisor status`).
- Logging to multiple destinations.

## Example: Starting a virtualized environment

```bash
export VLLMD_HYPERVISOR_KERNEL_FILEPATH=/path/to/kernel
export VLLMD_HYPERVISOR_SYSTEM_IMAGE_FILEPATH=/path/to/image.img
export VLLMD_HYPERVISOR_CONFIG_IMAGE_FILEPATH=/path/to/config.img
export VLLMD_HYPERVISOR_DEVICE_FILEPATH_LIST=/dev/vfio/10
export VLLMD_HYPERVISOR_CPU_COUNT=8
export VLLMD_HYPERVISOR_MEMORY_CONFIG="size=32G,shared=on"
export VLLMD_HYPERVISOR_LOG_FILEPATH=/var/log/vllmd-hypervisor.log

./vllmd-hypervisor start
```
