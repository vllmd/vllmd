#!/usr/bin/env bash
#
# vllmd-setup.sh - Proof-of-concept script for setting up VLLMD hypervisor
#
# This script implements the core functionality for deploying cloud-hypervisor
# VMs optimized for inference workloads.
#
# Security note: This script requires sudo access for specific operations
# but follows the principle of least privilege by only using elevated
# permissions where absolutely necessary.
#
# Usage:
#   bash vllmd-setup.sh [OPTIONS]
#
# Options:
#   --dry-run                  Show what would be done without making any changes
#   --yes                      Automatically use defaults without prompting
#   --no-reboot                Skip reboot requests and continue script execution
#   --destructive-image-replace Allow overwriting existing disk images
#   --image-prefix=PATH        Set custom path for VM images (default: /mnt/aw)
#   --source-raw-image=PATH    Path to source raw image file (default: /mnt/aw/base.raw)
#   --hypervisor-fw=PATH       Path to hypervisor firmware (default: /mnt/aw/hypervisor-fw)
#   --cloudinit-disk=PATH      Path to cloud-init disk image (default: /mnt/aw/cloudinit-boot-disk.raw)
#   --help                     Display this help message
#
# Example:
#   bash vllmd-setup.sh --dry-run
#   bash vllmd-setup.sh --yes
#   bash vllmd-setup.sh --no-reboot
#   bash vllmd-setup.sh --destructive-image-replace
#   bash vllmd-setup.sh --image-prefix=/mnt/aw --source-raw-image=/mnt/aw/base.raw --hypervisor-fw=/mnt/aw/hypervisor-fw

set -euo pipefail

# ===== Command Line Processing =====
DRY_RUN=0
AUTO_YES=0
NO_REBOOT=0
DESTRUCTIVE_IMAGE_REPLACE=0
STEP_NUMBER=0
VLLMD_KVM_IMAGE_PATH_PREFIX="/mnt/aw"
VLLMD_KVM_SOURCE_RAW_FILEPATH="/mnt/aw/base.raw"
VLLMD_KVM_HYPERVISOR_FW_FILEPATH="/mnt/aw/hypervisor-fw"
VLLMD_KVM_CLOUDINIT_FILEPATH="/mnt/aw/cloudinit-boot-disk.raw"

# Created files tracking
CREATED_FILES=()

function print_help() {
    sed -n 's/^# //p' "$0" | sed -n '/^Usage:/,/^$/p'
}

# Process command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) 
            DRY_RUN=1
            shift
            ;;
        --yes)
            AUTO_YES=1
            shift
            ;;
        --no-reboot)
            NO_REBOOT=1
            shift
            ;;
        --destructive-image-replace)
            DESTRUCTIVE_IMAGE_REPLACE=1
            shift
            ;;
        --image-prefix=*)
            VLLMD_KVM_IMAGE_PATH_PREFIX="${1#*=}"
            shift
            ;;
        --source-raw-image=*)
            VLLMD_KVM_SOURCE_RAW_FILEPATH="${1#*=}"
            shift
            ;;
        --hypervisor-fw=*)
            VLLMD_KVM_HYPERVISOR_FW_FILEPATH="${1#*=}"
            shift
            ;;
        --cloudinit-disk=*)
            VLLMD_KVM_CLOUDINIT_FILEPATH="${1#*=}"
            shift
            ;;
        --help)
            print_help
            exit 0
            ;;
        *)
            echo "Error: Unknown option $1"
            print_help
            exit 1
            ;;
    esac
done

# ===== Constants =====

# Directories
readonly VLLMD_KVM_CONFIG_PATH="${HOME}/.config/vllmd"
readonly VLLMD_KVM_SYSTEMD_PATH="${HOME}/.config/systemd/user"
readonly VLLMD_KVM_RUN_PATH="${HOME}/.local/run/vllmd"
readonly VLLMD_KVM_LOG_PATH="${HOME}/.local/log/vllmd"
readonly VLLMD_KVM_IMAGE_PATH="${VLLMD_KVM_IMAGE_PATH_PREFIX}/images"

# Files
readonly VLLMD_KVM_VFIO_FILEPATH="/etc/modprobe.d/vllmd-vfio.conf"
readonly VLLMD_KVM_MODULES_FILEPATH="/etc/modules-load.d/vllmd-modules.conf"
readonly VLLMD_KVM_UDEV_RULES_FILEPATH="/etc/udev/rules.d/99-vllmd.rules"
readonly VLLMD_KVM_SYSCTL_FILEPATH="/etc/sysctl.d/vllmd-sysctl.conf"
readonly VLLMD_KVM_GRUB_FILEPATH="/etc/default/grub.d/vllmd-grub.conf"

# Safety limits
readonly VLLMD_KVM_MAX_GPU_COUNT=8
readonly VLLMD_KVM_MIN_MEMORY_GB=4
readonly VLLMD_KVM_MAX_MEMORY_GB=2048
readonly VLLMD_KVM_DEFAULT_MEMORY_GB=16

# ===== Helper Functions =====

print_banner() {
    echo "============================================="
    echo "VLLMD Virtualization Setup"
    echo "Proof-of-Concept Script"
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "*** DRY RUN MODE - No changes will be made ***"
    fi
    echo "============================================="
    echo
}

enable_user_linger() {
    next_step "Enabling user linger for persistent user services"
    
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "Would check if linger is enabled for current user"
        echo "Would enable linger if not already enabled"
        return 0
    fi
    
    log_info "Checking if linger is enabled for user ${USER}..."
    
    # Check if linger is already enabled
    if loginctl show-user "${USER}" | grep -q "Linger=no"; then
        log_info "Linger is not enabled. Enabling linger for user ${USER}..."
        elevate loginctl enable-linger "${USER}"
        log_info "Linger enabled. User services will persist after logout."
    else
        log_info "Linger is already enabled for user ${USER}."
    fi
    
    return 0
}

