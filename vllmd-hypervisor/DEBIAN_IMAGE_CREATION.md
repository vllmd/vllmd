# Debian VM Image Creation for VLLMD Hypervisor

This document describes how to create a Debian VM image for use with VLLMD Hypervisor. The image is generated using a preseed configuration and cloud-hypervisor-v44, resulting in a fully automated installation process.

## Prerequisites

Before using the image generation tool, ensure you have the following dependencies installed:

- cloud-hypervisor-v44 - For running the VM during installation
- dosfstools - For creating the FAT filesystem (provides mkdosfs at /usr/sbin/mkdosfs)
- mtools - For manipulating the FAT filesystem (provides mcopy at /usr/bin/mcopy)
- coreutils - For creating the disk image (provides truncate)
- curl - For downloading the Debian installer files (/usr/bin/curl)
- iproute2 - For network configuration (provides ip command at /usr/sbin/ip or /sbin/ip)
- iptables - For network forwarding rules

You can install these dependencies on a Debian-based system with:

```bash
sudo apt update
sudo apt install dosfstools mtools coreutils curl iproute2 iptables
# Install cloud-hypervisor-v44 from your preferred source
```

## Usage

The `generate-debian-image.sh` script creates a Debian VM image with the following steps:

1. Downloads the Debian netinst ISO to a cache location
2. Creates a preseed configuration disk with timestamp
3. Creates a raw disk image
4. Sets up macvtap networking for VM connectivity
5. Runs cloud-hypervisor-v44 to install Debian using the preseed configuration

### Basic Usage

```bash
bash generate-debian-image.sh
```

This will create a Debian Bookworm VM image with default settings.

### Advanced Options

The script supports several options to customize the image generation process:

```bash
bash generate-debian-image.sh [OPTIONS]
```

Options:
- `--dry-run`: Show what would be done without making any changes
- `--force`: Force overwrite of existing files
- `--state-dir=PATH`: Set custom state directory (default: $HOME/.local/state/vllmd/vllmd-hypervisor)
- `--output=PATH`: Set custom output path for the VM image
- `--memory=SIZE`: Memory size for installation VM (default: 16G)
- `--disk-size=SIZE`: Size of the output disk image (default: 20G)
- `--debian-version=VER`: Debian version to install (default: bookworm)
- `--preseed=PATH`: Path to custom preseed file (default: use built-in preseed-v1-bookworm.cfg)

## Preseed Configuration

The script uses a predefined preseed configuration file (`preseed-v1-bookworm.cfg`) with these settings:

- **SSH Configuration**:
  - Permits root login via SSH
  - Enables password authentication for SSH

- **Localization**:
  - US English locale
  - US keyboard layout

- **Network**:
  - Automatic interface selection
  - Hostname: vllmd-hypervisor-runtime
  - Domain: vllmd.com
  - DHCP enabled for network configuration
  - NTP service enabled
  - Uses systemd-networkd for network management
  - Configures all ethernet interfaces (en*) for DHCP

- **Package Mirrors**:
  - HTTP protocol
  - Uses http.us.debian.org mirror
  - Enables security and update repositories

- **Account Setup**:
  - Disables root login
  - Sets up a user with full name "Steven Dake <steve@vllmd.com>"
  - Creates a default password
  - Adds user to sudo group

- **Time Settings**:
  - UTC timezone
  - NTP enabled for time synchronization

- **Partitioning**:
  - XFS filesystem
  - Regular partitioning method
  - Atomic recipe (single partition)
  - GPT partition table
  - Uses /dev/vdc as installation target during installation
  - Will be /dev/sda when running in the hypervisor

- **Boot Configuration**:
  - GRUB2 bootloader
  - Serial console enabled (tty1 and ttyS0,115200)

- **Packages**:
  - Standard system utilities
  - SSH server
  - Cloud-init, sudo, curl, open-iscsi, libopeniscsiusr, openssh-server, neovim, ssh-import-id
  - Full system upgrade during installation

- **Post-installation**:
  - Configures GRUB for serial console access
  - Sets up sudo access for the user
  - Removes traditional network interfaces file
  - Configures systemd-networkd for network management
  - Enables and starts systemd-networkd

## Integration with VLLMD Hypervisor

After generating the Debian VM image, you can use it with VLLMD Hypervisor:

1. Place the image in a location accessible to VLLMD Hypervisor
2. Update your VLLMD Hypervisor configuration to use this image as the source image
3. Start VMs using this base image

Example:

