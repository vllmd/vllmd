# VLLMD-Hypervisor Script Variables

This document provides a comprehensive list of variables used in the VLLMD KVM virtualization
scripts, organized by scope with their data types and purposes clearly defined.

| Variable                                    | Scope          | Data Type | Purpose                                                                               |
| ------------------------------------------- | -------------- | --------- | ------------------------------------------------------------------------------------- |
| `VLLMD_KVM_AUTO_YES`                        | Global         | Boolean   | Automatically accepts default values without prompting user                           |
| `VLLMD_KVM_CLOUDINIT_FILEPATH`              | Global         | String    | Path to cloud-init configuration disk                                                 |
| `VLLMD_KVM_CONFIG_PATH`                     | Global/Const   | String    | Path to VLLMD configuration directory                                                 |
| `VLLMD_KVM_CREATED_FILEPATH_LIST`           | Global         | Array     | List of file paths created during script execution                                    |
| `VLLMD_KVM_DEFAULT_MEMORY_GIB`              | Global/Const   | Integer   | Default memory allocation per VM in GiB                                               |
| `VLLMD_KVM_DESTRUCTIVE_IMAGE_REPLACE`       | Global         | Boolean   | Controls whether existing disk images can be overwritten                              |
| `VLLMD_KVM_DRY_RUN`                         | Global         | Boolean   | Controls whether actions are executed or only simulated for preview                   |
| `VLLMD_KVM_GPU_ADDRESS_LIST`                | Global         | Array     | List of detected GPU PCI addresses                                                    |
| `VLLMD_KVM_GRUB_FILEPATH`                   | Global/Const   | String    | Path to GRUB configuration file                                                       |
| `VLLMD_KVM_HYPERVISOR_FW_FILEPATH`          | Global         | String    | Path to cloud-hypervisor firmware file                                                |
| `VLLMD_KVM_IMAGE_PATH`                      | Global/Const   | String    | Path to VM image storage directory                                                    |
| `VLLMD_KVM_IMAGE_PREFIX_PATH`               | Global         | String    | Base directory prefix for VM image storage                                            |
| `VLLMD_KVM_LOG_PATH`                        | Global/Const   | String    | Path to VLLMD log directory                                                           |
| `VLLMD_KVM_MAXIMUM_GPU_COUNT`               | Global/Const   | Integer   | Maximum number of GPUs supported by the system                                        |
| `VLLMD_KVM_MAXIMUM_MEMORY_GIB`              | Global/Const   | Integer   | Maximum memory allocation per VM in GiB                                               |
| `VLLMD_KVM_MINIMUM_MEMORY_GIB`              | Global/Const   | Integer   | Minimum memory allocation per VM in GiB                                               |
| `VLLMD_KVM_MODULES_FILEPATH`                | Global/Const   | String    | Path to kernel modules configuration file                                             |
| `VLLMD_KVM_NO_REBOOT`                       | Global         | Boolean   | Skips reboot requests and continues script execution                                  |
| `VLLMD_KVM_NVIDIA_GPU_SPECIFICATION_LIST`   | Global         | Array     | List of NVIDIA GPU specifications in structured format for internal processing        |
| `VLLMD_KVM_NVIDIA_GPU_SPECIFICATION_STRING` | Global         | String    | Serialized string representation of GPU specifications for configuration file storage |
| `VLLMD_KVM_RUN_PATH`                        | Global/Const   | String    | Path to VLLMD runtime directory                                                       |
| `VLLMD_KVM_SOURCE_REFERENCE_RAW_FILEPATH`   | Global         | String    | Path of source reference raw disk image to copy for new VMs                           |
| `VLLMD_KVM_STEP_COUNT`                      | Global         | Integer   | Tracks current step count for dry run output                                          |
| `VLLMD_KVM_SYSCTL_FILEPATH`                 | Global/Const   | String    | Path to sysctl configuration file                                                     |
| `VLLMD_KVM_SYSTEMD_PATH`                    | Global/Const   | String    | Path to systemd user service directory                                                |
| `VLLMD_KVM_UDEV_RULES_FILEPATH`             | Global/Const   | String    | Path to udev rules file for VFIO devices                                              |
| `VLLMD_KVM_VFIO_FILEPATH`                   | Global/Const   | String    | Path to VFIO configuration file                                                       |
| `VLLMD_KVM_CMDLINE`                         | VM Config      | String    | Kernel command line parameters                                                        |
| `VLLMD_KVM_VIRTUAL_CPU_COUNT`               | VM Config      | Integer   | Number of virtual CPUs allocated to the VM                                            |
| `VLLMD_KVM_DISK_FILEPATH`                   | VM Config      | String    | Path to VM's disk image                                                               |
| `VLLMD_KVM_GPU_DEVICE`                      | VM Config      | String    | PCI address of GPU assigned to the VM                                                 |
| `VLLMD_KVM_HOST_NETWORK_INTERFACE`          | VM Config      | String    | Host network interface to bridge VM network                                           |
| `VLLMD_KVM_IDENTITY`                        | VM Config      | String    | Unique identifier for the VM                                                          |
| `VLLMD_KVM_KERNEL_FILEPATH`                 | VM Config      | String    | Path to hypervisor firmware                                                           |
| `VLLMD_KVM_MEMORY_HUGEPAGE_CONFIGURATION`   | VM Config      | String    | Memory allocation specification including hugepage settings and memory size in GiB    |
| `VLLMD_KVM_LOG_FILEPATH`                    | VM Runtime     | String    | Path to VM's log file                                                                 |
| `VLLMD_KVM_RUNTIME_PATH`                    | VM Runtime     | String    | Path to VM's runtime directory                                                        |
| `config_filepath`                           | Function Local | String    | Path to VM configuration file                                                         |
| `cpu_count`                                 | Function Local | Integer   | Number of CPUs to allocate to VM                                                      |
| `create_all`                                | Function Local | String    | Flag to create VMs for all GPUs                                                       |
| `default_interface`                         | Function Local | String    | Default network interface on host                                                     |
| `device_id`                                 | Function Local | String    | PCI device ID                                                                         |
| `disk_filepath`                             | Function Local | String    | Path to VM's disk image                                                               |
| `gpu_info`                                  | Function Local | String    | Human-readable GPU information                                                        |
| `gpu_model`                                 | Function Local | String    | Model name of GPU                                                                     |
| `mac_prefix`                                | Function Local | String    | MAC address prefix for VM network interfaces                                          |
| `mac_suffix`                                | Function Local | String    | MAC address suffix derived from VM name                                               |
| `memory_gib`                                | Function Local | Integer   | Memory allocation for VM in GiB                                                       |
| `modules_content`                           | Function Local | String    | Content for kernel modules configuration                                              |
| `node_count`                                | Function Local | Integer   | Number of NUMA nodes in system                                                        |
| `numa_node`                                 | Function Local | Integer   | NUMA node associated with GPU                                                         |
| `summary_content`                           | Function Local | String    | Content of installation summary                                                       |
| `summary_filepath`                          | Function Local | String    | Path to installation summary file                                                     |
| `temp_dir`                                  | Function Local | String    | Temporary directory for cloud-init file creation                                      |
| `udev_content`                              | Function Local | String    | Content for udev rules                                                                |
| `vfio_content`                              | Function Local | String    | Content for VFIO configuration                                                        |
| `vm_path`                                   | Function Local | String    | Path to VM's directory                                                                |

