#!/usr/bin/env bash
#
# precheck.sh - Verify system requirements for VLLMD virtualization
#
# This script checks if the system meets the prerequisites for running
# the VLLMD virtualization system, including required packages,
# hardware capabilities, and kernel features.
#

set -euo pipefail

# Output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'  # Purple color for RISK
NC='\033[0m' # No Color

print_header() {
    echo -e "\n${BLUE}==== $1 ====${NC}\n"
}

print_pass() {
    echo -e "[ ${GREEN}PASS${NC} ] $1"
}

print_fail() {
    echo -e "[ ${RED}FAIL${NC} ] $1"
}

print_warn() {
    echo -e "[ ${YELLOW}WARN${NC} ] $1"
}

print_info() {
    echo -e "[ ${BLUE}INFO${NC} ] $1"
}

print_risk() {
    echo -e "[ ${PURPLE}RISK${NC} ] $1"
}

# Print banner
echo "============================================="
echo "VLLMD Virtualization System Prerequisites Check"
echo "============================================="
echo

# Check required packages
print_header "Required Packages"

# Define required packages with versions (where applicable)
declare -A REQUIRED_PACKAGES=(
    ["cloud-hypervisor"]="v40.0+"
    ["numactl"]="2.0+"
    ["pciutils"]="3.5+"
)

# cloud-hypervisor
if command -v cloud-hypervisor &> /dev/null; then
    version=$(cloud-hypervisor --version | grep -oP 'cloud-hypervisor v\K[0-9]+\.[0-9]+(-dirty)?' || echo "unknown")
    print_pass "cloud-hypervisor is installed (version: ${version}, required: ${REQUIRED_PACKAGES["cloud-hypervisor"]})"
else
    print_fail "cloud-hypervisor is not installed (required: ${REQUIRED_PACKAGES["cloud-hypervisor"]})"
    echo "  Install with: sudo apt install --yes cloud-hypervisor"
fi

# numactl
if command -v numactl &> /dev/null; then
    numa_version=$(numactl --version 2>&1 | head -1 | grep -oP '([0-9]+\.[0-9]+\.[0-9]+)' || echo "unknown")
    print_pass "numactl is installed (version: ${numa_version}, required: ${REQUIRED_PACKAGES["numactl"]})"
else
    print_fail "numactl is not installed (required: ${REQUIRED_PACKAGES["numactl"]})"
    echo "  Install with: sudo apt install --yes numactl"
fi

# pciutils
if command -v lspci &> /dev/null; then
    pci_version=$(lspci --version | grep -oP '([0-9]+\.[0-9]+)' || echo "unknown")
    print_pass "pciutils is installed (version: ${pci_version}, required: ${REQUIRED_PACKAGES["pciutils"]})"
else
    print_fail "pciutils is not installed (required: ${REQUIRED_PACKAGES["pciutils"]})"
    echo "  Install with: sudo apt install --yes pciutils"
fi

# Check for additional tools and services
print_header "PCI Access and Additional Services"

