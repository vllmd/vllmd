#!/bin/bash
#
# generate-init-vllmd-hypervisor.sh - Create a cloud-init configuration disk for VLLMD VMs
#
# This script generates a FAT filesystem image containing cloud-init configuration
# for VM provisioning. The image includes user-data and meta-data files that
# configure the VM's hostname and user accounts.
#
# Usage:
#   ./generate-cloudinit-disk.sh [OPTIONS] [vm_name]
#
# Options:
#   --dry-run     Show what would be done without making any changes
#
# Arguments:
#   vm_name - Optional VM name (defaults to "vllmd-vm")
#
# Examples:
#   ./generate-cloudinit-disk.sh
#   ./generate-cloudinit-disk.sh my-custom-vm
#   ./generate-cloudinit-disk.sh --dry-run
#

set -euo pipefail

# Process command line arguments
DRY_RUN=0
VM_NAME="vllmd-vm"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        *)
            VM_NAME="$1"
            shift
            ;;
    esac
done

OUTPUT_PATH="/mnt/aw/cloudinit-boot-disk.raw"

# Create temporary directory for cloud-init files
TEMP_DIR=$(mktemp -d)
trap 'rm -rf ${TEMP_DIR}' EXIT

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
    
    echo "[DRY RUN] Would create directory: $(dirname "${OUTPUT_PATH}")"
    echo "[DRY RUN] Would create FAT filesystem image at: ${OUTPUT_PATH}"
    echo "[DRY RUN] Would copy user-data and meta-data files to the image"
    
    echo "[DRY RUN] Script would complete without making any changes"
    exit 0
fi

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

echo "Creating cloud-init disk image at ${OUTPUT_PATH}..."

# Ensure parent directory exists
mkdir -p $(dirname "${OUTPUT_PATH}")

# Create FAT filesystem image
/usr/sbin/mkdosfs -n CIDATA -C "${OUTPUT_PATH}" 8192

# Copy files to the image
mcopy -oi "${OUTPUT_PATH}" -s "${TEMP_DIR}/user-data" ::
mcopy -oi "${OUTPUT_PATH}" -s "${TEMP_DIR}/meta-data" ::

echo "Cloud-init configuration disk created successfully at ${OUTPUT_PATH}"
echo "This disk will be used as a secondary boot disk for all VMs"
echo "You may need to run parts of this script with sudo if permission errors occur"
