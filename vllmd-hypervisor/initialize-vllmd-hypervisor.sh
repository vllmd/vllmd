#!/usr/bin/env bash
#
# initialize-vllmd-hypervisor.sh - Proof-of-concept script for setting up VLLMD hypervisor
#
# This script implements the core functionality for deploying cloud-hypervisor
# VMs optimized for inference workloads.
#
# Security note: This script requires sudo access for specific operations
# but follows the principle of least privilege by only using elevated
# permissions where absolutely necessary.
#
# Usage:
#   bash initialize-vllmd-hypervisor.sh [OPTIONS]
#
# Options:
#   --dry-run                  Show what would be done without making any changes
#   --yes                      Automatically use defaults without prompting
#   --no-reboot                Skip reboot requests and continue script execution
#   --destructive-image-replace Allow overwriting existing disk images
#   --image-prefix=PATH        Set custom path for VM images (default: $HOME/.local/share/vllmd)
#   --source-raw-image=PATH    Path to source raw image file (default: $HOME/.local/share/vllmd/vllmd-hypervisor-runtime.raw)
#   --hypervisor-fw=PATH       Path to hypervisor firmware (default: $HOME/.local/share/vllmd/hypervisor-fw)
#   --config-image=PATH       Path to VM configuration disk image (default: $HOME/.local/share/vllmd/config-image.raw)
#   --gpu-blocklist=LIST       Comma-separated list of GPU addresses to exclude (e.g., "0000:01:00.0,0000:02:00.0")
#   --help                     Display this help message
#
# Example:
#   bash initialize-vllmd-hypervisor.sh --dry-run
#   bash initialize-vllmd-hypervisor.sh --yes
#   bash initialize-vllmd-hypervisor.sh --no-reboot
#   bash initialize-vllmd-hypervisor.sh --destructive-image-replace
#   bash initialize-vllmd-hypervisor.sh --gpu-blocklist="0000:61:00.0,0000:a1:00.0"
#   bash initialize-vllmd-hypervisor.sh --image-prefix=/custom/path --source-raw-image=/custom/path/runtime.raw --hypervisor-fw=/custom/path/hypervisor-fw

set -euo pipefail

# ===== Command Line Processing =====
DRY_RUN=0
AUTO_YES=0
NO_REBOOT=0
DESTRUCTIVE_IMAGE_REPLACE=0
STEP_NUMBER=0
VLLMD_RUNTIME_IMAGE_PREFIX_PATH="${HOME}/.local/share/vllmd"
VLLMD_RUNTIME_SOURCE_RAW_FILEPATH="${HOME}/.local/share/vllmd/vllmd-hypervisor-runtime.raw"
VLLMD_RUNTIME_HYPERVISOR_FW_FILEPATH="${HOME}/.local/share/vllmd/hypervisor-fw"
VLLMD_RUNTIME_CONFIG_IMAGE_FILEPATH="${HOME}/.local/share/vllmd/config-image.raw"
VLLMD_RUNTIME_CONFIG_FILE="${HOME}/.config/vllmd/vllmd-hypervisor-runtime-defaults.toml"
GPU_BLOCKLIST=""

# Created files tracking
CREATED_FILES=()

function print_help() {
    sed -n 's/^# //p' "$0" | sed -n '/^Usage:/,/^$/p'
}

# Helper functions for logging
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

# Function to read GPU blocklist from the config file
read_gpu_blocklist_from_config() {
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "Would check for GPU blocklist in configuration file"
        return
    fi
    
    if [[ -f "${VLLMD_RUNTIME_CONFIG_FILE}" ]]; then
        log_info "Reading configuration from ${VLLMD_RUNTIME_CONFIG_FILE}"
        
        # Try to extract gpu_blocklist value using grep and sed
        local config_blocklist
        config_blocklist=$(grep -A 5 "gpu_blocklist" "${VLLMD_RUNTIME_CONFIG_FILE}" | grep -o '".*"' | sed 's/"//g' || echo "")
        
        if [[ -n "${config_blocklist}" ]]; then
            log_info "Found GPU blocklist in configuration file: ${config_blocklist}"
            if [[ -z "${GPU_BLOCKLIST}" ]]; then
                GPU_BLOCKLIST="${config_blocklist}"
                log_info "Using GPU blocklist from configuration file"
            else
                log_info "Command-line GPU blocklist takes precedence over configuration file"
            fi
        fi
    fi
}