# Check udev rules for VFIO
if ls /etc/udev/rules.d/*vfio* &>/dev/null || ls /lib/udev/rules.d/*vfio* &>/dev/null; then
    print_pass "VFIO udev rules are configured"
else
    print_warn "No VFIO udev rules found"
    echo "  This may affect device permissions for VFIO passthrough"
fi

# Check for systemd-modules-load service
if systemctl is-active systemd-modules-load.service &>/dev/null; then
    print_pass "systemd-modules-load service is active"
else
    print_warn "systemd-modules-load service is not active"
    echo "  This service is important for loading kernel modules at boot"
fi

# Check for PCI device permissions
if [ -r "/sys/bus/pci/devices" ]; then
    print_pass "User has read access to PCI device information"
else
    print_warn "User may not have sufficient PCI device access permissions"
fi

# Check CPU virtualization support
print_header "CPU Virtualization Support"

# Count CPUs
cpu_cores=$(grep -c ^processor /proc/cpuinfo)
cpu_sockets=$(lscpu | grep "Socket(s)" | awk '{print $2}')
cpu_cores_per_socket=$(lscpu | grep "Core(s) per socket" | awk '{print $4}')
threads_per_core=$(lscpu | grep "Thread(s) per core" | awk '{print $4}')

print_info "CPU resources: ${cpu_sockets} sockets, ${cpu_cores_per_socket} cores/socket, ${threads_per_core} threads/core, ${cpu_cores} total logical cores"

if grep -q -E 'vmx|svm' /proc/cpuinfo; then
    cpu_vendor=$(grep -m1 "vendor_id" /proc/cpuinfo | awk '{print $3}')
    if grep -q "vmx" /proc/cpuinfo; then
        print_pass "Intel VT-x is supported"
    elif grep -q "svm" /proc/cpuinfo; then
        print_pass "AMD-V is supported"
    fi
else
    print_fail "CPU virtualization extensions not found. This system does not support hardware virtualization."
fi

# Check KVM support
if [ -e /dev/kvm ]; then
    print_pass "KVM is available (/dev/kvm exists)"
    
    # Check KVM permissions
    if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
        print_pass "Current user has permission to access KVM"
    else
        print_warn "Current user does not have permission to access KVM"
        echo "  Fix with: sudo usermod -a -G kvm $(whoami)"
        echo "  Then log out and log back in"
    fi
    
    # Check if user is in the correct groups
    if groups | grep -q "kvm"; then
        print_pass "User is in the kvm group"
    else
        print_warn "User is not in the kvm group"
        echo "  Fix with: sudo usermod -a -G kvm $(whoami)"
        echo "  Then log out and log back in"
    fi
else
    print_fail "KVM is not available (/dev/kvm does not exist)"
    echo "  Check if the kvm_intel or kvm_amd modules are loaded"
fi

# Check for nested virtualization (optional but improves performance)
if grep -q "Y" /sys/module/kvm_intel/parameters/nested 2>/dev/null || 
   grep -q "1" /sys/module/kvm_amd/parameters/nested 2>/dev/null; then
    print_pass "Nested virtualization is enabled"
else
    print_info "Nested virtualization is not enabled (optional)"
fi

# Check IOMMU support
print_header "IOMMU Support"

# Check kernel parameters (reliable method)
if grep -E "intel_iommu=on|amd_iommu=on" /proc/cmdline > /dev/null; then
    print_pass "IOMMU is enabled via kernel boot parameters"
else
    print_fail "IOMMU does not appear to be enabled"
    echo "  Add 'intel_iommu=on' or 'amd_iommu=on' to kernel parameters in GRUB"
fi

# Check for PCI passthrough support
if grep -q "iommu=pt" /proc/cmdline > /dev/null; then
    print_pass "PCI passthrough is enabled via 'iommu=pt' kernel parameter"
else
    print_warn "PCI passthrough parameter 'iommu=pt' not found in kernel parameters"
    echo "  Consider adding 'iommu=pt' to kernel parameters for optimal passthrough"
fi

# Check for PCIe Access Control and Topology features
print_header "PCIe Topology and Isolation"

# Check for PCIe ACS (Access Control Services) support
print_info "Checking PCIe ACS (Access Control Services) support"
acs_enabled=false
acs_devices=0

for device in /sys/bus/pci/devices/*/acs_enabled; do
    if [ -f "$device" ]; then
        acs_devices=$((acs_devices+1))
        if [ "$(cat "$device")" = "1" ]; then
            acs_enabled=true
        fi
    fi
done