## Variable Scopes

- **Global**: Available throughout the script, can be modified
- **Global/Const**: Global constant, defined once and never modified
- **VM Config**: Used in VM configuration files
- **VM Runtime**: Created or used during VM execution
- **Function Local**: Scoped to a specific function (can be mutable or constant)

<!--
# Instructions for updating this file

1. NAMING CONVENTION:
   - All global and constant variables MUST be prefixed with `VLLMD_KVM_`
   - All path variables MUST end with `_PATH`
   - All file path variables MUST end with `_FILEPATH`
   - All array/collection variables MUST end with `_LIST`
   - All count variables MUST end with `_COUNT` (avoid abbreviations)
   - Replace MIN/MAX with MINIMUM/MAXIMUM for clarity
   - Memory values MUST use `GiB` (not GB) for binary units
   - Use `Boolean` type for flags/toggles (not Integer)
   - Function-local variables MAY use shorter, more concise names
   - Variable names MUST be as explicit and unambiguous as possible

2. ORGANIZATION:
   - Variables MUST be sorted by:
     1. Scope (Global, Global/Const, VM Config, VM Runtime, Function Local)
     2. Alphabetically by name within each scope
   - Table columns: Variable, Scope, Data Type, Purpose
   - Data types MUST be specific (Boolean, Integer, String, Array, etc.)

3. SCOPE DEFINITIONS:
   - Global: Available throughout the script, can be modified
   - Global/Const: Global constant, defined once and never modified
   - VM Config: Used in VM configuration files
   - VM Runtime: Created or used during VM execution
   - Function Local: Scoped to a specific function (can be mutable or constant)

4. VARIABLE PURPOSES:
   - Purpose descriptions MUST be clear, concise, and unambiguous
   - Focus on what the variable represents, not implementation details
   - Include SI units for numeric values (GiB, MHz, etc.)
   - For related variables (like NVIDIA_GPU_SPECIFICATION_LIST vs NVIDIA_GPU_SPECIFICATION_STRING),
     clearly explain their relationship and differences
   - Avoid vague descriptions that could lead to programmer confusion

## Instruction Tuning

This document serves as the definitive reference for variable naming and usage in the VLLMD KVM system. To maintain its integrity and usefulness:

1. **Completeness**: Every variable used in the VLLMD KVM system MUST be documented here before being introduced to the codebase.

2. **Variable Addition Process**:
   - Add the variable to this document first
   - Fill in all four columns: Variable, Scope, Data Type, Purpose
   - Ensure the variable follows established naming conventions
   - Place the variable in the correct scope section
   - Sort alphabetically within its scope section

3. **Variable Modification Process**:
   - Update this document before changing variable names in code
   - Document the old name alongside the new name temporarily
   - After code changes are complete, remove the old name reference

4. **Documentation Accuracy Verification**:
   - Run a quarterly audit to ensure all variables in code match this document
   - Verify that variable purposes match actual usage
   - Update variable descriptions to reflect any changes in functionality

5. **Reviewing Variable Additions**:
   - Check for naming convention compliance
   - Verify scope is correctly identified
   - Ensure data type is specific and accurate
   - Confirm purpose is clear, concise, and unambiguous
   - Look for potential name conflicts or confusing similarities

6. **Advanced Usage**:
   - Use this document as a tool for static analysis
   - Generate code linting rules from these conventions
   - Reference when creating new components that need to interact with existing variables

This document should be treated as a living specification - keep it current as the system evolves, and reference it during code reviews to maintain consistent variable usage throughout the codebase.

When updating this file, maintain this comment section to preserve these instructions.
-->
