
#!/usr/bin/env bash
#
# generate-runtime-image.sh - Create a runtime image for VLLMD Hypervisor
#
# This script generates a Debian-based runtime image by downloading a Debian netinst ISO,
# creating a preseed configuration disk, and using cloud-hypervisor-v44 to generate a 
# runtime image with the preseed configuration. The resulting image can be used with VLLMD Hypervisor.
#
# Usage:
#   bash generate-runtime-image.sh [OPTIONS]
#
# Options:
#   --dry-run              Show what would be done without making any changes
#   --force                Force overwrite of existing files
#   --state-dir=PATH       Set custom state directory (default: $HOME/.local/state/vllmd/vllmd-hypervisor)
#   --output=PATH          Set custom output path for the runtime image
#   --memory=SIZE          Memory size for generation process in GiB (default: 16GiB)
#   --disk-size=SIZE       Size of the output disk image in GiB (default: 20GiB)
#   --debian-version=VER   Debian version to use (default: bookworm)
#   --preseed=PATH         Path to custom preseed file (default: use built-in preseed-v1-bookworm.cfg)
#
# Examples:
#   bash generate-runtime-image.sh
#   bash generate-runtime-image.sh --dry-run
#   bash generate-runtime-image.sh --force --memory=32GiB --disk-size=40GiB
#   bash generate-runtime-image.sh --preseed=/path/to/custom-preseed.cfg
#

set -euo pipefail

# Process command line arguments
DRY_RUN=0
FORCE=0
STATE_DIR="${HOME}/.local/state/vllmd/vllmd-hypervisor"
OUTPUT_PATH=""
MEMORY_SIZE="16G"
DISK_SIZE="20G"
DEBIAN_VERSION="bookworm"
PRESEED_PATH=""

# Script directory for accessing default preseed file
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
DEFAULT_PRESEED="${SCRIPT_DIR}/preseed-v1-bookworm.cfg"

# Set cache directory for ISO
CACHE_DIR="${HOME}/.cache/vllmd/vllmd-hypervisor"

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

# Get timestamp for file naming
TIMESTAMP=$(date "+%Y%m%d-%W-%H%M%S")

# Set up shared directory
SHARE_DIR="${HOME}/.local/share/vllmd/vllmd-hypervisor"
mkdir -p "${SHARE_DIR}" 2>/dev/null || true

# Set default OUTPUT_PATH if not specified
if [[ -z "${OUTPUT_PATH}" ]]; then
    OUTPUT_PATH="${STATE_DIR}/${TIMESTAMP}-vllmd-hypervisor-runtime.raw"
fi

# Set default PRESEED_PATH if not specified
if [[ -z "${PRESEED_PATH}" ]]; then
    PRESEED_PATH="${DEFAULT_PRESEED}"
fi

# Validate prerequisites
check_prerequisites() {
    local missing=0
    
    # Check for cloud-hypervisor-v44
    if ! command -v cloud-hypervisor-v44 &>/dev/null; then
        echo "ERROR: cloud-hypervisor-v44 is not installed. Please install it first."
        missing=1
    fi
    
    # Check for mkdosfs (part of dosfstools)
    if ! command -v /usr/sbin/mkdosfs &>/dev/null; then
        echo "ERROR: /usr/sbin/mkdosfs not found. Please install dosfstools package."
        missing=1
    fi
    
    # Check for mcopy (part of mtools)
    if ! command -v /usr/bin/mcopy &>/dev/null; then
        echo "ERROR: /usr/bin/mcopy not found. Please install mtools package."
        missing=1
    fi
    
    # Check for truncate (part of coreutils)
    if ! command -v truncate &>/dev/null; then
        echo "ERROR: truncate not found. Please install coreutils package."
        missing=1
    fi
    
    # Check for curl
    if ! command -v /usr/bin/curl &>/dev/null; then
        echo "ERROR: /usr/bin/curl not found. Please install curl package."
        missing=1
    fi
    
    # Check for IP tool
    if ! command -v /usr/sbin/ip &>/dev/null && ! command -v /sbin/ip &>/dev/null; then
        echo "ERROR: ip command not found. Please install iproute2 package."
        missing=1
    fi
    
    # Check for iptables
    if ! command -v /usr/sbin/iptables &>/dev/null && ! command -v /sbin/iptables &>/dev/null; then
        echo "ERROR: iptables not found. Please install iptables package."
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
    
    # Create build directory for temporary files with timestamp
    BUILD_DIR="${STATE_DIR}/${TIMESTAMP}-build"
    if [[ ! -d "${BUILD_DIR}" ]]; then
        if [[ "${DRY_RUN}" -eq 0 ]]; then
            mkdir -p "${BUILD_DIR}"
            echo "Created build directory: ${BUILD_DIR}"
        else
            echo "[DRY RUN] Would create build directory: ${BUILD_DIR}"
        fi
    fi
}