if [ "$acs_devices" -gt 0 ]; then
    if [ "$acs_enabled" = true ]; then
        print_pass "PCIe ACS is enabled on at least one device"
    else
        print_warn "PCIe ACS appears to be disabled on all devices"
        echo "  Consider adding 'pcie_acs_override=downstream,multifunction' to kernel parameters"
        echo "  This helps ensure proper IOMMU group isolation for PCI passthrough"
    fi
    
    # Check if ACS override is enabled
    if grep -q "pcie_acs_override" /proc/cmdline > /dev/null; then
        print_pass "PCIe ACS override is enabled in kernel parameters"
    else
        print_info "PCIe ACS override is not enabled (may be needed for proper device isolation)"
    fi
else
    print_info "Could not determine PCIe ACS status (no acs_enabled files found)"
fi

# Check for proper PCIe topology isolation by analyzing IOMMU groups
print_info "Analyzing PCIe topology and IOMMU group isolation"

# Get all GPUs with their PCI addresses and IOMMU groups
declare -A gpu_iommu_groups
declare -A iommu_group_members

vendor_id="10de"  # NVIDIA vendor ID

# Map GPUs to IOMMU groups
while read -r pci_addr; do
    if [ -d "/sys/bus/pci/devices/$pci_addr" ]; then
        # Find IOMMU group for this device
        group_path=$(readlink -f "/sys/bus/pci/devices/$pci_addr/iommu_group")
        if [ -n "$group_path" ]; then
            group_num=$(basename "$group_path")
            gpu_iommu_groups["$pci_addr"]=$group_num
            
            # Count all devices in this IOMMU group
            group_devices=$(find "$group_path/devices" -type l | wc -l)
            iommu_group_members["$group_num"]=$group_devices
        fi
    fi
done < <(lspci -nn | grep -i "\[$vendor_id:" | awk '{print "0000:"$1}')

# Check GPU isolation
isolation_issues=0
for gpu in "${!gpu_iommu_groups[@]}"; do
    group="${gpu_iommu_groups[$gpu]}"
    members="${iommu_group_members[$group]}"
    
    if [ "$members" -eq 1 ]; then
        print_pass "GPU $gpu is properly isolated in IOMMU group $group (alone)"
    else
        print_warn "GPU $gpu shares IOMMU group $group with $(($members-1)) other device(s)"
        isolation_issues=$((isolation_issues+1))
        
        # List all devices in this group
        echo "  Devices in IOMMU group $group:"
        find "/sys/kernel/iommu_groups/$group/devices" -type l | while read -r dev_link; do
            dev=$(basename "$dev_link")
            dev_info=$(lspci -s "${dev#0000:}" -nn 2>/dev/null || echo "Unknown device")
            echo "    - $dev: $dev_info"
        done
    fi
done

# Check for PCIe topology kernel parameters
if grep -q "pcie_ports=compat" /proc/cmdline || grep -q "pci=assign-busses" /proc/cmdline; then
    print_pass "PCIe topology preservation parameters detected in kernel command line"
else
    if [ $isolation_issues -gt 0 ]; then
        print_warn "Consider adding 'pcie_ports=compat pci=assign-busses' to kernel parameters"
        echo "  These help preserve PCIe topology information for reliable passthrough"
    else
        print_info "PCIe topology appears good without special parameters"
    fi
fi

# Check for PCIe device reset support
reset_problems=0
for gpu in "${!gpu_iommu_groups[@]}"; do
    if [ -f "/sys/bus/pci/devices/$gpu/reset" ]; then
        print_pass "GPU $gpu supports device reset"
    else
        print_warn "GPU $gpu does not appear to support reset functionality"
        reset_problems=$((reset_problems+1))
    fi
done

if [ $reset_problems -gt 0 ]; then
    print_warn "Some GPUs may have reset issues, consider adding 'pci_reset_function=y' kernel parameter"
fi

# Check for interrupt remapping and handling capabilities
print_header "Interrupt Management and Remapping"

# Check kernel parameters for interrupt remapping
if grep -q "intremap=on" /proc/cmdline > /dev/null || grep -q "irqremap=on" /proc/cmdline > /dev/null; then
    print_pass "Interrupt remapping is explicitly enabled via kernel parameters"
