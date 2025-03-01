# VLLMD Hypervisor Variable Registry

The Variable Registry is a tool for working with the standardized variables defined in the VLLMD Hypervisor system. This tool reads and validates variables from the VARIABLES.md file, providing various utilities to maintain consistency across the codebase.

## Features

- **List Variables**: View all variables with their scope, data type, and purpose
- **Check Naming Conventions**: Validate that variables follow the established naming standards
- **Validate Scripts**: Scan shell scripts to ensure all VLLMD_HYPERVISOR variables are properly defined
- **Export Default Values**: Extract and export default values from variable definitions to a .env file

## Usage

```bash
# List all variables
bash variable-registry.sh list

# List variables of a specific scope
bash variable-registry.sh list --scope "Global"

# List variables of a specific type
bash variable-registry.sh list --type "Boolean"

# Check naming conventions
bash variable-registry.sh check-naming

# Validate a shell script
bash variable-registry.sh validate ./initialize-vllmd-hypervisor.sh

# Export default values to a .env file
bash variable-registry.sh export-defaults

# Export default values to a custom file
bash variable-registry.sh export-defaults /path/to/custom-defaults.env
```

## Integration with Development Workflow

The Variable Registry can be integrated into the development workflow in various ways:

1. **Pre-commit Hook**: Run `check-naming` before commits to ensure naming convention compliance
2. **CI/CD Pipeline**: Validate all scripts using the `validate` command during continuous integration
3. **Documentation Generation**: Use the `list` command to generate up-to-date variable documentation
4. **Configuration Management**: Use `export-defaults` to create configuration templates

## Implementation Details

The Variable Registry is implemented as a bash script (`variable-registry.sh`) that parses the VARIABLES.md file using standard Unix tools like grep, sed, and awk. The script follows these steps:

1. Extract variable definitions from the markdown tables in VARIABLES.md
2. Process and validate the extracted data
3. Provide utilities to work with the processed data

## Maintenance

To maintain the Variable Registry:

1. Always update VARIABLES.md when adding or modifying variables
2. Run `check-naming` regularly to ensure naming convention compliance
3. Use `validate` on all shell scripts that use VLLMD_HYPERVISOR variables
4. Keep the exported defaults file up-to-date by running `export-defaults` after updating variable definitions

## Example: Checking a New Script

```bash
# Create a new script
echo '#!/bin/bash
# Sample script using VLLMD Hypervisor variables
export VLLMD_HYPERVISOR_CONFIG_PATH="/etc/vllmd/conf.d"
export VLLMD_HYPERVISOR_LOG_PATH="/var/log/vllmd"
export VLLMD_HYPERVISOR_UNDEFINED_VARIABLE="/tmp"
' > /tmp/test-script.sh

# Validate the script
bash variable-registry.sh validate /tmp/test-script.sh
```

This will identify that `VLLMD_HYPERVISOR_UNDEFINED_VARIABLE` is not defined in VARIABLES.md.