# Download Debian netinst ISO
download_installer() {
    local iso_url="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.9.0-amd64-netinst.iso"
    local iso_path="${BUILD_DIR}/debian-netinst.iso"
    local cache_iso="${CACHE_DIR}/debian-netinst.iso"
    
    # Create cache directory if it doesn't exist
    if [[ ! -d "${CACHE_DIR}" ]]; then
        if [[ "${DRY_RUN}" -eq 0 ]]; then
            mkdir -p "${CACHE_DIR}"
            echo "Created cache directory: ${CACHE_DIR}"
        else
            echo "[DRY RUN] Would create cache directory: ${CACHE_DIR}"
        fi
    fi
    
    # Check if file exists in cache
    if [[ -f "${cache_iso}" ]]; then
        echo "Found cached ISO at ${cache_iso}, reusing..."
        if [[ "${DRY_RUN}" -eq 0 ]]; then
            cp "${cache_iso}" "${iso_path}" || { echo "Failed to copy cached ISO"; exit 1; }
            echo "Copied to ${iso_path}"
        else
            echo "[DRY RUN] Would copy cached ISO to ${iso_path}"
        fi
        return
    elif [[ -f "${iso_path}" ]]; then
        echo "Using existing ISO at ${iso_path}"
        return
    fi
    
    if [[ "${DRY_RUN}" -eq 0 ]]; then
        echo "Downloading Debian netinst ISO..."
        /usr/bin/curl -L -o "${iso_path}" "${iso_url}" || { echo "Failed to download ISO"; exit 1; }
        echo "Download completed."
        
        # Cache the ISO for future runs
        echo "Caching ISO for future use..."
        cp "${iso_path}" "${cache_iso}" || { echo "Warning: Failed to cache ISO"; }
    else
        echo "[DRY RUN] Would download Debian netinst ISO from:"
        echo "  - ${iso_url}"
    fi
}

# Create preseed configuration disk
create_preseed_disk() {
    local preseed_disk="${BUILD_DIR}/${TIMESTAMP}-preseed.img"
    # Use XDG_RUNTIME_DIR for temporary files if available, otherwise fallback to mktemp
    local temp_dir
    if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
        temp_dir="${XDG_RUNTIME_DIR}/vllmd/vllmd-hypervisor-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "${temp_dir}"
    else
        temp_dir=$(mktemp -d -p "${TMPDIR:-/tmp}" vllmd-vllmd-hypervisor-XXXXXXXXXX)
    fi
    
    if [[ "${DRY_RUN}" -eq 0 ]]; then
        echo "Creating preseed configuration disk..."
        
        # Remove existing preseed disk if it exists and force flag is set
        if [[ -f "${preseed_disk}" ]]; then
            if [[ "${FORCE}" -eq 1 ]]; then
                echo "Removing existing preseed disk: ${preseed_disk}"
                rm -f "${preseed_disk}"
            else
                echo "ERROR: Preseed disk already exists at ${preseed_disk}. Use --force to overwrite."
                rm -rf "${temp_dir}"
                exit 1
            fi
        fi
        
        # Copy preseed file to temporary directory
        cp "${PRESEED_PATH}" "${temp_dir}/preseed.cfg"
        
        # Add a marker to the preseed file to ensure it's correctly identified
        echo "# Preseed file for VLLMD Hypervisor runtime image - $(date)" >> "${temp_dir}/preseed.cfg"
        
        # Create FAT filesystem image for preseed disk with a specific label
        /usr/sbin/mkdosfs -n "VLLM_PRES" -C "${preseed_disk}" 8192
        
        # Copy preseed file to the image in the root directory (ensure correct name)
        echo "Copying preseed file to disk image as /preseed.cfg..."
        /usr/bin/mcopy -oi "${preseed_disk}" "${temp_dir}/preseed.cfg" ::/preseed.cfg
        
        # Verify the preseed file is correctly written
        echo "Verifying preseed file on disk image..."
        /usr/bin/mdir -i "${preseed_disk}" ::
        
        echo "Preseed configuration disk created at ${preseed_disk}"
        rm -rf "${temp_dir}"
    else
        echo "[DRY RUN] Would create preseed configuration disk at ${preseed_disk}"
        echo "[DRY RUN] Would copy preseed file from ${PRESEED_PATH}"
    fi
}