next_step() {
    STEP_NUMBER=$((STEP_NUMBER + 1))
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "STEP ${STEP_NUMBER}: $*"
    fi
}

log() {
    local level="$1"
    local message="$2"
    echo "[${level}] ${message}"
}

log_info() {
    log "INFO" "$1"
}

log_warn() {
    log "WARNING" "$1" >&2
}

log_error() {
    log "ERROR" "$1" >&2
}

ask_continue() {
    local prompt="$1"
    local default="${2:-y}"
    
    # If auto-yes is enabled, return success
    if [[ "${AUTO_YES}" -eq 1 ]]; then
        return 0
    fi
    
    # If dry-run is enabled, just show what would be asked
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "Would prompt: ${prompt} [${default}]"
        if [[ "${default}" =~ [Yy] ]]; then
            echo "Would use default: yes"
            return 0
        else
            echo "Would use default: no"
            return 1
        fi
    fi
    
    local yn
    read -p "${prompt} [${default}] " yn
    
    case "${yn:-$default}" in
        [Yy]*) return 0 ;;
        [Nn]*) return 1 ;;
        *) 
            if [[ "$default" =~ [Yy] ]]; then
                return 0
            else
                return 1
            fi
            ;;
    esac
}

elevate() {
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "Would execute with sudo: $*"
        return 0
    fi
    
    if [[ $EUID -ne 0 ]]; then
        log_info "Executing with sudo: $*"
        sudo "$@"
    else
        log_info "Executing: $*"
        "$@"
    fi
}

check_command() {
    local cmd="$1"
    if ! command -v "${cmd}" &> /dev/null; then
        log_error "Required command '${cmd}' not found"
        return 1
    fi
    return 0
}

make_parent_dirs() {
    local file_path="$1"
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "Would create parent directories for ${file_path}"
        return 0
    fi
    mkdir --parents "$(dirname "${file_path}")"
}

write_file() {
    local file_path="$1"
    local content="$2"
    local need_sudo="${3:-0}"
    
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        if [[ "${need_sudo}" -eq 1 ]]; then
            echo "Would create file with sudo: ${file_path}"
        else
            echo "Would create file: ${file_path}"
        fi
        echo "Content would be:"
        echo "----------------------------------------"
        echo "${content}"
        echo "----------------------------------------"
        return 0
    fi
    
    # Create parent directories if needed
    make_parent_dirs "${file_path}"
    
    if [[ "${need_sudo}" -eq 1 ]]; then
        log_info "Creating file ${file_path} (with sudo)"
        echo "${content}" | elevate tee "${file_path}" > /dev/null
    else
        log_info "Creating file ${file_path}"
        echo "${content}" > "${file_path}"
    fi
    
    # Add to created files list
    CREATED_FILES+=("${file_path}")
}

modify_file() {
    local file_path="$1"
    local content="$2"
    local need_sudo="${3:-0}"
    
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        if [[ "${need_sudo}" -eq 1 ]]; then
            echo "Would modify file with sudo: ${file_path}"
        else
            echo "Would modify file: ${file_path}"
        fi
        echo "Content would be:"
        echo "----------------------------------------"
        echo "${content}"
        echo "----------------------------------------"
        return 0
    fi
    
    if [[ "${need_sudo}" -eq 1 ]]; then
        log_info "Modifying file ${file_path} (with sudo)"
        echo "${content}" | elevate tee "${file_path}" > /dev/null
    else
        log_info "Modifying file ${file_path}"
        echo "${content}" > "${file_path}"
    fi
    
    # Add to created files list if not already there
    if [[ ! " ${CREATED_FILES[*]} " =~ " ${file_path} " ]]; then
        CREATED_FILES+=("${file_path}")
    fi
}

file_exists() {
    local file_path="$1"
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "Would check if file exists: ${file_path}"
        return 1  # In dry-run, assume file doesn't exist to show all steps
    fi
    
    [[ -f "${file_path}" ]]
}

# ===== System Validation Functions =====

check_cpu_virtualization() {
    next_step "Checking CPU virtualization support"
    
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "Would check for VMX/SVM in /proc/cpuinfo"
        return 0
    fi
    
    log_info "Checking CPU virtualization support..."
    
    if ! grep -q -E 'vmx|svm' /proc/cpuinfo; then
        log_error "CPU virtualization extensions not found."
        log_error "This system does not support hardware virtualization."
        return 1
    fi
    
    log_info "CPU virtualization extensions detected"
    return 0
}