# Function to update GPU blocklist in the config file
update_gpu_blocklist_in_config() {
    if [[ -n "${GPU_BLOCKLIST}" ]]; then
        if [[ "${DRY_RUN}" -eq 1 ]]; then
            echo "Would update GPU blocklist in configuration file: ${GPU_BLOCKLIST}"
            return 0
        fi
        
        if [[ ! -f "${VLLMD_RUNTIME_CONFIG_FILE}" ]]; then
            log_info "Configuration file does not exist, creating it first"
            mkdir -p "$(dirname "${VLLMD_RUNTIME_CONFIG_FILE}")"
            echo "# VLLMD Hypervisor Runtime Default Configuration" > "${VLLMD_RUNTIME_CONFIG_FILE}"
        fi
        
        if grep -q "gpu_blocklist" "${VLLMD_RUNTIME_CONFIG_FILE}"; then
            # Config file exists and has gpu_blocklist entry, update it
            log_info "Updating GPU blocklist in configuration file"
            sed -i "s|gpu_blocklist = .*|gpu_blocklist = \"${GPU_BLOCKLIST}\"|" "${VLLMD_RUNTIME_CONFIG_FILE}"
        elif grep -q "\[gpu\]" "${VLLMD_RUNTIME_CONFIG_FILE}"; then
            # Config file exists and has [gpu] section but no gpu_blocklist entry, add it
            log_info "Adding GPU blocklist to existing [gpu] section"
            sed -i "/\[gpu\]/a gpu_blocklist = \"${GPU_BLOCKLIST}\"" "${VLLMD_RUNTIME_CONFIG_FILE}"
        else
            # Config file exists but doesn't have [gpu] section, add it
            log_info "Adding [gpu] section with GPU blocklist"
            echo -e "\n[gpu]\ngpu_blocklist = \"${GPU_BLOCKLIST}\"" >> "${VLLMD_RUNTIME_CONFIG_FILE}"
        fi
    fi
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
            VLLMD_RUNTIME_IMAGE_PREFIX_PATH="${1#*=}"
            shift
            ;;
        --source-raw-image=*)
            VLLMD_RUNTIME_SOURCE_RAW_FILEPATH="${1#*=}"
            shift
            ;;
        --hypervisor-fw=*)
            VLLMD_RUNTIME_HYPERVISOR_FW_FILEPATH="${1#*=}"
            shift
            ;;
        --config-image=*)
            VLLMD_RUNTIME_CONFIG_IMAGE_FILEPATH="${1#*=}"
            shift
            ;;
        --gpu-blocklist=*)
            GPU_BLOCKLIST="${1#*=}"
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

# Read GPU blocklist from config file if it exists (but command line takes precedence)
read_gpu_blocklist_from_config

# ===== Constants =====

# Directories
readonly VLLMD_RUNTIME_CONFIG_PATH="${HOME}/.config/vllmd"
readonly VLLMD_RUNTIME_SYSTEMD_PATH="${HOME}/.config/systemd/user"
readonly VLLMD_RUNTIME_RUN_PATH="${HOME}/.local/run/vllmd"
readonly VLLMD_RUNTIME_LOG_PATH="${HOME}/.local/log/vllmd"
readonly VLLMD_RUNTIME_IMAGE_PATH="${HOME}/.local/share/vllmd/images"

# Files
readonly VLLMD_RUNTIME_VFIO_FILEPATH="/etc/modprobe.d/vllmd-vfio.conf"
readonly VLLMD_RUNTIME_MODULES_FILEPATH="/etc/modules-load.d/vllmd-modules.conf"
readonly VLLMD_RUNTIME_UDEV_RULES_FILEPATH="/etc/udev/rules.d/00-vllmd.rules"
readonly VLLMD_RUNTIME_SYSCTL_FILEPATH="/etc/sysctl.d/vllmd-sysctl.conf"
readonly VLLMD_RUNTIME_GRUB_FILEPATH="/etc/default/grub.d/vllmd-grub.conf"

# Safety limits
readonly VLLMD_RUNTIME_MAX_GPU_COUNT=8
readonly VLLMD_RUNTIME_MIN_MEMORY_GB=4
readonly VLLMD_RUNTIME_MAX_MEMORY_GB=2048
readonly VLLMD_RUNTIME_DEFAULT_MEMORY_GB=16

# ===== Helper Functions =====

print_banner() {
    echo "============================================="
    echo "VLLMD Virtualization Setup"
    echo "Proof-of-Concept Script"
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "*** DRY RUN MODE - No changes will be made ***"
    fi
    echo "============================================="
    echo "This script configures a fully rootless virtualization environment"
    echo "Uses vllmd-hypervisor exclusively for VM management"
    echo "Device access is provided through KVM group membership"
    echo "============================================="
    echo
}