# Create the runtime image disk
create_disk_image() {
    if [[ "${DRY_RUN}" -eq 0 ]]; then
        echo "Creating disk image for runtime image..."
        
        # Remove existing disk image if it exists and force flag is set
        if [[ -f "${OUTPUT_PATH}" ]]; then
            if [[ "${FORCE}" -eq 1 ]]; then
                echo "Removing existing disk image: ${OUTPUT_PATH}"
                rm -f "${OUTPUT_PATH}"
            else
                echo "ERROR: Disk image already exists at ${OUTPUT_PATH}. Use --force to overwrite."
                exit 1
            fi
        fi
        
        # Create parent directory if it doesn't exist
        local output_dir=$(dirname "${OUTPUT_PATH}")
        if [[ ! -d "${output_dir}" ]]; then
            mkdir -p "${output_dir}"
            echo "Created output directory: ${output_dir}"
        fi
        
        # Create an empty file of the specified size using truncate (no QEMU dependency)
        truncate -s "${DISK_SIZE}" "${OUTPUT_PATH}"
        echo "Disk image created at ${OUTPUT_PATH}"
    else
        echo "[DRY RUN] Would create ${DISK_SIZE} disk image at ${OUTPUT_PATH}"
    fi
}

# Run the generation process using cloud-hypervisor-v44
run_generation() {
    local iso_path="${BUILD_DIR}/debian-netinst.iso"
    local preseed_disk="${BUILD_DIR}/${TIMESTAMP}-preseed.img"
    
    # Function to clean up network resources
    cleanup_network() {
        local macvtap_name="${macvtap_device:-macvtap0}"
        echo "Cleaning up network resources..."
        
        # Check if the macvtap device exists before trying to remove it
        if ip link show "${macvtap_name}" &>/dev/null; then
            echo "Removing macvtap device ${macvtap_name}..."
            sudo ip link set "${macvtap_name}" down || true
            sudo ip link delete "${macvtap_name}" || true
            if ip link show "${macvtap_name}" &>/dev/null; then
                echo "WARNING: Failed to remove macvtap device ${macvtap_name}"
            else
                echo "Macvtap device ${macvtap_name} removed successfully"
            fi
        else
            echo "Macvtap device ${macvtap_name} already removed or not created"
        fi
    }
    
    # Ensure cleanup happens on script exit
    trap cleanup_network EXIT
    
    if [[ "${DRY_RUN}" -eq 0 ]]; then
        echo "Starting Debian runtime image generation using cloud-hypervisor-v44..."
        echo "This will take some time. Generation logs will be displayed."
        
        # First, check if macvtap0 already exists and remove it
        echo "Checking for existing macvtap devices..."
        if ip link show macvtap0 &>/dev/null; then
            echo "Macvtap device macvtap0 already exists, removing it first..."
            sudo ip link set macvtap0 down || { 
                echo "ERROR: Failed to bring down existing macvtap device"; 
                echo "Please manually remove it with: sudo ip link set macvtap0 down"; 
                exit 1;
            }
            
            sudo ip link delete macvtap0 || {
                echo "ERROR: Failed to delete existing macvtap device";
                echo "Please manually remove it with: sudo ip link delete macvtap0";
                exit 1;
            }
        fi
        
        # Get the default network interface
        local default_interface=$(ip route | grep default | head -1 | awk '{print $5}')
        if [[ -z "${default_interface}" ]]; then
            echo "ERROR: Could not determine default network interface"
            exit 1
        fi
        echo "Host network interface is ${default_interface}"
        
        # Define macvtap device name and MAC address
        local macvtap_device="macvtap0"
        local mac_address="52:54:00:12:34:56"
        
        # Create a macvtap on the host network
        echo "Creating macvtap device ${macvtap_device} on ${default_interface}..."
        sudo ip link add link "${default_interface}" name "${macvtap_device}" type macvtap || {
            echo "ERROR: Failed to create macvtap device";
            exit 1;
        }
        
        # Set MAC address and bring up the interface
        echo "Configuring macvtap device with MAC ${mac_address}..."
        sudo ip link set "${macvtap_device}" address "${mac_address}" up || {
            echo "ERROR: Failed to configure macvtap device";
            sudo ip link delete "${macvtap_device}" || true;
            exit 1;
        }
        
        # Show macvtap info
        echo "Macvtap device information:"
        sudo ip link show "${macvtap_device}"
        
        # Get the tap index for the device file
        echo "Getting tap device index..."
        local tap_index=$(cat /sys/class/net/"${macvtap_device}"/ifindex 2>/dev/null)
        if [[ -z "${tap_index}" ]]; then
            echo "ERROR: Failed to get tap index for ${macvtap_device}"
            sudo ip link delete "${macvtap_device}" || true
            exit 1
        fi
        
        # Create the tap device path
        local tap_device="/dev/tap${tap_index}"
        echo "Using tap device: ${tap_device}"
        
        # Ensure the tap device file exists and is accessible
        if [[ ! -e "${tap_device}" ]]; then
            echo "ERROR: Tap device file ${tap_device} does not exist"
            sudo ip link delete "${macvtap_device}" || true
            exit 1
        fi
        
        # Make the tap device file accessible
        sudo chmod 666 "${tap_device}" || {
            echo "WARNING: Could not change permissions on ${tap_device}";
            echo "If the generation process fails to start, you may need to run this script as root";
        }
        
        echo "Successfully configured macvtap networking via ${macvtap_device}"
        echo "Network configuration summary:"
        ip -d link show "${macvtap_device}"
        
        # Run cloud-hypervisor-v44 with macvtap networking
        # We redirect FD 3 to the tap device file
        
        # Check if required kernel and initramfs files exist
        if [[ ! -f "$HOME/vmlinuz" ]]; then
            echo "ERROR: Kernel file $HOME/vmlinuz not found"
            cleanup_network
            exit 1
        fi
        
        if [[ ! -f "$HOME/initrd.gz" ]]; then
            echo "ERROR: Initramfs file $HOME/initrd.gz not found"
            cleanup_network
            exit 1
        fi
        
        # Verify output path exists before running cloud-hypervisor
        if [[ ! -f "${OUTPUT_PATH}" ]]; then
            echo "ERROR: Output disk image ${OUTPUT_PATH} not found"
            cleanup_network
            exit 1
        fi
        
        echo "Running cloud-hypervisor-v44 to generate runtime image..."
        cloud-hypervisor-v44 \
            --kernel $HOME/vmlinuz \
            --initramfs $HOME/initrd.gz \
            --cmdline "console=ttyS0,115200n8 auto=true priority=critical debug ignore_loglevel earlyprintk=serial,ttyS0,115200 nodmodeset url=file:///media/preseed.cfg" \
            --disk path="${iso_path}",id=1 \
                   path="${preseed_disk}",id=2 \
                   path="${OUTPUT_PATH}",id=3 \
            --cpus boot="4" \
            --memory "size=${MEMORY_SIZE}" \
            --net fd=3,mac="${mac_address}" 3<>"${tap_device}" \
            --serial tty \
            --console off || {
                echo "ERROR: cloud-hypervisor-v44 failed to complete runtime image generation"
                cleanup_network
                exit 1
            }
        
        echo "Runtime image generation completed."
    else
        echo "[DRY RUN] Would start runtime image generation with the following configuration:"
        echo "  - ISO: ${iso_path} (readonly=on)"
        echo "  - Memory: ${MEMORY_SIZE}"
        echo "  - Disk 1: ${OUTPUT_PATH} (${DISK_SIZE}, readonly=off)"
        echo "  - Disk 2: ${preseed_disk} (readonly=on)"
        echo "  - Network: Using macvtap interface on default network interface"
        echo "  - MAC Address: 52:54:00:12:34:56"
    fi
    
    # Explicit cleanup call - trap will also handle this on exit
    cleanup_network
}

