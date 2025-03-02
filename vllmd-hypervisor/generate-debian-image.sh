#!/bin/bash
#
# generate-debian-image.sh - Create a Debian VM image using preseed configuration
#
# This script generates a Debian VM image by downloading a Debian netboot installer,
# creating a preseed configuration disk, and using cloud-hypervisor to install Debian
# with the preseed configuration. The resulting image can be used with VLLMD Hypervisor.
#
# Usage:
#   bash generate-debian-image.sh [OPTIONS]
#
# Options:
#   --dry-run              Show what would be done without making any changes
#   --force                Force overwrite of existing files
#   --state-dir=PATH       Set custom state directory (default: $HOME/.local/state/vllmd-hypervisor)
#   --output=PATH          Set custom output path for the VM image
#   --memory=SIZE          Memory size for installation VM (default: 4G)
#   --disk-size=SIZE       Size of the output disk image in bytes (default: 20G)
#   --debian-version=VER   Debian version to install (default: bookworm)
#   --preseed=PATH         Path to custom preseed file (default: use built-in preseed-v1-bookworm.cfg)
#
# Examples:
#   bash generate-debian-image.sh
#   bash generate-debian-image.sh --dry-run
#   bash generate-debian-image.sh --force --memory=8G --disk-size=40G
#   bash generate-debian-image.sh --preseed=/path/to/custom-preseed.cfg
#

set -euo pipefail

# Process command line arguments
DRY_RUN=0
FORCE=0
STATE_DIR="${HOME}/.local/state/vllmd-hypervisor"
OUTPUT_PATH=""
MEMORY_SIZE="4G"
DISK_SIZE="20G"
DEBIAN_VERSION="bookworm"
PRESEED_PATH=""

# Script directory for accessing default preseed file
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
DEFAULT_PRESEED="${SCRIPT_DIR}/preseed-v1-bookworm.cfg"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --force)
            FORCE=1
            shift
            ;;
        --state-dir=*)
            STATE_DIR="${1#*=}"
            shift
            ;;
        --output=*)
            OUTPUT_PATH="${1#*=}"
            shift
            ;;
        --memory=*)
            MEMORY_SIZE="${1#*=}"
            shift
            ;;
        --disk-size=*)
            DISK_SIZE="${1#*=}"
            shift
            ;;
        --debian-version=*)
            DEBIAN_VERSION="${1#*=}"
            shift
            ;;
        --preseed=*)
            PRESEED_PATH="${1#*=}"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Set default OUTPUT_PATH if not specified
if [[ -z "${OUTPUT_PATH}" ]]; then
    OUTPUT_PATH="${STATE_DIR}/debian-${DEBIAN_VERSION}-vllmd.raw"
fi

# Set default PRESEED_PATH if not specified
if [[ -z "${PRESEED_PATH}" ]]; then
    PRESEED_PATH="${DEFAULT_PRESEED}"
fi

# Validate prerequisites
check_prerequisites() {
    local missing=0
    
    # Check for cloud-hypervisor
    if ! command -v cloud-hypervisor &>/dev/null; then
        echo "ERROR: cloud-hypervisor is not installed. Please install it first."
        missing=1
    fi
    
    # Check for mkdosfs (part of dosfstools)
    if ! command -v mkdosfs &>/dev/null; then
        echo "ERROR: mkdosfs not found. Please install dosfstools package."
        missing=1
    fi
    
    # Check for mcopy (part of mtools)
    if ! command -v mcopy &>/dev/null; then
        echo "ERROR: mcopy not found. Please install mtools package."
        missing=1
    fi
    
    # Check for truncate (part of coreutils)
    if ! command -v truncate &>/dev/null; then
        echo "ERROR: truncate not found. Please install coreutils package."
        missing=1
    fi
    
    # Check for wget
    if ! command -v wget &>/dev/null; then
        echo "ERROR: wget not found. Please install wget package."
        missing=1
    fi
    
    # Check for preseed file
    if [[ ! -f "${PRESEED_PATH}" ]]; then
        echo "ERROR: Preseed file not found at ${PRESEED_PATH}"
        missing=1
    fi
    
    if [[ "${missing}" -eq 1 ]]; then
        exit 1
    fi
}

# Check for existing files
check_existing_files() {
    local existing=0
    
    if [[ -f "${OUTPUT_PATH}" ]]; then
        echo "WARNING: Output image already exists at ${OUTPUT_PATH}"
        existing=1
    fi
    
    if [[ "${existing}" -eq 1 && "${FORCE}" -ne 1 ]]; then
        echo "Use --force to overwrite existing files"
        exit 1
    fi
}

# Create necessary directories
create_directories() {
    if [[ ! -d "${STATE_DIR}" ]]; then
        if [[ "${DRY_RUN}" -eq 0 ]]; then
            mkdir -p "${STATE_DIR}"
            echo "Created state directory: ${STATE_DIR}"
        else
            echo "[DRY RUN] Would create state directory: ${STATE_DIR}"
        fi
    fi
    
    # Create build directory for temporary files
    BUILD_DIR="${STATE_DIR}/build"
    if [[ ! -d "${BUILD_DIR}" ]]; then
        if [[ "${DRY_RUN}" -eq 0 ]]; then
            mkdir -p "${BUILD_DIR}"
            echo "Created build directory: ${BUILD_DIR}"
        else
            echo "[DRY RUN] Would create build directory: ${BUILD_DIR}"
        fi
    fi
}

