# VLLMD Hypervisor Environment Variables

This document defines the environment variables used by the VLLMD Hypervisor system. These variables provide runtime configuration options without modifying the configuration files.

## Core Environment Variables

| Variable | Default | Description | Used By |
|----------|---------|-------------|---------|
| `VLLMD_HYPERVISOR_CONFIG` | `$HOME/.config/vllmd/config.toml` | Path to the main configuration file | All scripts |
| `VLLMD_HYPERVISOR_STATE_DIR` | `$HOME/.local/state/vllmd-hypervisor` | Directory for runtime state data | All scripts |
| `VLLMD_HYPERVISOR_LOG_LEVEL` | `INFO` | Logging verbosity (DEBUG, INFO, WARN, ERROR) | All scripts |
| `VLLMD_HYPERVISOR_DRY_RUN` | `false` | If set to true, scripts perform validation without changes | Installation scripts |

## Virtualization Settings

| Variable | Default | Description | Used By |
|----------|---------|-------------|---------|
| `VLLMD_KVM_GROUP` | `kvm` | Group name for KVM permissions | precheck-vllmd-hypervisor.sh |
| `VLLMD_HUGEPAGES_SIZE` | `2M` | Size of hugepages (2M or 1G) | initialize-vllmd-hypervisor.sh |
| `VLLMD_DISABLE_NESTED_VIRT` | `false` | If set to true, disables nested virtualization check | precheck-vllmd-hypervisor.sh |

## Network Configuration

| Variable | Default | Description | Used By |
|----------|---------|-------------|---------|
| `VLLMD_BRIDGE_NAME` | `vllmd-br0` | Name of the network bridge interface | initialize-vllmd-hypervisor.sh |
| `VLLMD_HOST_INTERFACE` | First active interface | Host interface to bridge with VM interfaces | initialize-vllmd-hypervisor.sh |
| `VLLMD_DISABLE_NETWORK` | `false` | If set to true, skips network configuration | initialize-vllmd-hypervisor.sh |

## Systemd Integration

| Variable | Default | Description | Used By |
|----------|---------|-------------|---------|
| `VLLMD_SYSTEMD_USER` | Current user | Username for systemd services | install-vllmd-hypervisor-systemd.sh |
| `VLLMD_SYSTEMD_DIR` | `/etc/systemd/system` | Directory for systemd service files | install-vllmd-hypervisor-systemd.sh |
| `VLLMD_RUNTIME_TEMPLATE` | Template from package | Custom systemd service template | install-vllmd-hypervisor-systemd.sh |

## Cloud-Init Configuration

| Variable | Default | Description | Used By |
|----------|---------|-------------|---------|
| `VLLMD_CLOUD_INIT_USER` | Current user | Username for cloud-init user-data | generate-init-vllmd-hypervisor.sh |
| `VLLMD_SSH_KEY_PATH` | `$HOME/.ssh/id_rsa.pub` | SSH public key for VM access | generate-init-vllmd-hypervisor.sh |
| `VLLMD_CLOUD_IMAGE` | Ubuntu 22.04 | Base cloud image for VM creation | generate-init-vllmd-hypervisor.sh |

## Usage Examples

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

# Change the bridge name
export VLLMD_BRIDGE_NAME=custom-bridge
./initialize-vllmd-hypervisor.sh
```

## Variable Scope and Persistence

Environment variables take precedence over configuration file settings, but are not persisted between runs unless exported in a shell startup file or systemd service environment.

For permanent changes, prefer updating the configuration file instead of relying on environment variables.

## Maintenance Notes

When adding new environment variables:

1. Document them in this file
2. Provide sensible defaults
3. Add validation in the relevant scripts
4. Consider backward compatibility
5. Use the VLLMD_HYPERVISOR prefix for all variables