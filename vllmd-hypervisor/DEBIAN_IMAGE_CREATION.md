# Debian VM Image Creation for VLLMD Hypervisor

This document describes how to create a Debian VM image for use with VLLMD Hypervisor. The image is generated using a preseed configuration and cloud-hypervisor, resulting in a fully automated installation process.

## Prerequisites

Before using the image generation tool, ensure you have the following dependencies installed:

- cloud-hypervisor - For running the VM during installation
- dosfstools - For creating the FAT filesystem (provides mkdosfs)
- mtools - For manipulating the FAT filesystem (provides mcopy)
- coreutils - For creating the disk image (provides truncate)
- wget - For downloading the Debian installer files

You can install these dependencies on a Debian-based system with:

```bash
sudo apt update
sudo apt install dosfstools mtools coreutils wget
# Install cloud-hypervisor from your preferred source
```

## Usage

The `generate-debian-image.sh` script creates a Debian VM image with the following steps:

1. Downloads the Debian netboot installer
2. Creates a preseed configuration disk
3. Creates a raw disk image
4. Runs cloud-hypervisor to install Debian using the preseed configuration

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
- `--state-dir=PATH`: Set custom state directory (default: $HOME/.local/state/vllmd-hypervisor)
- `--output=PATH`: Set custom output path for the VM image
- `--memory=SIZE`: Memory size for installation VM (default: 4G)
- `--disk-size=SIZE`: Size of the output disk image (default: 20G)
- `--debian-version=VER`: Debian version to install (default: bookworm)
- `--preseed=PATH`: Path to custom preseed file (default: use built-in bookworm-preseed-v1.cfg)

Example with custom options:

```bash
bash generate-debian-image.sh --force --memory=8G --disk-size=40G --output=/path/to/custom-debian.raw
```

## Preseed Configuration

The script uses a predefined preseed configuration file (`bookworm-preseed-v1.cfg`) that sets up:

- US English locale and keyboard
- Network configuration with DHCP
- Hostname: bookworm_baseline
- Domain: artificialwisdom.cloud
- User account setup (non-root)
- XFS filesystem
- GPT partition table
- Required packages for cloud environments

You can provide your own preseed file with the `--preseed` option if you need custom settings.

## Integration with VLLMD Hypervisor

After generating the Debian VM image, you can use it with VLLMD Hypervisor:

1. Place the image in a location accessible to VLLMD Hypervisor
2. Update your VLLMD Hypervisor configuration to use this image as the source image
3. Start VMs using this base image

Example:

```bash
# Generate the image
bash generate-debian-image.sh --output=/var/lib/vllmd/images/debian-bookworm.raw

# Use the image in the VLLMD Hypervisor configuration
VLLMD_HYPERVISOR_SOURCE_REFERENCE_RAW_FILEPATH="/var/lib/vllmd/images/debian-bookworm.raw"

# Initialize VLLMD Hypervisor with the new image
bash initialize-vllmd-hypervisor.sh
```

## How It Works

The script performs the following steps to create the VM image:

1. **Preparation**:
   - Validates prerequisites
   - Creates necessary directories
   - Sets up configuration

2. **Downloading the Installer**:
   - Retrieves the Debian netboot kernel and initrd from the Debian mirror

3. **Creating the Preseed Disk**:
   - Creates a FAT-formatted disk image
   - Adds the preseed configuration file to this image

4. **Creating the Disk Image**:
   - Creates an empty raw disk image of the specified size using truncate

5. **Running the Installation**:
   - Launches cloud-hypervisor with:
     - The downloaded kernel and initrd
     - The preseed configuration disk as a secondary disk
     - The target disk image
     - The appropriate kernel command line options

6. **Completion**:
   - When the installation finishes, the disk image is ready for use with VLLMD Hypervisor

## Customization

### Custom Preseed File

To use a custom preseed file, create your own based on the provided template and pass it with the `--preseed` option:

```bash
bash generate-debian-image.sh --preseed=/path/to/my-preseed.cfg
```

### Important Preseed Settings

When customizing the preseed file, pay attention to these important settings:

- **Partitioning**: The default uses XFS filesystem (`d-i partman/default_filesystem string xfs`)
- **Package Selection**: The default includes cloud-init, openssh-server, and other utilities
- **Network Configuration**: Configured for DHCP by default
- **Late Commands**: These run at the end of installation to perform final system configurations

## Troubleshooting

### Installation Fails

If the installation fails, try:

1. Increasing the memory with `--memory=8G`
2. Running with `--dry-run` to verify configurations
3. Checking the preseed file for syntax errors
4. Ensuring network connectivity for downloading packages

### Cloud-Hypervisor Issues

If you encounter issues with cloud-hypervisor:

1. Verify that cloud-hypervisor is installed and accessible
2. Check that you're using a compatible version of cloud-hypervisor
3. Review the cloud-hypervisor logs for errors

## Security Considerations

The default preseed configuration:

- Disables root login
- Sets up a user account with sudo access
- Installs SSH server
- Applies security updates automatically

For production environments, consider customizing the preseed file to enhance security according to your requirements.