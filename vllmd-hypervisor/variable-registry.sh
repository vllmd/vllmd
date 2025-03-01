#!/usr/bin/env bash
# VLLMD Hypervisor Variable Registry
#
# This script provides functionality to work with variables defined in VARIABLES.md.
# It can:
# - List all variables with their scope and type
# - Check naming conventions
# - Validate variables used in scripts
#
# Usage:
#   ./variable-registry.sh list [--scope SCOPE] [--type TYPE]
#   ./variable-registry.sh check-naming
#   ./variable-registry.sh validate FILE
#   ./variable-registry.sh export-defaults

set -euo pipefail

# Get the directory of this script
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
VARIABLES_MD="${SCRIPT_DIR}/VARIABLES.md"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Ensure VARIABLES.md exists
if [[ ! -f "${VARIABLES_MD}" ]]; then
  echo -e "${RED}Error: ${VARIABLES_MD} not found${NC}"
  exit 1
fi

# Function to extract variables from VARIABLES.md
extract_variables() {
  # Use grep to extract variable lines, then process with awk
  grep -oP '^\|\s*`([^`]+)`\s*\|\s*([^|]+)\|\s*([^|]+)\|\s*([^|]+)\|' "${VARIABLES_MD}" | \
  awk -F '|' '{
    # Extract variable name (remove backticks)
    gsub(/`/, "", $2)
    var_name = $2
    
    # Extract scope
    scope = $3
    
    # Extract data type 
    data_type = $4
    
    # Extract purpose
    purpose = $5
    
    # Clean up whitespace
    gsub(/^[ \t]+|[ \t]+$/, "", var_name)
    gsub(/^[ \t]+|[ \t]+$/, "", scope)
    gsub(/^[ \t]+|[ \t]+$/, "", data_type)
    gsub(/^[ \t]+|[ \t]+$/, "", purpose)
    
    # Print as tab-separated values for easy processing
    print var_name "\t" scope "\t" data_type "\t" purpose
  }'
}

# Function to list variables, optionally filtered by scope or type
list_variables() {
  local scope_filter=""
  local type_filter=""
  
  # Parse arguments
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      --scope)
        scope_filter="$2"
        shift 2
        ;;
      --type)
        type_filter="$2"
        shift 2
        ;;
      *)
        echo -e "${RED}Unknown parameter: $1${NC}"
        return 1
        ;;
    esac
  done
  
  # Extract and filter variables
  extract_variables | while IFS=$'\t' read -r name scope type purpose; do
    # Apply filters if specified
    if [[ -n "${scope_filter}" && "${scope}" != *"${scope_filter}"* ]]; then
      continue
    fi
    
    if [[ -n "${type_filter}" && "${type}" != *"${type_filter}"* ]]; then
      continue
    fi
    
    # Print variable details
    echo -e "${BLUE}${name}${NC}"
    echo -e "  Scope: ${scope}"
    echo -e "  Type: ${type}"
    echo -e "  Purpose: ${purpose}"
    echo ""
  done
}

# Function to check naming conventions
check_naming_conventions() {
  local violations=0
  
  echo "Checking naming conventions..."
  
  extract_variables | while IFS=$'\t' read -r name scope type purpose; do
    # Check if global variables start with VLLMD_HYPERVISOR_
    if [[ "${scope}" == "Global"* && ! "${name}" =~ ^VLLMD_HYPERVISOR_ ]]; then
      echo -e "${RED}ERROR:${NC} Global variable '${name}' does not start with 'VLLMD_HYPERVISOR_'"
      ((violations++))
    fi
    
    # Check if path variables end with _PATH
    if [[ "${name}" =~ [Pp][Aa][Tt][Hh] && ! "${name}" =~ _PATH$ && ! "${name}" =~ _FILEPATH$ ]]; then
      echo -e "${YELLOW}WARNING:${NC} Path variable '${name}' should end with '_PATH' or '_FILEPATH'"
      ((violations++))
    fi
    
    # Check if file path variables end with _FILEPATH
    if [[ "${name}" =~ [Ff][Ii][Ll][Ee] && "${name}" =~ [Pp][Aa][Tt][Hh] && ! "${name}" =~ _FILEPATH$ ]]; then
      echo -e "${YELLOW}WARNING:${NC} File path variable '${name}' should end with '_FILEPATH'"
      ((violations++))
    fi
    
    # Check if array variables end with _LIST
    if [[ "${type}" == "Array" && ! "${name}" =~ _LIST$ ]]; then
      echo -e "${YELLOW}WARNING:${NC} Array variable '${name}' should end with '_LIST'"
      ((violations++))
    fi
    
    # Check if count variables end with _COUNT
    if [[ "${name}" =~ [Cc][Oo][Uu][Nn][Tt] && ! "${name}" =~ _COUNT$ ]]; then
      echo -e "${YELLOW}WARNING:${NC} Count variable '${name}' should end with '_COUNT'"
      ((violations++))
    fi
  done
  
  if [[ ${violations} -eq 0 ]]; then
    echo -e "${GREEN}All variables follow naming conventions.${NC}"
    return 0
  else
    echo -e "${RED}Found ${violations} naming convention violations.${NC}"
    return 1
  fi
}

# Function to validate variables used in a script
validate_script() {
  local script_file="$1"
  local undefined_vars=0
  
  if [[ ! -f "${script_file}" ]]; then
    echo -e "${RED}Error: Script file ${script_file} not found${NC}"
    return 1
  fi
  
  echo "Validating variables in ${script_file}..."
  
  # Create an array of all defined variable names
  mapfile -t defined_vars < <(extract_variables | cut -f1)
  
  # Extract variable references from the script file
  # This looks for $VAR and ${VAR} patterns
  mapfile -t script_vars < <(grep -oP '\$\{?([A-Za-z0-9_]+)\}?' "${script_file}" | \
                             sed -E 's/\$\{?([A-Za-z0-9_]+)\}?/\1/g' | \
                             grep -i "^VLLMD_HYPERVISOR_" | sort -u)
  
  echo "Found ${#script_vars[@]} VLLMD_HYPERVISOR variables in script."
  
  # Check each variable against the defined variables
  for var in "${script_vars[@]}"; do
    if [[ ! " ${defined_vars[*]} " =~ " ${var} " ]]; then
      echo -e "${RED}ERROR:${NC} Undefined variable '${var}' used in script"
      ((undefined_vars++))
    else
      echo -e "${GREEN}OK:${NC} Variable '${var}' is properly defined"
    fi
  done
  
  if [[ ${undefined_vars} -eq 0 ]]; then
    echo -e "${GREEN}All VLLMD_HYPERVISOR variables in the script are properly defined.${NC}"
    return 0
  else
    echo -e "${RED}Found ${undefined_vars} undefined variables.${NC}"
    return 1
  fi
}

# Function to export default values of variables to a .env file
export_defaults() {
  local output_file="${1:-${SCRIPT_DIR}/hypervisor-defaults.env}"
  
  echo "Exporting default values to ${output_file}..."
  
  # Add header to the file
  cat > "${output_file}" << 'EOF'
# VLLMD Hypervisor Default Variable Values
# This file was automatically generated from VARIABLES.md
# DO NOT EDIT THIS FILE DIRECTLY - update VARIABLES.md instead

EOF
  
  # Extract default values from purposes field
  extract_variables | while IFS=$'\t' read -r name scope type purpose; do
    # Only process global variables
    if [[ "${scope}" != "Global"* ]]; then
      continue
    fi
    
    # Try to extract default value from purpose field
    if [[ "${purpose}" =~ [Dd]efault:\ *\`([^\`]+)\` ]]; then
      default_value="${BASH_REMATCH[1]}"
      # Remove trailing punctuation
      default_value="${default_value%\.*}"
      default_value="${default_value%\,*}"
      # Trim whitespace
      default_value="$(echo "${default_value}" | xargs)"
      
      # Add variable with default value to the file
      echo "${name}=\"${default_value}\"" >> "${output_file}"
    fi
  done
  
  echo -e "${GREEN}Default values exported to ${output_file}${NC}"
}

# Main execution logic
main() {
  local command="${1:-help}"
  shift || true
  
  case "${command}" in
    list)
      list_variables "$@"
      ;;
    check-naming)
      check_naming_conventions
      ;;
    validate)
      if [[ $# -lt 1 ]]; then
        echo -e "${RED}Error: Please provide a script file to validate${NC}"
        exit 1
      fi
      validate_script "$1"
      ;;
    export-defaults)
      export_defaults "$@"
      ;;
    help|--help|-h)
      echo "VLLMD Hypervisor Variable Registry"
      echo ""
      echo "Usage:"
      echo "  $0 list [--scope SCOPE] [--type TYPE]"
      echo "  $0 check-naming"
      echo "  $0 validate FILE"
      echo "  $0 export-defaults [OUTPUT_FILE]"
      echo ""
      echo "Commands:"
      echo "  list            List all variables with their scope and type"
      echo "  check-naming    Check if variables follow naming conventions"
      echo "  validate        Validate variables used in a script file"
      echo "  export-defaults Export default values to a .env file"
      echo ""
      echo "Options:"
      echo "  --scope SCOPE   Filter variables by scope"
      echo "  --type TYPE     Filter variables by data type"
      echo ""
      echo "Examples:"
      echo "  $0 list --scope 'Global'"
      echo "  $0 validate ./initialize-vllmd-hypervisor.sh"
      ;;
    *)
      echo -e "${RED}Unknown command: ${command}${NC}"
      echo "Use '$0 help' to see available commands"
      exit 1
      ;;
  esac
}

# Run the main function with all arguments
main "$@"