elif grep -q "intremap=off" /proc/cmdline > /dev/null || grep -q "irqremap=off" /proc/cmdline > /dev/null; then
    print_warn "Interrupt remapping is explicitly disabled via kernel parameters"
    echo "  This may cause stability issues with device passthrough"
else
    # Check if the system has IOMMU enabled (implied interrupt remapping)
    if [ -r "/sys/kernel/iommu_groups/0/devices" ]; then
        print_info "Interrupt remapping is likely enabled (IOMMU groups are available)"
    else
        print_warn "Interrupt remapping status could not be determined"
        echo "  Consider adding 'intremap=on' to kernel parameters"
    fi
fi

# Check for interrupt posting capability
if [ -d "/sys/kernel/irq_domain_mapping" ]; then
    print_pass "Interrupt domain mapping is available"
    
    # If file exists, show its content which details the type of interrupt mapping
    if [ -f "/proc/interrupts" ]; then
        print_info "Interrupt controller types:"
        int_controllers=$(grep -i "controller" /proc/interrupts | sort | uniq)
        if [ -n "$int_controllers" ]; then
            echo "$int_controllers" | while read -r line; do
                echo "  - $line"
            done
        else
            echo "  No interrupt controllers found in /proc/interrupts"
        fi
    fi
fi

# Check for MSI/MSI-X support (important for high-performance passthrough)
msi_support=false
msi_x_support=false

# Check if MSI is enabled for our NVIDIA GPUs
for gpu in "${!gpu_iommu_groups[@]}"; do
    if [ -d "/sys/bus/pci/devices/$gpu/msi_irqs" ]; then
        msi_irq_count=$(ls "/sys/bus/pci/devices/$gpu/msi_irqs" | wc -l)
        if [ "$msi_irq_count" -gt 0 ]; then
            print_pass "GPU $gpu is using MSI with $msi_irq_count interrupt vectors"
            msi_support=true
        fi
    fi
    
    # Check if MSI-X is available/enabled
    if [ -f "/sys/bus/pci/devices/$gpu/msix_cap" ]; then
        print_pass "GPU $gpu has MSI-X capability"
        msi_x_support=true
        
        # If we can read number of vectors
        if [ -f "/sys/bus/pci/devices/$gpu/msix_table_size" ]; then
            msix_size=$(cat "/sys/bus/pci/devices/$gpu/msix_table_size" 2>/dev/null || echo "unknown")
            print_info "  MSI-X table size: $msix_size vectors"
        fi
    fi
done

# Overall MSI/MSI-X assessment
if [ "$msi_support" = true ] || [ "$msi_x_support" = true ]; then
    print_pass "System has MSI/MSI-X interrupt capability (optimal for passthrough)"
else
    print_warn "Could not confirm MSI/MSI-X support for GPUs"
    echo "  Consider adding 'pci=nomsi' to kernel parameters if you experience IRQ-related issues"
fi

# Check IRQ affinity setting capability
if [ -d "/proc/irq" ]; then
    print_info "Checking IRQ affinity control capability"
    
    # Choose a random IRQ to test affinity control
    test_irq=$(find /proc/irq -mindepth 1 -maxdepth 1 -type d | grep -v "0" | head -1)
    if [ -n "$test_irq" ] && [ -f "$test_irq/smp_affinity" ]; then
        print_pass "IRQ affinity control is available"
        print_info "  This allows pinning interrupts to specific CPUs for optimal performance"
    else
        print_info "IRQ affinity control could not be confirmed"
    fi
fi

# Check if we're using x2apic mode (better for large systems)
dmesg_file=$(mktemp)
dmesg > "$dmesg_file" 2>/dev/null || true

if grep -q "x2apic enabled" "$dmesg_file" 2>/dev/null; then
    print_pass "x2APIC mode is enabled (optimal for large systems)"