# Download Debian netboot installer
download_installer() {
    local kernel_url="http://ftp.debian.org/debian/dists/${DEBIAN_VERSION}/main/installer-amd64/current/images/netboot/debian-installer/amd64/linux"
    local initrd_url="http://ftp.debian.org/debian/dists/${DEBIAN_VERSION}/main/installer-amd64/current/images/netboot/debian-installer/amd64/initrd.gz"
    
    if [[ "${DRY_RUN}" -eq 0 ]]; then
        echo "Downloading Debian ${DEBIAN_VERSION} netboot installer..."
        wget -O "${BUILD_DIR}/kernel" "${kernel_url}" || { echo "Failed to download kernel"; exit 1; }
        wget -O "${BUILD_DIR}/initrd.gz" "${initrd_url}" || { echo "Failed to download initrd"; exit 1; }
        echo "Download completed."
    else
        echo "[DRY RUN] Would download Debian ${DEBIAN_VERSION} netboot installer from:"
        echo "  - ${kernel_url}"
        echo "  - ${initrd_url}"
    fi
}

# Create preseed configuration disk
create_preseed_disk() {
    local preseed_disk="${BUILD_DIR}/preseed.img"
    local temp_dir=$(mktemp -d)
    
    if [[ "${DRY_RUN}" -eq 0 ]]; then
        echo "Creating preseed configuration disk..."
        
        # Copy preseed file to temporary directory
        cp "${PRESEED_PATH}" "${temp_dir}/preseed.cfg"
        
        # Create FAT filesystem image for preseed disk
        /usr/sbin/mkdosfs -n PRESEED -C "${preseed_disk}" 8192
        
        # Copy preseed file to the image
        mcopy -oi "${preseed_disk}" -s "${temp_dir}/preseed.cfg" ::
        
        echo "Preseed configuration disk created at ${preseed_disk}"
        rm -rf "${temp_dir}"
    else
        echo "[DRY RUN] Would create preseed configuration disk at ${preseed_disk}"
        echo "[DRY RUN] Would copy preseed file from ${PRESEED_PATH}"
    fi
}

# Create the VM disk image
create_disk_image() {
    if [[ "${DRY_RUN}" -eq 0 ]]; then
        echo "Creating disk image for VM..."
        # Create an empty file of the specified size using truncate (no QEMU dependency)
        truncate -s "${DISK_SIZE}" "${OUTPUT_PATH}"
        echo "Disk image created at ${OUTPUT_PATH}"
    else
        echo "[DRY RUN] Would create ${DISK_SIZE} disk image at ${OUTPUT_PATH}"
    fi
}

# Run the installation using cloud-hypervisor
run_installation() {
    local kernel_path="${BUILD_DIR}/kernel"
    local initrd_path="${BUILD_DIR}/initrd.gz"
    local preseed_disk="${BUILD_DIR}/preseed.img"
    local kernel_args="console=ttyS0 auto=true priority=critical interface=auto url=file:///preseed.cfg"
    
    if [[ "${DRY_RUN}" -eq 0 ]]; then
        echo "Starting Debian installation using cloud-hypervisor..."
        echo "This will take some time. Installation logs will be displayed."
        
        # Run cloud-hypervisor with the specified configuration
        cloud-hypervisor \
            --kernel "${kernel_path}" \
            --initramfs "${initrd_path}" \
            --cmdline "${kernel_args}" \
            --memory "size=${MEMORY_SIZE}" \
            --disk "path=${OUTPUT_PATH},readonly=off" \
            --disk "path=${preseed_disk},readonly=on" \
            --console tty \
            --serial tty
        
        echo "Debian installation completed."
    else
        echo "[DRY RUN] Would start Debian installation with the following configuration:"
        echo "  - Kernel: ${kernel_path}"
        echo "  - Initrd: ${initrd_path}"
        echo "  - Kernel args: ${kernel_args}"
        echo "  - Memory: ${MEMORY_SIZE}"
        echo "  - Disk: ${OUTPUT_PATH} (${DISK_SIZE})"
        echo "  - Preseed disk: ${preseed_disk}"
    fi
}

# Main execution
main() {
    echo "VLLMD Hypervisor Debian Image Generator"
    
    # Check prerequisites
    check_prerequisites
    
    # Check for existing files
    check_existing_files
    
    # Create necessary directories
    create_directories
    
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "[DRY RUN] Would generate Debian ${DEBIAN_VERSION} VM image"
        echo "[DRY RUN] Configuration:"
        echo "  - State directory: ${STATE_DIR}"
        echo "  - Output path: ${OUTPUT_PATH}"
        echo "  - Memory size: ${MEMORY_SIZE}"
        echo "  - Disk size: ${DISK_SIZE}"
        echo "  - Preseed file: ${PRESEED_PATH}"
    else
        echo "Generating Debian ${DEBIAN_VERSION} VM image"
        echo "Configuration:"
        echo "  - State directory: ${STATE_DIR}"
        echo "  - Output path: ${OUTPUT_PATH}"
        echo "  - Memory size: ${MEMORY_SIZE}"
        echo "  - Disk size: ${DISK_SIZE}"
        echo "  - Preseed file: ${PRESEED_PATH}"
    fi
    
    # Download installer
    download_installer
    
    # Create preseed disk
    create_preseed_disk
    
    # Create disk image
    create_disk_image
    
    # Run installation
    run_installation
    
    if [[ "${DRY_RUN}" -eq 0 ]]; then
        echo "Debian VM image generation completed successfully."
        echo "The image is available at: ${OUTPUT_PATH}"
        echo "You can use this image with VLLMD Hypervisor by specifying it as the source image."
    else
        echo "[DRY RUN] Script would complete without making any changes"
    fi
}

# Run the main function
main