check_iommu() {
    next_step "Checking IOMMU support"
    
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "Would check for IOMMU support using lspci and kernel parameters"
        return 0
    fi
    
    log_info "Checking IOMMU support..."
    
    # Method 1: Check if IOMMU hardware exists using lspci
    if lspci -v | grep -i "IOMMU" > /dev/null; then
        log_info "IOMMU hardware detected"
        
        # Method 2: Check if IOMMU groups exist (which means IOMMU is enabled)
        if [[ -d "/sys/kernel/iommu_groups" ]]; then
            local group_count=$(find /sys/kernel/iommu_groups/ -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
            if [[ $group_count -gt 0 ]]; then
                log_info "IOMMU is enabled with $group_count IOMMU groups"
                return 0
            fi
        fi
        
        # Method 3: Check boot parameters for IOMMU flags
        if grep -E "intel_iommu=on|amd_iommu=on" /proc/cmdline > /dev/null; then
            log_info "IOMMU is enabled via kernel boot parameters"
            return 0
        fi
        
        # If we have IOMMU hardware but no groups, it's not enabled
        log_error "IOMMU hardware detected but not enabled."
        log_error "Add 'intel_iommu=on' or 'amd_iommu=on' to kernel parameters."
        return 1
    else
        # No IOMMU hardware detected
        log_error "No IOMMU hardware detected. Your system may not support GPU passthrough."
        return 1
    fi
}

check_cloud_hypervisor() {
    next_step "Checking for cloud-hypervisor"
    
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "Would check if cloud-hypervisor is installed"
        return 0
    fi
    
    log_info "Checking for cloud-hypervisor..."
    
    if ! check_command "cloud-hypervisor"; then
        log_error "cloud-hypervisor is not installed."
        log_error "Please install cloud-hypervisor v40.0 or later."
        log_error "https://github.com/cloud-hypervisor/cloud-hypervisor/releases"
        return 1
    fi
    
    # Check version with more robust pattern matching
    local version
    version=$(cloud-hypervisor --version | grep -oP 'cloud-hypervisor v\K[0-9]+\.[0-9]+(-dirty)?' || echo "unknown")
    log_info "Found cloud-hypervisor version: ${version}"
    
    if [[ "${version}" == "unknown" ]]; then
        log_warn "Could not determine cloud-hypervisor version."
        if ! ask_continue "Continue anyway?"; then
            return 1
        fi
    fi
    
    return 0
}

check_numactl() {
    next_step "Checking for numactl"
    
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "Would check if numactl is installed"
        return 0
    fi
    
    log_info "Checking for numactl..."
    
    if ! check_command "numactl"; then
        log_error "numactl is not installed."
        log_error "Please install numactl for NUMA topology detection."
        return 1
    fi
    
    log_info "numactl is available"
    return 0
}

# ===== Resource Discovery Functions =====

discover_gpus() {
    next_step "Discovering NVIDIA GPUs"
    
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "Would search for NVIDIA GPUs using lspci"
        echo "Would identify GPU models and map to known properties"
        return 0
    fi
    
    log_info "Discovering NVIDIA GPUs..."
    
    declare -a gpu_list=()
    local vendor_id="10de" # NVIDIA vendor ID
    
    # Use lspci to find all NVIDIA GPUs
    local gpu_devices
    gpu_devices=$(lspci -nn | grep -i "\[${vendor_id}:" | sort) || true
    
    if [[ -z "${gpu_devices}" ]]; then
        log_warn "No NVIDIA GPUs found in the system."
        return 0
    fi
    
    echo "Found NVIDIA GPUs:"
    # Use mapfile to avoid the subshell issue that causes variables to not persist
    mapfile -t gpu_device_lines <<< "${gpu_devices}"
    
    for line in "${gpu_device_lines[@]}"; do
        local pci_address device_id
        pci_address=$(echo "${line}" | awk '{print $1}')
        
        # Extract device ID from the PCI ID format [VVVV:DDDD]
        device_id=$(echo "${line}" | grep -oP '\[[0-9a-f]{4}:[0-9a-f]{4}\]' | grep -oP '[0-9a-f]{4}(?=\])')
        
        # Format to standard PCI address format (with leading zeros)
        pci_address=$(printf "0000:%s" "${pci_address}")
        
        # Look up the GPU model and details from our known list
        local gpu_info="Unknown"
        for known_gpu in "${NVIDIA_GPUS[@]}"; do
            local known_id model memory cc
            IFS=: read -r known_id model memory cc <<< "${known_gpu}"
            if [[ "${device_id}" == "${known_id}" ]]; then
                gpu_info="${model} (${memory}GB, CC${cc})"
                break
            fi
        done
        
        echo "  ${pci_address}: ${gpu_info}"
        gpu_list+=("${pci_address}")
    done
    
    if [[ ${#gpu_list[@]} -eq 0 ]]; then
        log_warn "No supported NVIDIA GPUs found."
        return 0
    fi
    
    # Export the GPU list to make it available globally
    export GPU_LIST=("${gpu_list[@]}")
    
    echo "Found ${#gpu_list[@]} NVIDIA GPUs"
    return 0
}

discover_numa_topology() {
    next_step "Discovering NUMA topology"
    
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "Would examine NUMA topology using numactl"
        echo "Would map CPUs and GPUs to NUMA nodes"
        return 0
    fi
    
    log_info "Discovering NUMA topology..."
    
    # Get NUMA node count
    local node_count
    node_count=$(numactl --hardware | grep "available:" | awk '{print $2}')
    
    echo "System has ${node_count} NUMA node(s)"
    
    # For each NUMA node, get CPUs
    for ((node=0; node<node_count; node++)); do
        local cpus
        cpus=$(numactl --hardware | grep -A1 "node ${node} cpus:" | tail -1)
        echo "  Node ${node} CPUs: ${cpus}"
        
        # Find GPUs in this NUMA node
        echo "  Node ${node} GPUs:"
        for device in /sys/bus/pci/devices/*; do
            if [[ -f "${device}/vendor" && "$(cat "${device}/vendor")" == "0x10de" ]]; then
                local dev_numa
                dev_numa=$(cat "${device}/numa_node" 2>/dev/null || echo "-1")
                if [[ "${dev_numa}" == "${node}" ]]; then
                    local addr model
                    addr=$(basename "${device}")
                    model=$(lspci -s "${addr#0000:}" -nn | grep -o '\[.*\]' || echo "Unknown")
                    echo "    ${addr}: ${model}"
                fi
            fi
        done
    done
    
    return 0
}

# ===== Configuration Functions =====

setup_vfio() {
    next_step "Setting up VFIO for GPU passthrough"
    
    # Create module configuration
    local modules_content="# VLLMD VFIO modules
vfio
vfio_iommu_type1
vfio_pci
vfio_virqfd"

    # Create VFIO configuration
    # We avoid hardcoding device IDs here - we'll bind at runtime
    local vfio_content="# VLLMD VFIO configuration
options vfio-pci ids=
options vfio_iommu_type1 allow_unsafe_interrupts=0
options vfio_pci disable_idle_d3=1"

    # Create udev rules for secure device access
    local udev_content="# VLLMD VFIO device permissions
SUBSYSTEM==\"vfio\", OWNER=\"root\", GROUP=\"kvm\", MODE=\"0640\"
ACTION==\"add\", SUBSYSTEM==\"vfio\", KERNEL==\"vfio\", NAME=\"vfio/vfio\", MODE=\"0640\"
ACTION==\"add\", SUBSYSTEM==\"vfio\", KERNEL==\"[0-9]*\", NAME=\"vfio/%k\", MODE=\"0640\""

    # Write config files with sudo
    local config_updated=0
    
    if ! file_exists "${VLLMD_KVM_MODULES_FILEPATH}" || ask_continue "Overwrite existing ${VLLMD_KVM_MODULES_FILEPATH}?"; then
        write_file "${VLLMD_KVM_MODULES_FILEPATH}" "${modules_content}" 1
        config_updated=1
    fi
    
    if ! file_exists "${VLLMD_KVM_VFIO_FILEPATH}" || ask_continue "Overwrite existing ${VLLMD_KVM_VFIO_FILEPATH}?"; then
        write_file "${VLLMD_KVM_VFIO_FILEPATH}" "${vfio_content}" 1
        config_updated=1
    fi
    
    if ! file_exists "${VLLMD_KVM_UDEV_RULES_FILEPATH}" || ask_continue "Overwrite existing ${VLLMD_KVM_UDEV_RULES_FILEPATH}?"; then
        write_file "${VLLMD_KVM_UDEV_RULES_FILEPATH}" "${udev_content}" 1
        config_updated=1
    fi
    
    log_info "VFIO configuration created."
    
    if [[ "${config_updated}" -eq 1 ]]; then
        if [[ "${DRY_RUN}" -eq 1 ]]; then
            echo "Would inform that a reboot is normally required for VFIO changes"
            if [[ "${NO_REBOOT}" -eq 1 ]]; then
                echo "Would skip reboot request due to --no-reboot flag"
            else
                echo "Would recommend system reboot before continuing"
            fi
        elif [[ "${NO_REBOOT}" -eq 1 ]]; then
            log_info "Reboot request skipped due to --no-reboot flag."
            log_info "Loading VFIO modules to attempt partial activation without reboot..."
            elevate modprobe vfio || true
            elevate modprobe vfio_iommu_type1 || true
            elevate modprobe vfio_pci || true
            elevate modprobe vfio_virqfd || true
            log_warn "VFIO changes may not take full effect until reboot."
        else
            log_info "A reboot is required for VFIO changes to take effect."
            log_info "Please reboot your system and run this script again."
            exit 0
        fi
    fi
    
    return 0
}

setup_hugepages() {
    next_step "Setting up hugepages for improved memory performance"
    
    # Calculate default hugepages based on system memory (in GB)
    local mem_kb
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        mem_kb=67108864  # Simulate a system with 64GB of RAM
    else
        mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    fi
    
    local mem_gb=$((mem_kb / 1024 / 1024))
    
    # Default to 50% of system memory for hugepages
    local hugepages_gb=$((mem_gb / 2))
    
    # Ensure we're within reasonable limits
    if [[ "${hugepages_gb}" -lt "${MIN_MEMORY_GB}" ]]; then
        hugepages_gb="${MIN_MEMORY_GB}"
    elif [[ "${hugepages_gb}" -gt "${MAX_MEMORY_GB}" ]]; then
        hugepages_gb="${MAX_MEMORY_GB}"
    fi
    
    # 2MB hugepages
    local page_size_kb=2048
    local num_hugepages=$(( hugepages_gb * 1024 * 1024 / page_size_kb ))
    
    # Create sysctl configuration
    local sysctl_content="# VLLMD hugepage configuration
vm.nr_hugepages = ${num_hugepages}
# Disable transparent hugepages for predictable performance
vm.swappiness = 0"

    # Create GRUB configuration for persistent hugepages across reboots
    local grub_content="# VLLMD hugepage GRUB configuration
GRUB_CMDLINE_LINUX=\"\${GRUB_CMDLINE_LINUX} default_hugepagesz=2M hugepagesz=2M hugepages=${num_hugepages}\""

    if ! file_exists "${VLLMD_KVM_SYSCTL_FILEPATH}" || ask_continue "Overwrite existing ${VLLMD_KVM_SYSCTL_FILEPATH}?"; then
        write_file "${VLLMD_KVM_SYSCTL_FILEPATH}" "${sysctl_content}" 1
    fi
    
    if ! file_exists "${VLLMD_KVM_GRUB_FILEPATH}" || ask_continue "Overwrite existing ${VLLMD_KVM_GRUB_FILEPATH}?"; then
        write_file "${VLLMD_KVM_GRUB_FILEPATH}" "${grub_content}" 1
        
        if [[ "${DRY_RUN}" -eq 1 ]]; then
            echo "Would update GRUB configuration with update-grub"
            if [[ "${NO_REBOOT}" -eq 1 ]]; then
                echo "Would skip reboot request due to --no-reboot flag"
            else
                echo "Would recommend system reboot before continuing"
            fi
        elif [[ "${NO_REBOOT}" -eq 1 ]]; then
            log_info "Updating GRUB configuration..."
            elevate update-grub
            log_info "Reboot request skipped due to --no-reboot flag."
            log_warn "Hugepage GRUB changes won't take full effect until reboot."
        else
            log_info "Updating GRUB configuration..."
            elevate update-grub
            log_info "A reboot is required for hugepage changes to take effect."
            log_info "Please reboot your system and run this script again."
            exit 0
        fi
    fi
    
    # Apply sysctl settings immediately if requested
    if ask_continue "Apply hugepage settings now?"; then
        if [[ "${DRY_RUN}" -eq 1 ]]; then
            echo "Would apply sysctl settings immediately"
            echo "Would set vm.nr_hugepages=${num_hugepages}"
        else
            elevate sysctl --system
            elevate sysctl -w vm.nr_hugepages="${num_hugepages}"
            
            # Check if they were applied correctly
            local current_hugepages
            current_hugepages=$(cat /proc/sys/vm/nr_hugepages)
            if [[ "${current_hugepages}" -lt "${num_hugepages}" ]]; then
                log_warn "Could not allocate all requested hugepages (${current_hugepages} < ${num_hugepages})"
                log_warn "This might be due to memory fragmentation. A reboot may help."
            else
                log_info "Successfully allocated ${current_hugepages} hugepages"
            fi
        fi
    fi
    
    return 0
}

create_directory_structure() {
    next_step "Creating VLLMD directory structure"
    
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "Would create directories:"
        echo "  ${VLLMD_KVM_CONFIG_PATH}"
        echo "  ${VLLMD_KVM_SYSTEMD_PATH}"
        echo "  ${VLLMD_KVM_RUN_PATH}"
        echo "  ${VLLMD_KVM_LOG_PATH}"
        echo "  ${VLLMD_KVM_IMAGE_PATH}"
        return 0
    fi
    
    log_info "Creating VLLMD directory structure..."
    
    mkdir --parents "${VLLMD_KVM_CONFIG_PATH}"
    mkdir --parents "${VLLMD_KVM_SYSTEMD_PATH}"
    mkdir --parents "${VLLMD_KVM_RUN_PATH}"
    mkdir --parents "${VLLMD_KVM_LOG_PATH}"
    mkdir --parents "${VLLMD_KVM_IMAGE_PATH}"
    
    log_info "Directory structure created"
    return 0
}

# ===== VM Setup Functions =====

create_systemd_service_template() {
    next_step "Creating systemd service templates"
    
    # Create the pre-start service template
    local pre_start_service_filepath="${VLLMD_KVM_SYSTEMD_PATH}/vllmd-kvm-pre-start@.service"
    local pre_start_content="[Unit]
Description=VLLMD Pre-start setup for VM %i
Before=vllmd-kvm@%i.service
Slice=vllmd.slice

[Service]
Type=oneshot
RemainAfterExit=yes
EnvironmentFile=%h/.config/vllmd/%i.conf
ExecStart=/bin/sh -c 'ip link add link \"\${VLLMD_KVM_HOST_NET}\" name macvtap\${VLLMD_KVM_ID} type macvtap'
ExecStart=/bin/sh -c 'ip link set macvtap\${VLLMD_KVM_ID} up'
ExecStop=/bin/sh -c 'ip link delete macvtap\${VLLMD_KVM_ID}'

[Install]
WantedBy=default.target"

    # Create the main VM service template
    local vm_service_filepath="${VLLMD_KVM_SYSTEMD_PATH}/vllmd-kvm@.service"
    local vm_content="[Unit]
Description=VLLMD Virtual Machine %i
Requires=vllmd-kvm-pre-start@%i.service
After=vllmd-kvm-pre-start@%i.service
Slice=vllmd.slice

[Service]
Type=simple
Environment=VLLMD_KVM_RUNTIME_PATH=%h/.local/run/vllmd/%i
Environment=VLLMD_KVM_LOG_FILEPATH=%h/.local/log/vllmd/%i.log
EnvironmentFile=%h/.config/vllmd/%i.conf

ExecStartPre=/bin/sh -c 'mkdir --parents \"\${VLLMD_KVM_RUNTIME_PATH}\"'
ExecStart=cloud-hypervisor \\
    --api-socket \"\${VLLMD_KVM_RUNTIME_PATH}/api.sock\" \\
    --kernel \"\${VLLMD_KVM_KERNEL_FILEPATH}\" \\
    --disk path=\"\${VLLMD_KVM_DISK_FILEPATH}\" \\
          path=\"\${VLLMD_KVM_CLOUDINIT_DISK}\",readonly=on \\
    --cpus boot=\"\${VLLMD_KVM_CPUS}\" \\
    --memory \"\${VLLMD_KVM_MEMORY}\" \\
    --serial tty \\
    --console off \\
    --net fd=3,num_queues=8 3<>/dev/tap\$(cat /sys/class/net/macvtap\${VLLMD_KVM_ID}/ifindex) \\
    --device path=\"\${VLLMD_KVM_GPU_DEVICE}\" \\
    --log-file \"\${VLLMD_KVM_LOG_FILEPATH}\" \\
    --cmdline \"\${VLLMD_KVM_CMDLINE}\"

ExecStop=/bin/sh -c 'if [ -S \"\${VLLMD_KVM_RUNTIME_PATH}/api.sock\" ]; then \\
    curl --unix-socket \"\${VLLMD_KVM_RUNTIME_PATH}/api.sock\" \\
      -X PUT \"http://localhost/api/v1/vm.shutdown\"; \\
    timeout 30 bash -c \"while [ -S \\\"\${VLLMD_KVM_RUNTIME_PATH}/api.sock\\\" ]; do \\
        sleep 1; \\
    done\"; \\
fi'
ExecStopPost=/bin/sh -c 'rm -rf \"\${VLLMD_KVM_RUNTIME_PATH}\"'

Restart=on-failure
RestartSec=5
TimeoutStartSec=300
TimeoutStopSec=30

[Install]
WantedBy=default.target"

    # Write service files
    if ! file_exists "${pre_start_service_filepath}" || ask_continue "Overwrite existing ${pre_start_service_filepath}?"; then
        write_file "${pre_start_service_filepath}" "${pre_start_content}"
    fi
    
    if ! file_exists "${vm_service_filepath}" || ask_continue "Overwrite existing ${vm_service_filepath}?"; then
        write_file "${vm_service_filepath}" "${vm_content}"
    fi
    
    log_info "Systemd service templates created"
    return 0
}

create_vm_config() {
    local vm_name="$1"
    local gpu_address="$2"
    local memory_gb="${3:-$DEFAULT_MEMORY_GB}"
    local cpus="${4:-4}"
    
    next_step "Creating VM configuration for ${vm_name}"
    
    local config_filepath="${VLLMD_KVM_CONFIG_PATH}/${vm_name}.conf"
    local vm_path="${VLLMD_KVM_IMAGE_PATH}/${vm_name}"
    local disk_filepath="${vm_path}/disk.raw"
    
    # Find GPU model from address
    local gpu_model="Unknown"
    local device_id
    
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "Would discover GPU model for address ${gpu_address}"
        gpu_model="NVIDIA A100"
    elif [[ -f "/sys/bus/pci/devices/${gpu_address}/device" ]]; then
        device_id=$(cat "/sys/bus/pci/devices/${gpu_address}/device" | cut -c 3-)
        
        for known_gpu in "${NVIDIA_GPUS[@]}"; do
            local known_id model memory cc
            IFS=: read -r known_id model memory cc <<< "${known_gpu}"
            if [[ "${device_id}" == "${known_id}" ]]; then
                gpu_model="${model}"
                break
            fi
        done
    fi
    
    # Find NUMA node of GPU
    local numa_node=0
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "Would determine NUMA node for GPU"
    elif [[ -f "/sys/bus/pci/devices/${gpu_address}/numa_node" ]]; then
        numa_node=$(cat "/sys/bus/pci/devices/${gpu_address}/numa_node")
        if [[ "${numa_node}" -lt 0 ]]; then
            numa_node=0
        fi
    fi
    
    # Generate a MAC address using a fixed prefix and hash of VM name
    # This ensures deterministic but unique MAC addresses
    local mac_prefix="52:54:00"
    local hash
    hash=$(echo "${vm_name}" | md5sum | head -c 6)
    local mac_suffix
    mac_suffix=$(echo "${hash}" | sed 's/\(..\)/\1:/g' | sed 's/:$//')
    local mac_address="${mac_prefix}:${mac_suffix}"
    
    # Identify default network interface
    local default_interface
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        default_interface="eth0"
    else
        default_interface=$(ip route | grep default | awk '{print $5}' | head -1)
    fi
    
    cat > /dev/null << EOF
# VLLMD VM Configuration for ${vm_name}
# GPU: ${gpu_model} (${gpu_address})
# NUMA Node: ${numa_node}

# VM Identification
VLLMD_KVM_ID="${vm_name}"

# Network Configuration
VLLMD_KVM_HOST_NET="ens8f1"

# Hardware Configuration
VLLMD_KVM_CPUS="${cpus}"
VLLMD_KVM_MEMORY="size=${memory_gb}G,hugepages=on,hugepage_size=2M,shared=on"

# Storage Configuration
VLLMD_KVM_DISK_FILEPATH="${disk_path}"
VLLMD_KVM_CLOUDINIT_DISK="${CLOUDINIT_DISK}"

# Boot Configuration
VLLMD_KVM_KERNEL_FILEPATH="${HYPERVISOR_FW_PATH}"
VLLMD_KVM_CMDLINE="root=/dev/vda1 rw console=ttyS0 hugepagesz=2M hugepages=32768 default_hugepagesz=2M intel_iommu=on iommu=pt"

# GPU Configuration
VLLMD_KVM_GPU_DEVICE="${gpu_address}"
EOF

    local config_content
    config_content=$(cat << EOF
# VLLMD VM Configuration for ${vm_name}
# GPU: ${gpu_model} (${gpu_address})
# NUMA Node: ${numa_node}

# VM Identification
VLLMD_KVM_ID="${vm_name}"

# Network Configuration
VLLMD_KVM_HOST_NET="${default_interface}"

# Hardware Configuration
VLLMD_KVM_CPUS="${cpus}"
VLLMD_KVM_MEMORY="size=${memory_gb}G,hugepages=on,hugepage_size=2M,shared=on"

# Storage Configuration
VLLMD_KVM_DISK_FILEPATH="${disk_path}"
VLLMD_KVM_CLOUDINIT_DISK="${CLOUDINIT_DISK}"

# Boot Configuration
VLLMD_KVM_KERNEL_FILEPATH="${HYPERVISOR_FW_PATH}"
VLLMD_KVM_CMDLINE="root=/dev/vda1 rw console=ttyS0 hugepagesz=2M hugepages=32768 default_hugepagesz=2M intel_iommu=on iommu=pt"

# GPU Configuration
VLLMD_KVM_GPU_DEVICE="${gpu_address}"
EOF
)

    if ! file_exists "${config_filepath}" || ask_continue "Overwrite existing ${config_filepath}?"; then
        write_file "${config_filepath}" "${config_content}"
    else
        log_info "VM configuration not updated (kept existing file)"
    fi
    
    return 0
}

create_disk_image() {
    local vm_name="$1"
    local size_gb="${2:-50}" # This parameter is no longer used since we copy an existing image
    local vm_dir="${IMAGE_DIR}/${vm_name}"
    local disk_path="${vm_dir}/disk.raw"
    
    next_step "Setting up disk image for ${vm_name}"
    
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "Would create VM directory at ${vm_dir}"
        echo "Would check if source raw image exists at ${SOURCE_RAW_IMAGE}"
        echo "Would check if target disk image already exists at ${disk_path}"
        
        if [[ "${DESTRUCTIVE_IMAGE_REPLACE}" -eq 1 ]]; then
            echo "Would copy source image to ${disk_path} (would overwrite if exists due to --destructive-image-replace flag)"
        else
            echo "Would copy source image to ${disk_path} (would skip if already exists)"
        fi
        return 0
    fi
    
    # Check if source image exists
    if [[ ! -f "${SOURCE_RAW_IMAGE}" ]]; then
        log_error "Source raw image '${SOURCE_RAW_IMAGE}' does not exist"
        log_error "Specify a valid source image with --source-raw-image=PATH"
        return 1
    fi
    
    # Create VM directory
    make_parent_dirs "${disk_path}"
    
    # Check if target image already exists
    if [[ -f "${disk_path}" ]]; then
        if [[ "${DESTRUCTIVE_IMAGE_REPLACE}" -eq 1 ]]; then
            log_warn "Disk image ${disk_path} already exists and will be overwritten (--destructive-image-replace specified)"
        else
            log_warn "Disk image ${disk_path} already exists. Skipping copy to prevent data loss."
            log_warn "Use --destructive-image-replace if you want to overwrite existing images."
            return 0
        fi
    fi
    
    log_info "Copying source image '${SOURCE_RAW_IMAGE}' to '${disk_path}'..."
    
    # Copy the source image to the target location
    cp "${SOURCE_RAW_IMAGE}" "${disk_path}"
    
    # Add to created files list
    CREATED_FILES+=("${disk_path}")
    
    log_info "Disk image copied successfully"
    return 0
}

# ===== Known NVIDIA GPU models and their properties =====
# Format: "device_id:model:memory_gb:compute_capability"
NVIDIA_GPUS_ARRAY="2235:A40:48:8.6
20b7:A30:24:8.0
2236:A30:24:8.0 
2237:A40:48:8.6
2238:A10:24:8.6
2239:A16:16:8.6
2330:H100:80:9.0
2420:L4:24:8.9
2230:L40:48:8.9
1EB8:T4:16:7.5
1DB4:V100:32:7.0
2231:RTX6000:48:8.6
1E30:RTX8000:48:7.5
1DB6:GV100:32:7.0"

readarray -t NVIDIA_GPUS <<< "${NVIDIA_GPUS_ARRAY}"

# ===== Main Script =====

create_cloudinit_disk() {
    next_step "Creating cloud-init configuration disk"
    
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "Would check if cloud-init disk exists at ${VLLMD_KVM_CLOUDINIT_FILEPATH}"
        echo "Would create cloud-init disk with user 'sdake' if it doesn't exist"
        return 0
    fi
    
    # Check if cloud-init disk already exists
    if [[ -f "${VLLMD_KVM_CLOUDINIT_FILEPATH}" ]]; then
        log_info "Cloud-init disk already exists at ${VLLMD_KVM_CLOUDINIT_FILEPATH}"
        return 0
    fi
    
    log_info "Creating cloud-init configuration disk at ${VLLMD_KVM_CLOUDINIT_FILEPATH}"
    
    # Create temporary directory for cloud-init files
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Create meta-data file
    cat > "${temp_dir}/meta-data" << EOF
#cloud-config
---
instance-id: vllmd-vm
local-hostname: vllmd-vm
EOF
    
    # Create user-data file
    cat > "${temp_dir}/user-data" << EOF
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
    
    # Create the parent directory if needed
    mkdir -p "$(dirname "${VLLMD_KVM_CLOUDINIT_FILEPATH}")"
    
    # Create FAT filesystem image
    /usr/sbin/mkdosfs -n CIDATA -C "${VLLMD_KVM_CLOUDINIT_FILEPATH}" 8192
    
    # Copy files to the image
    mcopy -oi "${VLLMD_KVM_CLOUDINIT_FILEPATH}" -s "${temp_dir}/user-data" ::
    mcopy -oi "${VLLMD_KVM_CLOUDINIT_FILEPATH}" -s "${temp_dir}/meta-data" ::
    
    # Cleanup
    rm -rf "${temp_dir}"
    
    # Add to created files list
    CREATED_FILES+=("${VLLMD_KVM_CLOUDINIT_FILEPATH}")
    
    log_info "Cloud-init disk created successfully"
    return 0
}

main() {
    print_banner
    
    # Check requirements
    check_cpu_virtualization || return 1
    check_iommu || return 1
    check_cloud_hypervisor || return 1
    check_numactl || return 1
    
    # Discover resources
    discover_gpus
    discover_numa_topology
    
    # Setup environment
    create_directory_structure
    
    # Create cloud-init disk if needed
    create_cloudinit_disk
    
    # Enable user linger for persistent VMs
    enable_user_linger
    
    # System configuration
    if ask_continue "Configure VFIO for GPU passthrough?"; then
        setup_vfio
    fi
    
    if ask_continue "Configure hugepages for memory performance?"; then
        setup_hugepages
    fi
    
    # Create systemd service templates
    create_systemd_service_template
    
    # Create VM config if GPUs are available
    if ask_continue "Create VM configurations?"; then
        echo "Available GPUs:"
        
        # Use the global GPU list we discovered earlier
        local idx=0
        local gpu_list=("${GPU_LIST[@]}")
        
        if [[ "${DRY_RUN}" -eq 1 ]]; then
            echo "  1: 0000:01:00.0 - NVIDIA A30 (24GB)"
            echo "  2: 0000:41:00.0 - NVIDIA A30 (24GB)"
            echo "  3: 0000:61:00.0 - NVIDIA A40 (48GB)"
            echo "  4: 0000:a1:00.0 - NVIDIA A40 (48GB)"
            gpu_list=("0000:01:00.0" "0000:41:00.0" "0000:61:00.0" "0000:a1:00.0")
            
            echo "Would create VM configurations for all 4 GPUs"
            echo "Would use memory: 64GB per VM"
            echo "Would use CPUs: 16 per VM"
            
            for i in {0..3}; do
                local gpu_address="${gpu_list[$i]}"
                local vm_name="vllmd-kvm-${i}"
                local memory_gb=64
                local cpus=16
                
                echo "Would create VM '${vm_name}' with GPU ${gpu_address}"
                echo "Would create VM config file"
                echo "Would create 50GB disk image"
            done
        else
            # Display GPUs using the list from discover_gpus
            if [[ ${#gpu_list[@]} -eq 0 ]]; then
                log_warn "No NVIDIA GPUs found. Using discover_gpus function to try again."
                discover_gpus
                gpu_list=("${GPU_LIST[@]}")
            fi
            
            # Display the GPUs with their details
            for pci_address in "${gpu_list[@]}"; do
                idx=$((idx+1))
                
                # Get device ID from PCI address
                local device_id=""
                if [[ -f "/sys/bus/pci/devices/${pci_address}/device" ]]; then
                    device_id=$(cat "/sys/bus/pci/devices/${pci_address}/device" | cut -c 3-)
                fi
                
                # Look up the GPU model and details
                local gpu_info="Unknown"
                for known_gpu in "${NVIDIA_GPUS[@]}"; do
                    local known_id model memory cc
                    IFS=: read -r known_id model memory cc <<< "${known_gpu}"
                    if [[ "${device_id}" == "${known_id}" ]]; then
                        gpu_info="${model} (${memory}GB, CC${cc})"
                        break
                    fi
                done
                
                echo "  ${idx}: ${pci_address} - ${gpu_info}"
            done
            
            if [[ ${#gpu_list[@]} -eq 0 ]]; then
                log_warn "No NVIDIA GPUs found for VM creation."
            else
                local create_all="n"
                local memory_gb cpus
                
                if [[ "${AUTO_YES}" -eq 1 ]]; then
                    create_all="y"
                    memory_gb="${DEFAULT_MEMORY_GB}"
                    cpus=4
                else
                    read -p "Create VMs for all GPUs? [y/n]: " create_all
                    read -p "Enter memory size in GB for each VM [${DEFAULT_MEMORY_GB}]: " memory_gb
                    memory_gb="${memory_gb:-$DEFAULT_MEMORY_GB}"
                    read -p "Enter number of CPUs for each VM [4]: " cpus
                    cpus="${cpus:-4}"
                fi
                
                if [[ "${create_all}" =~ ^[Yy] ]]; then
                    # Create a VM for each GPU
                    for i in "${!gpu_list[@]}"; do
                        local gpu_address="${gpu_list[$i]}"
                        local vm_name="vllmd-kvm-${i}"
                        
                        create_vm_config "${vm_name}" "${gpu_address}" "${memory_gb}" "${cpus}"
                        create_disk_image "${vm_name}" 50
                        
                        log_info "VM '${vm_name}' configuration created with GPU ${gpu_address}"
                    done
                    
                    log_info "VM configurations created."
                    
                    # Add information about the raw disk images
                    log_info "Note that the disk images are currently empty raw containers."
                    log_info "You'll need to install an operating system onto them before the VMs can boot."
                    log_info "For example, to install Debian:"
                    echo "  1. Download a Debian ISO"
                    echo "  2. Add the ISO to each VM command line with: --disk path=/path/to/debian.iso,readonly=on"
                    echo "  3. Add a boot option: --boot order=cd,hd"
                    echo
                    
                    log_info "To enable all systemd services (required for auto-start at boot):"
                    echo "  systemctl --user daemon-reload"
                    for i in "${!gpu_list[@]}"; do
                        echo "  systemctl --user enable vllmd-kvm@vllmd-kvm-${i}.service"
                    done
                    echo
                    log_info "To start all VMs immediately:"
                    for i in "${!gpu_list[@]}"; do
                        echo "  systemctl --user start vllmd-kvm@vllmd-kvm-${i}.service"
                    done
                    echo
                    log_info "User linger has been enabled, so the VMs will persist after logout."
                else
                    # Allow selecting individual GPUs
                    log_info "Select which GPUs to create VMs for (comma-separated list, e.g., 1,3,5):"
                    local selections
                    read -p "GPU numbers: " selections
                    
                    IFS=',' read -ra selected_indices <<< "$selections"
                    for idx in "${selected_indices[@]}"; do
                        if [[ $idx =~ ^[0-9]+$ && $idx -ge 1 && $idx -le ${#gpu_list[@]} ]]; then
                            local gpu_address="${gpu_list[$((idx-1))]}"
                            local vm_name="vllmd-kvm-$((idx-1))"
                            
                            create_vm_config "${vm_name}" "${gpu_address}" "${memory_gb}" "${cpus}"
                            create_disk_image "${vm_name}" 50
                            
                            log_info "VM '${vm_name}' configuration created with GPU ${gpu_address}"
                        else
                            log_error "Invalid selection: ${idx}"
                        fi
                    done
                    
                    log_info "VM configurations created."
                    
                    # Add information about the raw disk images
                    log_info "Note that the disk images are currently empty raw containers."
                    log_info "You'll need to install an operating system onto them before the VMs can boot."
                    log_info "For example, to install Debian:"
                    echo "  1. Download a Debian ISO"
                    echo "  2. Add the ISO to each VM command line with: --disk path=/path/to/debian.iso,readonly=on"
                    echo "  3. Add a boot option: --boot order=cd,hd"
                    echo
                    
                    log_info "To enable the systemd services (required for auto-start at boot):"
                    echo "  systemctl --user daemon-reload"
                    for idx in "${selected_indices[@]}"; do
                        if [[ $idx =~ ^[0-9]+$ && $idx -ge 1 && $idx -le ${#gpu_list[@]} ]]; then
                            echo "  systemctl --user enable vllmd-kvm@vllmd-kvm-$((idx-1)).service"
                        fi
                    done
                    echo
                    log_info "To start the VMs immediately:"
                    for idx in "${selected_indices[@]}"; do
                        if [[ $idx =~ ^[0-9]+$ && $idx -ge 1 && $idx -le ${#gpu_list[@]} ]]; then
                            echo "  systemctl --user start vllmd-kvm@vllmd-kvm-$((idx-1)).service"
                        fi
                    done
                    echo
                    log_info "User linger has been enabled, so the VMs will persist after logout."
                fi
            fi
        fi
    fi
    
    # Create a summary file with all created files
    if [[ "${DRY_RUN}" -ne 1 ]] && [[ ${#CREATED_FILES[@]} -gt 0 ]]; then
        local summary_filepath="${VLLMD_KVM_CONFIG_PATH}/installation-summary.md"
        local summary_content="# VLLMD Installation Summary\n\n"
        summary_content+="Installation completed on $(date '+%Y-%m-%d %H:%M:%S')\n\n"
        summary_content+="## Created Files\n\n"
        
        for file in "${CREATED_FILES[@]}"; do
            summary_content+="- \`${file}\`\n"
        done
        
        echo -e "${summary_content}" > "${summary_filepath}"
        log_info "Installation summary saved to ${summary_filepath}"
        CREATED_FILES+=("${summary_filepath}")
    fi
    
    log_info "VLLMD setup completed"
    return 0
}

# Run the main function
main "$@"