# Main execution
main() {
    echo "VLLMD Hypervisor Runtime Image Generator"
    
    # Check prerequisites
    check_prerequisites
    
    # Check for existing files
    check_existing_files
    
    # Create necessary directories
    create_directories
    
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "[DRY RUN] Would generate Debian ${DEBIAN_VERSION} runtime image"
        echo "[DRY RUN] Configuration:"
        echo "  - State directory: ${STATE_DIR}"
        echo "  - Output path: ${OUTPUT_PATH}"
        echo "  - Memory size: ${MEMORY_SIZE}"
        echo "  - Disk size: ${DISK_SIZE}"
        echo "  - Preseed file: ${PRESEED_PATH}"
    else
        echo "Generating Debian ${DEBIAN_VERSION} runtime image"
        echo "Configuration:"
        echo "  - State directory: ${STATE_DIR}"
        echo "  - Output path: ${OUTPUT_PATH}"
        echo "  - Memory size: ${MEMORY_SIZE}"
        echo "  - Disk size: ${DISK_SIZE}"
        echo "  - Preseed file: ${PRESEED_PATH}"
    fi
    
    # Download installer
    download_installer
    
    create_preseed_disk
    
    # Create disk image
    create_disk_image
    
    # Run generation process
    run_generation
    
    if [[ "${DRY_RUN}" -eq 0 ]]; then
        echo "VLLMD Hypervisor runtime image generation completed successfully."
        echo "The image is available at: ${OUTPUT_PATH}"
        echo "You can use this image with VLLMD Hypervisor by specifying it as the source image."
    else
        echo "[DRY RUN] Script would complete without making any changes"
    fi
}

# Run the main function
main
