# VLLMD-Hypervisor System Interfaces

This document records the interfaces and information sources utilized by the VLLMD-Hypervisor's diagnostic and configuration tools, particularly the `precheck.sh` script.

## Precheck Information Sources

The `precheck.sh` script examines various Linux kernel interfaces, files, and system information sources to determine system readiness for virtualization. This table documents these interfaces to facilitate maintenance and future enhancements.

| Category | Information Source | Path | Description | Permissions Required |
|----------|-------------------|------|-------------|----------------------|
| **CPU Virtualization** | CPU Features | `/proc/cpuinfo` | Checks for VMX/SVM flags indicating virtualization support | User |
| | CPU Topology | `lscpu` output | Retrieves socket count, cores per socket, and threads per core | User |
| | Nested Virtualization | `/sys/module/kvm_intel/parameters/nested` or<br>`/sys/module/kvm_amd/parameters/nested` | Checks if nested virtualization is enabled | User |
| **Runtime Virtualization** | KVM Device | `/dev/kvm` | Verifies KVM device exists and is accessible | User |
| | KVM Group Membership | `groups` command | Determines if user is in kvm group | User |
| **IOMMU Support** | Kernel Parameters | `/proc/cmdline` | Checks for IOMMU enablement flags (intel_iommu=on, amd_iommu=on) | User |
| | IOMMU Groups | `/sys/kernel/iommu_groups/` | Examines IOMMU group structure and isolation | User |
| | PCI Passthrough | `/proc/cmdline` | Checks for iommu=pt parameter | User |
| **PCIe Topology** | PCI Devices | `/sys/bus/pci/devices/` | Discovers PCI devices and their properties | User |
| | Device Assignment | `/sys/bus/pci/devices/*/iommu_group` | Maps devices to their IOMMU groups | User |
| | ACS Support | `/sys/bus/pci/devices/*/acs_enabled` | Verifies ACS (Access Control Services) status | User |
| | Device Reset Support | `/sys/bus/pci/devices/*/reset` | Checks if device supports reset functionality | User |
| **Interrupt Management** | Interrupt Remapping | `/proc/cmdline` | Checks for intremap/irqremap parameters | User |
| | MSI Support | `/sys/bus/pci/devices/*/msi_irqs` | Detects MSI (Message Signaled Interrupts) capability | User |
| | MSI-X Support | `/sys/bus/pci/devices/*/msix_cap` | Verifies MSI-X interrupt capability | User |
| | IRQ Affinity | `/proc/irq/*/smp_affinity` | Checks for IRQ CPU affinity control capability | User |
| | APIC Mode | `dmesg` output | Detects x2APIC mode status | User (sometimes root) |
| **GPU Status** | PCI Devices | Output of `lspci -nn` | Detects NVIDIA GPUs by vendor ID (10de) | User |
| | Device Properties | `/sys/bus/pci/devices/` | Examines GPU capabilities and configuration | User |
| **Memory Configuration** | Hugepages | `/proc/meminfo` | Checks hugepage configuration and availability | User |
| | Memory Allocation | Calculations from hugepage info | Determines total memory allocated for hugepages | User |
| **Kernel Features** | Kernel Version | `uname -r` | Verifies kernel version meets requirements | User |
| | Loaded Modules | `/proc/modules` | Checks for VFIO and related modules | User |
| | CPU Vulnerabilities | `/sys/devices/system/cpu/vulnerabilities/*` | Examines CPU security mitigations | User |
| | Kernel Parameters | `/proc/cmdline` | Checks for security/performance optimization flags | User |
| **System Services** | Systemd Services | `systemctl` command | Verifies status of required services | User |
| | Udev Rules | `/etc/udev/rules.d/` and<br>`/lib/udev/rules.d/` | Checks for VFIO device permission rules | User |

## Output Interfaces

The script produces a structured diagnostic output with multiple levels of detail:

| Output Level | Format | Purpose |
|--------------|--------|---------|
| PASS/FAIL/WARN | Colored status indicators | Immediate visual feedback on component status |
| INFO | Detailed information | Additional context without explicit status judgment |
| RISK | Security/performance trade-offs | Highlights configuration choices with potential security implications |
| System Readiness | Overall READY/NOT-READY assessment | Final determination of system viability for VLLMD |

## Future Interface Enhancements

The following interfaces are planned for future enhancements:

1. JSON output format for programmatic consumption
2. Machine-readable configuration assessment metric
3. Persistent configuration profile storage
4. Integration with system monitoring services

## Maintenance Notes

When updating the precheck.sh script:

1. Add any new information sources to this document
2. Maintain backward compatibility with existing paths where possible
3. Consider permission requirements for new information sources
4. Document kernel version dependencies for new interfaces
