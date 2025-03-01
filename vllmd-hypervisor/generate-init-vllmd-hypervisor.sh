#!/bin/bash
#
# generate-init-vllmd-hypervisor.sh - Create a cloud-init configuration disk for VLLMD VMs
#
# This script generates a FAT filesystem image containing cloud-init configuration
# for VM provisioning. The image includes user-data and meta-data files that
# configure the VM's hostname and user accounts.
#
# Usage:
#   bash generate-init-vllmd-hypervisor.sh [OPTIONS] [vm_name]
#
# Options:
#   --dry-run              Show what would be done without making any changes
#   --force                Force overwrite of existing files
#   --config-dir=PATH      Set custom config directory (default: $HOME/.config/vllmd-hypervisor)
#   --state-dir=PATH       Set custom state directory (default: $HOME/.local/state/vllmd-hypervisor)
#
# Arguments:
#   vm_name - Optional VM name (defaults to "vllmd-vm")
#
# Examples:
#   bash generate-init-vllmd-hypervisor.sh
#   bash generate-init-vllmd-hypervisor.sh my-custom-vm
#   bash generate-init-vllmd-hypervisor.sh --dry-run
#   bash generate-init-vllmd-hypervisor.sh --force
#

set -euo pipefail

# Process command line arguments
DRY_RUN=0
FORCE=0
VM_NAME="vllmd-vm"
CONFIG_DIR="${HOME}/.config/vllmd-hypervisor"
STATE_DIR="${HOME}/.local/state/vllmd-hypervisor"

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
        --config-dir=*)
            CONFIG_DIR="${1#*=}"
            shift
            ;;
        --state-dir=*)
            STATE_DIR="${1#*=}"
            shift
            ;;
        *)
            VM_NAME="$1"
            shift
            ;;
    esac
done

# Define output paths
OUTPUT_PATH="${STATE_DIR}/vllmd-hypervisor-initdisk.raw"
CONFIG_PATH="${CONFIG_DIR}/vllmd-hypervisor-config.yaml"

# Create temporary directory for cloud-init files
TEMP_DIR=$(mktemp -d)
trap 'rm -rf ${TEMP_DIR}' EXIT

# Check for existing files
check_existing_files() {
    local existing=0
    
    if [[ -f "${OUTPUT_PATH}" ]]; then
        echo "WARNING: Output image already exists at ${OUTPUT_PATH}"
        existing=1
    fi
    
    if [[ -f "${CONFIG_PATH}" ]]; then
        echo "WARNING: Configuration file already exists at ${CONFIG_PATH}"
        existing=1
    fi
    
    if [[ "${existing}" -eq 1 && "${FORCE}" -ne 1 ]]; then
        echo "Use --force to overwrite existing files"
        exit 1
    fi
}

# Create necessary directories
create_directories() {
    if [[ ! -d "${CONFIG_DIR}" ]]; then
        mkdir -p "${CONFIG_DIR}"
        echo "Created configuration directory: ${CONFIG_DIR}"
    fi
    
    if [[ ! -d "${STATE_DIR}" ]]; then
        mkdir -p "${STATE_DIR}"
        echo "Created state directory: ${STATE_DIR}"
    fi
}

if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[DRY RUN] Would generate cloud-init configuration for ${VM_NAME}"
    echo "[DRY RUN] Would create meta-data file with:"
    echo "  instance-id: ${VM_NAME}"
    echo "  local-hostname: ${VM_NAME}"
    
    echo "[DRY RUN] Would create user-data file with:"
    echo "  - User: sdake"
    echo "  - SSH import from GitHub: gh:sdake"
    echo "  - Sudo access: ALL=(ALL) NOPASSWD:ALL"
    echo "  - Shell: /bin/bash"
    echo "  - Password authentication: enabled"
    
    echo "[DRY RUN] Would create configuration file: ${CONFIG_PATH}"
    echo "[DRY RUN] Would create directories if needed:"
    echo "  - ${CONFIG_DIR}"
    echo "  - ${STATE_DIR}"
    echo "[DRY RUN] Would create FAT filesystem image at: ${OUTPUT_PATH}"
    echo "[DRY RUN] Would copy user-data and meta-data files to the image"
    
    echo "[DRY RUN] Script would complete without making any changes"
    exit 0
fi

# Check for existing files
check_existing_files

# Create necessary directories
create_directories

echo "Generating cloud-init configuration for ${VM_NAME}..."

# Create meta-data file
cat > "${TEMP_DIR}/meta-data" << EOF
#cloud-config
---
instance-id: ${VM_NAME}
local-hostname: ${VM_NAME}
EOF

# Create user-data file
cat > "${TEMP_DIR}/user-data" << EOF
#cloud-config
---
users:
  - name: sdake
    ssh_import_id:
      - gh:sdake
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: false
    inactive: false
    shell: /bin/bash
ssh_pwauth: true
EOF

# Save configuration for reference
cat > "${CONFIG_PATH}" << EOF
# VLLMD Hypervisor Cloud-Init Configuration
# Generated on $(date '+%Y-%m-%d %H:%M:%S')

vm_name: ${VM_NAME}
image_path: ${OUTPUT_PATH}
config_dir: ${CONFIG_DIR}
state_dir: ${STATE_DIR}

# Cloud-Init Template Configuration
user: sdake
ssh_import: gh:sdake
sudo_access: ALL=(ALL) NOPASSWD:ALL
password_auth: true
EOF

echo "Creating cloud-init disk image at ${OUTPUT_PATH}..."

# Create FAT filesystem image
/usr/sbin/mkdosfs -n CIDATA -C "${OUTPUT_PATH}" 8192

# Copy files to the image
mcopy -oi "${OUTPUT_PATH}" -s "${TEMP_DIR}/user-data" ::
mcopy -oi "${OUTPUT_PATH}" -s "${TEMP_DIR}/meta-data" ::

echo "Cloud-init configuration disk created successfully at ${OUTPUT_PATH}"
echo "Configuration saved to ${CONFIG_PATH}"
echo "This disk will be used as a secondary boot disk for all VMs"