elif grep -q "x2apic disabled" "$dmesg_file" 2>/dev/null; then
    print_info "x2APIC mode is disabled"
    if grep -E -q "AMD-Vi|DMAR" "$dmesg_file" 2>/dev/null; then
        print_info "  Consider adding 'x2apic_phys' or 'x2apic=on' to kernel parameters"
    fi
else
    print_info "x2APIC status could not be determined"
fi

# Clean up
rm -f "$dmesg_file"

# Method 3: Check if IOMMU groups exist
if [ -d "/sys/kernel/iommu_groups" ]; then
    group_count=$(find /sys/kernel/iommu_groups/ -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
    if [ "$group_count" -gt 0 ]; then
        print_pass "IOMMU groups are available ($group_count groups)"
    else
        print_warn "IOMMU groups directory exists but no groups found"
    fi
else
    print_fail "No IOMMU groups directory found (/sys/kernel/iommu_groups)"
fi

# Check GPU presence and details
print_header "NVIDIA GPU Detection"

# Count NVIDIA GPUs
nvidia_gpu_count=$(lspci -nn | grep -i "\[10de:" | wc -l)

if [ "$nvidia_gpu_count" -gt 0 ]; then
    print_pass "NVIDIA GPUs detected (${nvidia_gpu_count} found)"
    
    echo "GPU Details:"
    lspci -nn | grep -i "\[10de:" | while read -r line; do
        pci_address=$(echo "$line" | awk '{print $1}')
        device_info=$(echo "$line" | cut -d: -f3-)
        echo "  $pci_address: $device_info"
        
        # Check if the GPU is in its own IOMMU group (good for passthrough)
        if [ -d "/sys/kernel/iommu_groups" ]; then
            for group in /sys/kernel/iommu_groups/*/devices/0000:$pci_address; do
                if [ -e "$group" ]; then
                    group_num=$(echo "$group" | grep -oP '/sys/kernel/iommu_groups/\K[0-9]+')
                    device_count=$(find "/sys/kernel/iommu_groups/$group_num/devices" -type l | wc -l)
                    
                    if [ "$device_count" -eq 1 ]; then
                        print_info "  → In IOMMU group $group_num (alone, ideal for passthrough)"
                    else
                        print_warn "  → In IOMMU group $group_num (with $((device_count-1)) other devices)"
                    fi
                fi
            done
        fi
    done
else
    print_warn "No NVIDIA GPUs detected"
fi

# Check hugepages support
print_header "Hugepages Support"

hugepages_total=$(grep HugePages_Total /proc/meminfo | awk '{print $2}')
hugepages_free=$(grep HugePages_Free /proc/meminfo | awk '{print $2}')
hugepage_size=$(grep Hugepagesize /proc/meminfo | awk '{print $2}')

if [ "$hugepages_total" -gt 0 ]; then
    # Calculate total memory allocated for hugepages
    total_hugepages_mib=$((hugepages_total * hugepage_size / 1024))
    total_hugepages_gib=$(awk "BEGIN {printf \"%.2f\", ${total_hugepages_mib}/1024}")
    free_hugepages_gib=$(awk "BEGIN {printf \"%.2f\", ${hugepages_free}*${hugepage_size}/1024/1024}")
    
    print_pass "Hugepages are configured ($hugepages_total pages, ${hugepage_size}kB each, $hugepages_free free)"
    print_info "Total memory allocated for hugepages: ${total_hugepages_gib} GiB (${free_hugepages_gib} GiB free)"
else
    print_warn "No hugepages are currently allocated"
    echo "  Set up hugepages with: echo 'vm.nr_hugepages = N' | sudo tee -a /etc/sysctl.d/10-hugepages.conf"
    echo "  Then apply with: sudo sysctl -p /etc/sysctl.d/10-hugepages.conf"
fi

# Check for necessary kernel features
print_header "Kernel Features and Modules"

# Check kernel version (min 5.4 recommended for good VFIO support)
kernel_version=$(uname -r)
kernel_major=$(echo "$kernel_version" | cut -d. -f1)
kernel_minor=$(echo "$kernel_version" | cut -d. -f2)

if [ "$kernel_major" -gt 5 ] || [ "$kernel_major" -eq 5 -a "$kernel_minor" -ge 4 ]; then
    print_pass "Kernel version $kernel_version is sufficient (recommended: 5.4+)"
else
    print_warn "Kernel version $kernel_version may be too old (recommended: 5.4+)"
fi

# Check for CPU vulnerability mitigations
print_info "Checking CPU vulnerability mitigations (may impact performance)"

# Directory containing vulnerability information
vuln_dir="/sys/devices/system/cpu/vulnerabilities"

if [ -d "$vuln_dir" ]; then
    # Create an array to store mitigations status
    declare -A mitigations

    # Check common CPU vulnerabilities
    for vuln_file in "$vuln_dir"/*; do
        if [ -r "$vuln_file" ]; then
            vuln_name=$(basename "$vuln_file")
            vuln_status=$(cat "$vuln_file")
            
            # Store in array
            mitigations["$vuln_name"]="$vuln_status"
            
            # Check if this vulnerability has mitigations enabled
            if [[ "$vuln_status" == *"Mitigation"* ]]; then
                print_pass "$vuln_name: $vuln_status"
            elif [[ "$vuln_status" == *"Vulnerable"* ]]; then
                print_warn "$vuln_name: $vuln_status"
            elif [[ "$vuln_status" == *"Not affected"* ]]; then
                print_info "$vuln_name: $vuln_status"
            else
                print_info "$vuln_name: $vuln_status"
            fi
        fi
    done
    
    # Check specifically for performance-impacting mitigations
    if [[ "${mitigations[meltdown]}" == *"Mitigation"* || "${mitigations[spectre_v2]}" == *"Mitigation"* ]]; then
        print_info "Performance-impacting mitigations are active - VM performance may be affected"
        if ! grep -q "mitigations=off" /proc/cmdline && ! grep -q "nopti" /proc/cmdline; then
            print_risk "Consider adding 'mitigations=off' to kernel parameters for performance, but be aware this reduces security and should be evaluated carefully"
        fi
    fi
else
    print_warn "Cannot access CPU vulnerability information"
fi

# Check for page table isolation (affects passthrough performance)
if grep -q "nopti" /proc/cmdline; then
    print_pass "Page Table Isolation is disabled (better for VM performance)"
elif grep -q "pti=off" /proc/cmdline; then
    print_pass "Page Table Isolation is disabled (better for VM performance)"
else
    print_info "Page Table Isolation may be enabled (minor performance impact)"
fi

# Check necessary modules for VFIO passthrough
modules=("vfio" "vfio_iommu_type1" "vfio_pci" "vfio_virqfd")
missing_modules=()
vfio_global_status=false

print_info "Checking for VFIO kernel modules"

# Check for VFIO by examining /proc/modules directly
if [ -r "/proc/modules" ]; then
    MODULES_OUTPUT=$(cat /proc/modules)
    for module in "${modules[@]}"; do
        # Check if module is loaded using grep
        if echo "$MODULES_OUTPUT" | grep -q "^$module "; then
            print_pass "$module module is loaded"
            vfio_global_status=true
        else
            # Check if the module could be part of other modules (like vfio_pci_core)
            if echo "$MODULES_OUTPUT" | grep -q "$module"; then
                print_pass "$module functionality is available (via other module)"
                vfio_global_status=true
            else
                if modinfo "$module" &> /dev/null; then
                    print_warn "$module module is available but not loaded"
                    echo "  Load with: sudo modprobe $module"
                    missing_modules+=("$module")
                else
                    print_fail "$module module is not available"
                fi
            fi
        fi
    done
else
    print_warn "Cannot read /proc/modules (insufficient permissions)"
    print_info "Checking VFIO availability through IOMMU groups"
    
    # Alternative check: if IOMMU groups exist and we can find VFIO-related files
    if [ -d "/sys/kernel/iommu_groups" ] && [ "$(find /sys/kernel/iommu_groups/ -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)" -gt 0 ]; then
        # Check if vfio devices are available
        if [ -d "/dev/vfio" ] || ls /dev/vfio* &> /dev/null; then
            print_pass "VFIO devices are available in /dev"
            vfio_global_status=true
        else
            print_warn "No VFIO devices found in /dev"
        fi
    fi
fi

# Set global variable to track VFIO availability
export VFIO_AVAILABLE=$vfio_global_status

if [ ${#missing_modules[@]} -gt 0 ]; then
    echo
    echo "Load missing modules with:"
    echo "  sudo modprobe ${missing_modules[*]}"
    echo
    echo "To load modules at boot time:"
    echo "  echo '${missing_modules[*]}' | sudo tee -a /etc/modules-load.d/vfio.conf"
fi

# Summary
print_header "System Readiness Summary"

# Initialize the readiness variable if not already set
system_ready=true

# CPU virtualization is required
grep -q -E 'vmx|svm' /proc/cpuinfo || system_ready=false

# KVM is required
[ -e /dev/kvm ] || system_ready=false

# IOMMU is required - check via kernel parameters
grep -E "intel_iommu=on|amd_iommu=on" /proc/cmdline > /dev/null || system_ready=false

# VFIO modules are required
[ "$VFIO_AVAILABLE" = true ] || system_ready=false

# Hugepages are required
[ "$hugepages_total" -gt 0 ] || system_ready=false

# User must have PCI device access
[ -r "/sys/bus/pci/devices" ] || system_ready=false

if [ "$system_ready" = true ]; then
    echo "The system is READY and has:"
else
    echo "The system is NOT READY. Current status:"
fi

# Check virtualization
if grep -q -E 'vmx|svm' /proc/cpuinfo; then
    echo -e "  - CPU virtualization: ${GREEN}YES${NC}"
else
    echo -e "  - CPU virtualization: ${RED}NO${NC}"
fi

# Check KVM
if [ -e /dev/kvm ]; then
    echo -e "  - KVM support: ${GREEN}YES${NC}"
else
    echo -e "  - KVM support: ${RED}NO${NC}"
fi

# Check IOMMU
if grep -E "intel_iommu=on|amd_iommu=on" /proc/cmdline > /dev/null; then
    echo -e "  - IOMMU support: ${GREEN}YES${NC}"
else
    echo -e "  - IOMMU support: ${RED}NO${NC}"
fi

# Check GPUs
nvidia_gpu_count=$(lspci -nn | grep -i "\[10de:" | wc -l)
if [ "$nvidia_gpu_count" -gt 0 ]; then
    echo -e "  - NVIDIA GPUs: ${GREEN}YES (${nvidia_gpu_count} found)${NC}"
else
    echo -e "  - NVIDIA GPUs: ${YELLOW}NO${NC}"
fi

# Check hugepages
if [ "$hugepages_total" -gt 0 ]; then
    total_hugepages_gib=$(awk "BEGIN {printf \"%.2f\", ${hugepages_total}*${hugepage_size}/1024/1024}")
    echo -e "  - Hugepages: ${GREEN}YES (${total_hugepages_gib} GiB)${NC}"
else
    echo -e "  - Hugepages: ${YELLOW}NO${NC}"
fi

# Check VFIO modules - use the result from the detailed check
if [ "$VFIO_AVAILABLE" = true ]; then
    echo -e "  - VFIO modules: ${GREEN}YES${NC}"
else
    echo -e "  - VFIO modules: ${RED}NO${NC}"
fi
echo

# Final status output
if [ "$system_ready" = true ]; then
    echo -e "${GREEN}READY${NC}"
else
    echo -e "${RED}NOT-READY${NC}"
fi