```bash
# Generate the image
bash generate-debian-image.sh --output=$HOME/.local/share/vllmd/vllmd-hypervisor/images/vllmd-hypervisor-runtime.raw

# Use the image in the VLLMD Hypervisor configuration
VLLMD_HYPERVISOR_SOURCE_REFERENCE_RAW_FILEPATH="$HOME/.local/share/vllmd/vllmd-hypervisor/images/vllmd-hypervisor-runtime.raw"

# Initialize VLLMD Hypervisor with the new image
bash initialize-vllmd-hypervisor.sh
```

## How It Works

The script performs the following steps to create the VM image:

1. **Preparation**:
   - Validates prerequisites
   - Creates necessary directories with timestamp-based naming
   - Sets up configuration

2. **Downloading the Installer**:
   - Retrieves the Debian netinst ISO (debian-12.9.0-amd64-netinst.iso)
   - Stores the ISO in a cache directory for reuse
   - Reuses existing ISO if found to save bandwidth

3. **Creating the Preseed Disk**:
   - Creates a FAT-formatted disk image with volume label "VLLM_PRES"
   - Uses a timestamp in the preseed disk filename for uniqueness
   - Adds the preseed configuration file to this image
   - Verifies that the preseed file is correctly written

4. **Network Configuration**:
   - Sets up macvtap networking on the host's default network interface
   - Creates a macvtap device with MAC address "52:54:00:12:34:56"
   - Configures file permissions for the tap device

5. **Creating the Disk Image**:
   - Creates an empty raw disk image of the specified size using truncate
   - Names the file with a timestamp for easier management

6. **Running the Installation**:
   - Launches cloud-hypervisor-v44 with:
     - The downloaded netinst ISO
     - The preseed configuration disk as a secondary disk
     - The target disk image
     - 4 CPUs for the installation VM
     - Properly configured serial console
     - Macvtap networking for internet connectivity

7. **Cleanup**:
   - Automatically removes the macvtap device after installation
   - Cleans up temporary files (preserves cached ISO)

## Generated Resources and Binaries

The script generates and uses the following resources:

1. **Directories**:
   - Timestamp-based state directory (`$HOME/.local/state/vllmd/vllmd-hypervisor/$TIMESTAMP-build`)
   - Cache directory for ISO (`$HOME/.cache/vllmd/vllmd-hypervisor`)
   - Image storage directory (`$HOME/.local/share/vllmd/vllmd-hypervisor/images`)

2. **Files**:
   - Cached Debian netinst ISO (`$HOME/.cache/vllmd/vllmd-hypervisor/debian-netinst.iso`)
   - Generated preseed disk image (`$BUILD_DIR/$TIMESTAMP-preseed.img`)
   - VM disk image (`$STATE_DIR/$TIMESTAMP-vllmd-hypervisor-runtime.raw` or custom path with `--output`)

3. **Network Resources**:
   - Temporary macvtap device (macvtap0)
   - Tap device file (/dev/tap*)

4. **Installed Debian VM Components**:
   - XFS-formatted filesystem on a GPT partition table
   - GRUB2 bootloader configured for serial console
   - User with sudo access
   - Systemd-networkd configuration for network interfaces
   - Required packages for VM operation

5. **Binaries Used**:
   - `cloud-hypervisor-v44` - For running the VM
   - `/usr/sbin/mkdosfs` - For creating the FAT filesystem
   - `/usr/bin/mcopy` - For copying files to the FAT filesystem
   - `/usr/bin/mdir` - For verifying files on the FAT filesystem
   - `truncate` - For creating the disk image
   - `/usr/bin/curl` - For downloading the Debian ISO
   - `/usr/sbin/ip` or `/sbin/ip` - For network configuration
   - `sudo` - For operations requiring elevated privileges
   - `rm` - For removing files
   - `mkdir` - For creating directories
   - `find` - For finding existing files
   - `cat` - For reading system information
   - `chmod` - For changing file permissions

## Troubleshooting

### Installation Fails

If the installation fails, try:

1. Running with `--dry-run` to verify configurations
2. Checking if macvtap devices are already in use (they will be removed and recreated)
3. Ensuring network connectivity for downloading packages
4. Verifying that the default network interface is properly detected

### Network Issues

If you encounter network issues during installation:

1. Make sure your host has a valid internet connection
2. Check that your default network interface is properly detected
3. Ensure you have proper permissions to create macvtap devices (may require sudo)
4. Verify that the tap device permissions are set correctly (the script uses chmod 666)

### Cloud-Hypervisor Issues

If you encounter issues with cloud-hypervisor-v44:

1. Verify that cloud-hypervisor-v44 is installed and accessible
2. Check that you're using version 44 specifically, as the script is optimized for this version
3. Review installation logs for errors