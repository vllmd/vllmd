# VLLMD Hypervisor Variables Reference

This document provides a comprehensive reference for all variables used in the VLLMD Hypervisor system, including both configuration file variables and environment variables.

## Overview

The VLLMD Hypervisor uses two main types of variables:

1. **Configuration Variables**: Defined in TOML configuration files
2. **Environment Variables**: Set in the shell environment or systemd service files

## Configuration Variables

These variables are defined in the TOML configuration files as described in the [VLLMD Hypervisor Configuration Schema](SCHEMA_README.md).

### Global Section

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `user` | string | Current user | Username for systemd services |
| `state_dir` | string | `$HOME/.local/state/vllmd-hypervisor` | Directory path for state data |
| `config_dir` | string | `$HOME/.config/vllmd` | Directory path for configuration files |
| `default_memory_gb` | integer | 16 | Default memory allocation in GB for runtimes |
| `default_cpus` | integer | 4 | Default CPU allocation for runtimes |

### Runtime Section

Each runtime is defined as an array element with these variables:

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `index` | integer | (required) | Unique index for the runtime (min: 1) |
| `name` | string | (required) | Descriptive name for the runtime |
| `gpus` | array | [] | Array of GPU PCI addresses |
| `memory_gb` | integer | From global | Memory allocation in GB |
| `cpus` | integer | From global | Number of CPU cores |

### Network Section

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `default_interface` | string | First active interface | Default host network interface |
| `bridge_name` | string | `vllmd-br0` | Name of the bridge interface |

## Environment Variables

Environment variables provide runtime configuration options without modifying the configuration files. They generally take precedence over configuration file settings.

### Core Environment Variables

| Variable | Default | Description | Used By |
|----------|---------|-------------|---------|
| `VLLMD_HYPERVISOR_CONFIG` | `$HOME/.config/vllmd/config.toml` | Path to the main configuration file | All scripts |
| `VLLMD_HYPERVISOR_STATE_DIR` | `$HOME/.local/state/vllmd-hypervisor` | Directory for runtime state data | All scripts |
| `VLLMD_HYPERVISOR_LOG_LEVEL` | `INFO` | Logging verbosity (DEBUG, INFO, WARN, ERROR) | All scripts |
| `VLLMD_HYPERVISOR_DRY_RUN` | `false` | If set to true, scripts perform validation without changes | Installation scripts |

### Virtualization Settings

| Variable | Default | Description | Used By |
|----------|---------|-------------|---------|
| `VLLMD_KVM_GROUP` | `kvm` | Group name for KVM permissions | precheck-vllmd-hypervisor.sh |
| `VLLMD_HUGEPAGES_SIZE` | `2M` | Size of hugepages (2M or 1G) | initialize-vllmd-hypervisor.sh |
| `VLLMD_DISABLE_NESTED_VIRT` | `false` | If set to true, disables nested virtualization check | precheck-vllmd-hypervisor.sh |

### Network Configuration

| Variable | Default | Description | Used By |
|----------|---------|-------------|---------|
| `VLLMD_BRIDGE_NAME` | `vllmd-br0` | Name of the network bridge interface | initialize-vllmd-hypervisor.sh |
| `VLLMD_HOST_INTERFACE` | First active interface | Host interface to bridge with VM interfaces | initialize-vllmd-hypervisor.sh |
| `VLLMD_DISABLE_NETWORK` | `false` | If set to true, skips network configuration | initialize-vllmd-hypervisor.sh |

### Systemd Integration

| Variable | Default | Description | Used By |
|----------|---------|-------------|---------|
| `VLLMD_SYSTEMD_USER` | Current user | Username for systemd services | install-vllmd-hypervisor-systemd.sh |
| `VLLMD_SYSTEMD_DIR` | `/etc/systemd/system` | Directory for systemd service files | install-vllmd-hypervisor-systemd.sh |
| `VLLMD_RUNTIME_TEMPLATE` | Template from package | Custom systemd service template | install-vllmd-hypervisor-systemd.sh |

### Cloud-Init Configuration

| Variable | Default | Description | Used By |
|----------|---------|-------------|---------|
| `VLLMD_CLOUD_INIT_USER` | Current user | Username for cloud-init user-data | generate-init-vllmd-hypervisor.sh |
| `VLLMD_SSH_KEY_PATH` | `$HOME/.ssh/id_rsa.pub` | SSH public key for VM access | generate-init-vllmd-hypervisor.sh |
| `VLLMD_CLOUD_IMAGE` | Ubuntu 22.04 | Base cloud image for VM creation | generate-init-vllmd-hypervisor.sh |

## Variable Relationship

The following diagram shows the relationship between configuration variables and environment variables:

```
┌─────────────────────────┐      ┌─────────────────────────┐
│                         │      │                         │
│  Environment Variables  │──┐   │  Configuration Files    │
│  (Higher Precedence)    │  │   │  (Lower Precedence)     │
│                         │  │   │                         │
└─────────────────────────┘  │   └─────────────────────────┘
                             │                  │
                             │                  │
                             ▼                  ▼
                       ┌─────────────────────────────┐
                       │                             │
                       │    Runtime Configuration    │
                       │                             │
                       └─────────────────────────────┘
```

## Usage Examples

### Configuration File Example

```toml
# VLLMD Hypervisor Configuration

[global]
user = "sdake"
state_dir = "/home/sdake/.local/state/vllmd-hypervisor"
config_dir = "/home/sdake/.config/vllmd"
default_memory_gb = 32
default_cpus = 8

[[runtimes]]
index = 1
name = "vllm-inference-1"
gpus = ["0000:01:00.0"]
memory_gb = 64
cpus = 16

[[runtimes]]
index = 2
name = "vllm-inference-2"
gpus = ["0000:02:00.0"]
# Uses default memory and CPU settings

[network]
default_interface = "eth0"
bridge_name = "vllmd-br0"
```

### Environment Variable Usage

```bash
# Use a custom configuration file
export VLLMD_HYPERVISOR_CONFIG=$HOME/my-custom-config.toml
./precheck-vllmd-hypervisor.sh

# Perform a dry run of the installation
export VLLMD_HYPERVISOR_DRY_RUN=true
./install-vllmd-hypervisor-systemd.sh

# Use 1GB hugepages instead of the default 2MB
export VLLMD_HUGEPAGES_SIZE=1G
./initialize-vllmd-hypervisor.sh
```

## Best Practices

1. Use configuration files for persistent settings
2. Use environment variables for temporary overrides or testing
3. Keep all runtime-specific settings in the configuration file
4. Use descriptive names for runtimes
5. Set appropriate resource limits based on your hardware
6. Document any new variables in this reference guide

## Maintenance Notes

When adding new variables:

1. Document them in this file
2. Provide sensible defaults
3. Add validation in the relevant scripts
4. Consider backward compatibility
5. Use the VLLMD_HYPERVISOR prefix for all environment variables