enable_user_linger() {
    next_step "Enabling user linger for persistent user services"
    
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "Would check if linger is enabled for current user"
        echo "Would enable linger if not already enabled"
        echo "Would check if user is in the kvm group"
        echo "Would add user to kvm group if needed"
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
    
    # Check if user is in the kvm group
    log_info "Checking if user ${USER} is in the kvm group..."
    if ! groups "${USER}" | grep -q "\bkvm\b"; then
        log_info "Adding user ${USER} to the kvm group..."
        elevate usermod -aG kvm "${USER}"
        log_info "User added to kvm group. You may need to log out and log back in for this to take effect."
    else
        log_info "User ${USER} is already in the kvm group."
    fi
    
    return 0
}

next_step() {
    STEP_NUMBER=$((STEP_NUMBER + 1))
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "STEP ${STEP_NUMBER}: $*"
    fi
}

# Logging functions are already defined at the top of the script

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

check_cap_tools() {
    next_step "Checking for capability tools"
    
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "Would check if /usr/sbin/getcap and /usr/sbin/setcap are installed"
        return 0
    fi
    
    log_info "Checking for capability tools..."
    
    if [[ ! -x "/usr/sbin/getcap" ]]; then
        log_error "/usr/sbin/getcap is not installed or not executable."
        log_error "Please install the libcap2-bin package:"
        log_error "sudo apt-get install libcap2-bin"
        return 1
    fi
    
    if [[ ! -x "/usr/sbin/setcap" ]]; then
        log_error "/usr/sbin/setcap is not installed or not executable."
        log_error "Please install the libcap2-bin package:"
        log_error "sudo apt-get install libcap2-bin"
        return 1
    fi
    
    log_info "Capability tools are available"
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

check_vllmd_hypervisor() {
    next_step "Checking for vllmd-hypervisor"
    
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "Would check if vllmd-hypervisor launcher is installed"
        echo "Would verify vllmd-hypervisor has cap_net_admin capability"
        return 0
    fi
    
    log_info "Checking for vllmd-hypervisor launcher..."
    
    if ! check_command "vllmd-hypervisor"; then
        log_error "vllmd-hypervisor is not installed."
        log_error "Please install vllmd-hypervisor by building from the Rust codebase."
        log_error "See: /home/arnold/repos/vllmd/rust/vllmd-hypervisor"
        return 1
    fi
    
    # Check basic functionality
    if ! vllmd-hypervisor --help &>/dev/null; then
        log_warn "Could not verify vllmd-hypervisor functionality."
        if ! ask_continue "Continue anyway?"; then
            return 1
        fi
    fi
    
    # Check if vllmd-hypervisor has the required capability
    log_info "Checking if vllmd-hypervisor has the required network capabilities..."
    
    local vh_path
    vh_path=$(which vllmd-hypervisor)
    log_info "vllmd-hypervisor path: ${vh_path}"
    
    local has_cap
    local getcap_output
    getcap_output=$(/usr/sbin/getcap "${vh_path}" 2>/dev/null || echo "")
    log_info "getcap output: \"${getcap_output}\""
    has_cap=$(echo "${getcap_output}" | grep -q "cap_net_admin+ep" && echo "yes" || echo "no")
    
    if [[ "${has_cap}" == "no" ]]; then
        log_warn "vllmd-hypervisor does not have the required network capabilities."
        log_warn "To fix this, you need to run:"
        log_warn "sudo setcap cap_net_admin+ep ${vh_path}"
        
        if ask_continue "Set cap_net_admin capability now?"; then
            log_info "Setting cap_net_admin capability on vllmd-hypervisor (requires sudo)..."
            
            # Use sudo for setcap as it requires root privileges
            log_info "Running: sudo setcap cap_net_admin+ep ${vh_path}"
            sudo setcap cap_net_admin+ep "${vh_path}"
            
            # Verify it worked
            local verify_output
            verify_output=$(/usr/sbin/getcap "${vh_path}" 2>/dev/null || echo "")
            log_info "Verification getcap output: \"${verify_output}\""
            
            if echo "${verify_output}" | grep -q "cap_net_admin+ep"; then
                log_info "Successfully set cap_net_admin capability on vllmd-hypervisor."
            else
                log_error "Failed to verify cap_net_admin capability on vllmd-hypervisor."
                log_error "Please run the following command manually as root:"
                log_error "sudo setcap cap_net_admin+ep ${vh_path}"
                
                if ! ask_continue "Continue anyway (capability might still be effective)?"; then
                    return 1
                fi
                log_warn "Continuing without verified capability."
            fi
        else
            log_warn "Without the cap_net_admin capability, network functionality may not work correctly."
            if ! ask_continue "Continue anyway?"; then
                return 1
            fi
        fi
    else
        log_info "vllmd-hypervisor has the required network capabilities."
    fi
    
    log_info "vllmd-hypervisor launcher is ready for use."
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
        echo "Would apply GPU blocklist if specified: ${GPU_BLOCKLIST}"
        return 0
    fi
    
    log_info "Discovering NVIDIA GPUs..."
    
    declare -a gpu_list=()
    declare -a blocklist_array=()
    local vendor_id="10de" # NVIDIA vendor ID
    
    # Parse the GPU blocklist if it's specified
    if [[ -n "${GPU_BLOCKLIST}" ]]; then
        IFS=',' read -ra blocklist_array <<< "${GPU_BLOCKLIST}"
        log_info "GPU blocklist contains ${#blocklist_array[@]} entries: ${GPU_BLOCKLIST}"
    fi
    
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
        
        # Check if this GPU is in the blocklist
        local is_blocked=0
        for blocked_gpu in "${blocklist_array[@]}"; do
            if [[ "${pci_address}" == "${blocked_gpu}" ]]; then
                is_blocked=1
                break
            fi
        done
        
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
        
        if [[ "${is_blocked}" -eq 1 ]]; then
            echo "  ${pci_address}: ${gpu_info} [BLOCKED - in blocklist]"
        else
            echo "  ${pci_address}: ${gpu_info}"
            gpu_list+=("${pci_address}")
        fi
    done
    
    if [[ ${#gpu_list[@]} -eq 0 ]]; then
        log_warn "No usable NVIDIA GPUs found (all GPUs may be blocklisted)."
        return 0
    fi
    
    # Export the GPU list to make it available globally
    export GPU_LIST=("${gpu_list[@]}")
    
    local blocked_count=$((${#gpu_device_lines[@]} - ${#gpu_list[@]}))
    if [[ "${blocked_count}" -gt 0 ]]; then
        echo "Found ${#gpu_list[@]} usable NVIDIA GPUs (${blocked_count} blocked)"
    else
        echo "Found ${#gpu_list[@]} NVIDIA GPUs"
    fi
    
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
    local udev_content="# Consolidated VLLMD rules for devices
# Combines all rules for VFIO, tap, and PCI devices
# These rules enable fully rootless operation through group permissions

# VFIO device permissions - KVM group access
SUBSYSTEM==\"vfio\", OWNER=\"root\", GROUP=\"kvm\", MODE=\"0660\"
ACTION==\"add\", SUBSYSTEM==\"vfio\", KERNEL==\"vfio\", NAME=\"vfio/vfio\", MODE=\"0660\"
ACTION==\"add\", SUBSYSTEM==\"vfio\", KERNEL==\"[0-9]*\", NAME=\"vfio/%k\", MODE=\"0660\"

# Tap device permissions - KVM group access 
SUBSYSTEM==\"tap\", GROUP=\"kvm\", MODE=\"0660\"
KERNEL==\"tap[0-9]*\", GROUP=\"kvm\", MODE=\"0660\"

# PCI device permissions for NVIDIA GPUs - KVM group access
SUBSYSTEM==\"pci\", ATTR{vendor}==\"0x10de\", GROUP=\"kvm\", MODE=\"0660\"

# Hugepages access for KVM group
SUBSYSTEM==\"memory\", KERNEL==\"hugepages\", GROUP=\"kvm\", MODE=\"0770\""

    # Write config files with sudo
    local config_updated=0
    
    if ! file_exists "${VLLMD_RUNTIME_MODULES_FILEPATH}" || ask_continue "Overwrite existing ${VLLMD_RUNTIME_MODULES_FILEPATH}?"; then
        write_file "${VLLMD_RUNTIME_MODULES_FILEPATH}" "${modules_content}" 1
        config_updated=1
    fi
    
    if ! file_exists "${VLLMD_RUNTIME_VFIO_FILEPATH}" || ask_continue "Overwrite existing ${VLLMD_RUNTIME_VFIO_FILEPATH}?"; then
        write_file "${VLLMD_RUNTIME_VFIO_FILEPATH}" "${vfio_content}" 1
        config_updated=1
    fi
    
    if ! file_exists "${VLLMD_RUNTIME_UDEV_RULES_FILEPATH}" || ask_continue "Overwrite existing ${VLLMD_RUNTIME_UDEV_RULES_FILEPATH}?"; then
        write_file "${VLLMD_RUNTIME_UDEV_RULES_FILEPATH}" "${udev_content}" 1
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
    if [[ "${hugepages_gb}" -lt "${VLLMD_RUNTIME_MIN_MEMORY_GB}" ]]; then
        hugepages_gb="${VLLMD_RUNTIME_MIN_MEMORY_GB}"
    elif [[ "${hugepages_gb}" -gt "${VLLMD_RUNTIME_MAX_MEMORY_GB}" ]]; then
        hugepages_gb="${VLLMD_RUNTIME_MAX_MEMORY_GB}"
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

    if ! file_exists "${VLLMD_RUNTIME_SYSCTL_FILEPATH}" || ask_continue "Overwrite existing ${VLLMD_RUNTIME_SYSCTL_FILEPATH}?"; then
        write_file "${VLLMD_RUNTIME_SYSCTL_FILEPATH}" "${sysctl_content}" 1
    fi
    
    if ! file_exists "${VLLMD_RUNTIME_GRUB_FILEPATH}" || ask_continue "Overwrite existing ${VLLMD_RUNTIME_GRUB_FILEPATH}?"; then
        write_file "${VLLMD_RUNTIME_GRUB_FILEPATH}" "${grub_content}" 1
        
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
        echo "  ${VLLMD_RUNTIME_CONFIG_PATH}"
        echo "  ${VLLMD_RUNTIME_SYSTEMD_PATH}"
        echo "  ${VLLMD_RUNTIME_RUN_PATH}"
        echo "  ${VLLMD_RUNTIME_LOG_PATH}"
        echo "  ${VLLMD_RUNTIME_IMAGE_PATH}"
        echo "Would create default configuration file"
        return 0
    fi
    
    log_info "Creating VLLMD directory structure..."
    
    mkdir --parents "${VLLMD_RUNTIME_CONFIG_PATH}"
    mkdir --parents "${VLLMD_RUNTIME_SYSTEMD_PATH}"
    mkdir --parents "${VLLMD_RUNTIME_RUN_PATH}"
    mkdir --parents "${VLLMD_RUNTIME_LOG_PATH}"
    mkdir --parents "${VLLMD_RUNTIME_IMAGE_PATH}"
    
    # Create default configuration file
    if [[ ! -f "${VLLMD_RUNTIME_CONFIG_PATH}/vllmd-hypervisor-runtime-defaults.toml" ]]; then
        log_info "Creating default runtime configuration file..."
        
        # Create default TOML configuration
        cat > "${VLLMD_RUNTIME_CONFIG_PATH}/vllmd-hypervisor-runtime-defaults.toml" << EOF
# VLLMD Hypervisor Runtime Default Configuration

[system]
# Base paths for runtime files
image_path = "${VLLMD_RUNTIME_IMAGE_PATH}"
source_raw_filepath = "${VLLMD_RUNTIME_SOURCE_RAW_FILEPATH}"
hypervisor_fw_filepath = "${VLLMD_RUNTIME_HYPERVISOR_FW_FILEPATH}"
config_image_filepath = "${VLLMD_RUNTIME_CONFIG_IMAGE_FILEPATH}"

[runtime]
# Default runtime settings
default_memory_gb = 16
default_cpus = 4
default_disk_size_gb = 50

[gpu]
# GPU configuration
gpu_blocklist = "${GPU_BLOCKLIST}"  # Comma-separated list of GPU addresses to block
EOF
        
        log_info "Default configuration file created at ${VLLMD_RUNTIME_CONFIG_PATH}/vllmd-hypervisor-runtime-defaults.toml"
    else
        log_info "Default configuration file already exists"
    fi
    
    log_info "Directory structure created"
    return 0
}

# ===== VM Setup Functions =====

create_systemd_service_template() {
    next_step "Creating systemd service templates"
    
    # We no longer need the pre-start service since vllmd-hypervisor handles all lifecycle operations
    # This block is kept as a comment for reference
    # local pre_start_service_filepath="${VLLMD_RUNTIME_SYSTEMD_PATH}/vllmd-runtime-pre-start@.service"
    # local pre_start_content="[Unit]
# Description=VLLMD Pre-start setup for Runtime %i
# Before=vllmd-runtime@%i.service
#
# [Service]
# Slice=vllmd.slice
# Type=oneshot
# RemainAfterExit=yes
# EnvironmentFile=%h/.config/vllmd/runtime-%i.env
# ExecStart=/bin/true
#
# [Install]
# WantedBy=default.target"

    # Create the main runtime service template
    # Make sure the parent directory exists
    mkdir -p "${VLLMD_RUNTIME_SYSTEMD_PATH}"
    local runtime_service_filepath="${VLLMD_RUNTIME_SYSTEMD_PATH}/vllmd-runtime@.service"
    local runtime_content="[Unit]
Description=VLLMD Runtime %i

[Service]
# Configure as a non-daemon service that stays in foreground
Type=simple
RemainAfterExit=no
# Environment variables for vllmd-hypervisor launcher
# These variables will be merged with the ones in the EnvironmentFile
Environment=VLLMD_RUNTIME_ID=%i
Environment=VLLMD_RUNTIME_PATH=%h/.local/run/vllmd/%i
Environment=VLLMD_RUNTIME_API_SOCKET=%h/.local/run/vllmd/%i/api.sock
Environment=VLLMD_RUNTIME_LOG_FILEPATH=%h/.local/log/vllmd/%i.log
# Include all configuration from the runtime env file
EnvironmentFile=%h/.config/vllmd/runtime-%i.env

# Create the runtime directory
ExecStartPre=/bin/sh -c 'mkdir --parents %h/.local/run/vllmd/%i'
# vllmd-hypervisor reads all configuration from environment variables
ExecStart=/usr/local/bin/vllmd-hypervisor start
# The vllmd-hypervisor launcher handles device access correctly

# Stop the VM using only environment variables for configuration
ExecStop=/usr/local/bin/vllmd-hypervisor stop
# Clean up the runtime directory
ExecStopPost=/bin/sh -c 'rm -rf %h/.local/run/vllmd/%i'

# Process management configuration
KillMode=process
KillSignal=SIGTERM
SendSIGKILL=yes
Restart=on-failure
RestartSec=5
TimeoutStartSec=300
TimeoutStopSec=30

[Install]
WantedBy=default.target"

    # Write service files
    # We no longer need the pre-start service
    # if ! file_exists "${pre_start_service_filepath}" || ask_continue "Overwrite existing ${pre_start_service_filepath}?"; then
    #     write_file "${pre_start_service_filepath}" "${pre_start_content}"
    # fi
    
    if ! file_exists "${runtime_service_filepath}" || ask_continue "Overwrite existing ${runtime_service_filepath}?"; then
        write_file "${runtime_service_filepath}" "${runtime_content}"
    fi
    
    log_info "Systemd service templates created"
    return 0
}

create_runtime_config() {
    local runtime_id="$1"
    local gpu_address="$2"
    # Use VLLMD_RUNTIME_DEFAULT_MEMORY_GB or default to 16 if not set
    local memory_gb="${3:-${VLLMD_RUNTIME_DEFAULT_MEMORY_GB:-16}}"
    # Ensure memory value is uppercase G for cloud-hypervisor compatibility
    local memory_gb_uppercase=$(echo "${memory_gb}" | sed 's/g$/G/')
    local cpus="${4:-4}"
    
    next_step "Creating runtime configuration for runtime-${runtime_id}"
    
    local config_filepath="${VLLMD_RUNTIME_CONFIG_PATH}/runtime-${runtime_id}.env"
    local runtime_path="${VLLMD_RUNTIME_IMAGE_PATH}/runtime-${runtime_id}"
    local disk_filepath="${runtime_path}/disk.raw"
    
    # Ensure config directory exists
    mkdir -p "${VLLMD_RUNTIME_CONFIG_PATH}"
    
    # Ensure runtime directory exists
    mkdir -p "${runtime_path}"
    
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
    hash=$(echo "runtime-${runtime_id}" | md5sum | head -c 6)
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
    
    # Removed the EOF redirection to /dev/null - This was a no-op

    # Define runtime path variable for use in configuration
    local runtime_run_path="${HOME}/.local/run/vllmd/${runtime_id}"
    
    local config_content
    config_content=$(cat << EOF
# VLLMD Runtime Configuration for runtime-${runtime_id}
# GPU: ${gpu_model} (${gpu_address})
# NUMA Node: ${numa_node}
# Created: $(date)

# Runtime Identification
VLLMD_RUNTIME_ID="${runtime_id}"

# Runtime Path
VLLMD_RUNTIME_PATH="${runtime_run_path}"

# Hardware Configuration
VLLMD_RUNTIME_CPUS="${cpus}"
VLLMD_RUNTIME_MEMORY="size=${memory_gb_uppercase},hugepages=on,hugepage_size=2M,shared=on"

# Storage Configuration
VLLMD_RUNTIME_DISK_FILEPATH="${disk_filepath}"
VLLMD_RUNTIME_CONFIG_DISK="${VLLMD_RUNTIME_CONFIG_IMAGE_FILEPATH}"

# Boot Configuration
VLLMD_RUNTIME_KERNEL_FILEPATH="${VLLMD_RUNTIME_HYPERVISOR_FW_FILEPATH}"
VLLMD_RUNTIME_CMDLINE="root=/dev/vda1 rw console=ttyS0 hugepagesz=2M hugepages=32768 default_hugepagesz=2M intel_iommu=on iommu=pt"

# Serial and Console Configuration
VLLMD_RUNTIME_SERIAL="tty"
VLLMD_RUNTIME_CONSOLE="off"

# GPU Configuration - accessed through vllmd-hypervisor launcher
VLLMD_RUNTIME_GPU_DEVICE="${gpu_address}"
EOF
)

    if ! file_exists "${config_filepath}" || ask_continue "Overwrite existing ${config_filepath}?"; then
        write_file "${config_filepath}" "${config_content}"
    else
        log_info "Runtime configuration not updated (kept existing file)"
    fi
    
    return 0
}

create_disk_image() {
    local runtime_id="$1"
    local size_gb="${2:-50}" # This parameter is no longer used since we copy an existing image
    local runtime_dir="${VLLMD_RUNTIME_IMAGE_PATH}/runtime-${runtime_id}"
    local disk_path="${runtime_dir}/disk.raw"
    
    next_step "Setting up disk image for runtime-${runtime_id}"
    
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "Would create runtime directory at ${runtime_dir}"
        echo "Would check if source raw image exists at ${VLLMD_RUNTIME_SOURCE_RAW_FILEPATH}"
        echo "Would check if target disk image already exists at ${disk_path}"
        
        if [[ "${DESTRUCTIVE_IMAGE_REPLACE}" -eq 1 ]]; then
            echo "Would copy source image to ${disk_path} (would overwrite if exists due to --destructive-image-replace flag)"
        else
            echo "Would copy source image to ${disk_path} (would skip if already exists)"
        fi
        return 0
    fi
    
    # Check if source image exists
    if [[ ! -f "${VLLMD_RUNTIME_SOURCE_RAW_FILEPATH}" ]]; then
        log_error "Source raw image '${VLLMD_RUNTIME_SOURCE_RAW_FILEPATH}' does not exist"
        log_error "Specify a valid source image with --source-raw-image=PATH"
        return 1
    fi
    
    # Create runtime directory
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
    
    log_info "Copying source image '${VLLMD_RUNTIME_SOURCE_RAW_FILEPATH}' to '${disk_path}'..."
    
    # Copy the source image to the target location
    cp "${VLLMD_RUNTIME_SOURCE_RAW_FILEPATH}" "${disk_path}"
    
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

create_config_image() {
    next_step "Creating VM configuration image"
    
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "Would check if configuration image exists at ${VLLMD_RUNTIME_CONFIG_IMAGE_FILEPATH}"
        echo "Would create configuration image with user 'sdake' if it doesn't exist"
        return 0
    fi
    
    # Check if configuration image already exists
    if [[ -f "${VLLMD_RUNTIME_CONFIG_IMAGE_FILEPATH}" ]]; then
        log_info "Configuration image already exists at ${VLLMD_RUNTIME_CONFIG_IMAGE_FILEPATH}"
        return 0
    fi
    
    log_info "Creating VM configuration image at ${VLLMD_RUNTIME_CONFIG_IMAGE_FILEPATH}"
    
    # Create temporary directory for boot initialization files
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
    mkdir -p "$(dirname "${VLLMD_RUNTIME_CONFIG_IMAGE_FILEPATH}")"
    
    # Create FAT filesystem image
    /usr/sbin/mkdosfs -n CONFIG -C "${VLLMD_RUNTIME_CONFIG_IMAGE_FILEPATH}" 8192
    
    # Copy files to the image
    mcopy -oi "${VLLMD_RUNTIME_CONFIG_IMAGE_FILEPATH}" -s "${temp_dir}/user-data" ::
    mcopy -oi "${VLLMD_RUNTIME_CONFIG_IMAGE_FILEPATH}" -s "${temp_dir}/meta-data" ::
    
    # Cleanup
    rm -rf "${temp_dir}"
    
    # Add to created files list
    CREATED_FILES+=("${VLLMD_RUNTIME_CONFIG_IMAGE_FILEPATH}")
    
    log_info "VM configuration image created successfully"
    return 0
}

main() {
    print_banner
    
    # Check requirements
    check_cpu_virtualization || return 1
    check_iommu || return 1
    check_cap_tools || return 1
    check_vllmd_hypervisor || return 1
    check_numactl || return 1
    
    # Discover resources
    discover_gpus
    discover_numa_topology
    
    # Update GPU blocklist in config if provided via command line
    if [[ -n "${GPU_BLOCKLIST}" ]]; then
        update_gpu_blocklist_in_config
    fi
    
    # Setup environment
    create_directory_structure
    
    # Create VM configuration image if needed
    create_config_image
    
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
                local vm_name="runtime-${i}"
                local memory_gb=64
                local cpus=16
                
                echo "Would create runtime VM '${vm_name}' with GPU ${gpu_address}"
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
                
                # Default memory size is 64GB if not set
                local DEFAULT_MEMORY_GB="64G"
                
                if [[ "${AUTO_YES}" -eq 1 ]]; then
                    create_all="y"
                    memory_gb="128G"
                    cpus=4
                else
                    read -p "Create VMs for all GPUs? [y/n]: " create_all
                    read -p "Enter memory size in GB for each VM [${DEFAULT_MEMORY_GB}]: " memory_gb
                    memory_gb="${memory_gb:-${DEFAULT_MEMORY_GB}}"
                    read -p "Enter number of CPUs for each VM [4]: " cpus
                    cpus="${cpus:-4}"
                fi
                
                if [[ "${create_all}" =~ ^[Yy] ]]; then
                    # Create a VM for each GPU
                    for i in "${!gpu_list[@]}"; do
                        local gpu_address="${gpu_list[$i]}"
                        # Use the index directly as the runtime ID
                        
                        create_runtime_config "${i}" "${gpu_address}" "${memory_gb}" "${cpus}"
                        create_disk_image "${i}" 50
                        
                        log_info "Runtime 'runtime-${i}' configuration created with GPU ${gpu_address}"
                    done
                    
                    log_info "Runtime configurations created."
                    
                    # Check if the raw image exists or needs to be created
                    if [[ -f "${VLLMD_RUNTIME_SOURCE_RAW_FILEPATH}" ]]; then
                        log_info "Found ready-to-use runtime image at ${VLLMD_RUNTIME_SOURCE_RAW_FILEPATH}"
                    else
                        log_warn "No ready-to-use runtime image found."
                        log_info "Please create a runtime image with:"
                        echo "  bash generate-runtime-image.sh --output=\"${VLLMD_RUNTIME_IMAGE_PREFIX_PATH}/vllmd-hypervisor-runtime.raw\""
                        echo
                    fi
                    
                    log_info "To enable all systemd services (required for auto-start at boot):"
                    echo "  systemctl --user daemon-reload"
                    for i in "${!gpu_list[@]}"; do
                        echo "  systemctl --user enable vllmd-runtime@${i}.service"
                    done
                    echo
                    log_info "To start all runtimes immediately:"
                    for i in "${!gpu_list[@]}"; do
                        echo "  systemctl --user start vllmd-runtime@${i}.service"
                    done
                    echo
                    log_info "User linger has been enabled, so the runtimes will persist after logout."
                else
                    # Creating runtime-137
                    local runtime_id="137"
                    local gpu_address="0000:01:00.0"  # You may need to adjust this to your GPU address
                    
                    log_info "Creating runtime-${runtime_id} configuration with GPU ${gpu_address}"
                    create_runtime_config "${runtime_id}" "${gpu_address}" "${memory_gb}" "${cpus}"
                    create_disk_image "${runtime_id}" 50
                    
                    # Store the runtime ID for later use in enable/start commands
                    selected_indices=("${runtime_id}")
                    
                    log_info "Runtime configurations created."
                    
                    # Check if the raw image exists or needs to be created
                    if [[ -f "${VLLMD_RUNTIME_SOURCE_RAW_FILEPATH}" ]]; then
                        log_info "Found ready-to-use runtime image at ${VLLMD_RUNTIME_SOURCE_RAW_FILEPATH}"
                    else
                        log_warn "No ready-to-use runtime image found."
                        log_info "Please create a runtime image with:"
                        echo "  bash generate-runtime-image.sh --output=\"${VLLMD_RUNTIME_IMAGE_PREFIX_PATH}/vllmd-hypervisor-runtime.raw\""
                        echo
                    fi
                    
                    log_info "To enable the systemd services (required for auto-start at boot):"
                    echo "  systemctl --user daemon-reload"
                    echo "  systemctl --user enable vllmd-runtime@137.service"
                    echo
                    log_info "To start the runtimes immediately:"
                    echo "  systemctl --user start vllmd-runtime@137.service"
                    echo
                    log_info "User linger has been enabled, so the runtimes will persist after logout."
                fi
            fi
        fi
    fi
    
    # Create a summary file with all created files
    if [[ "${DRY_RUN}" -ne 1 ]] && [[ ${#CREATED_FILES[@]} -gt 0 ]]; then
        local summary_filepath="${VLLMD_RUNTIME_CONFIG_PATH}/installation-summary.md"
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
