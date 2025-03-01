#!/bin/bash
# validate-config.sh - Validate VLLMD Hypervisor TOML configuration against schema
set -euo pipefail

print_usage() {
    echo "Usage: bash validate-config.sh [--config CONFIG_FILE]"
    echo ""
    echo "Validate a VLLMD Hypervisor TOML configuration file against the JSON Schema."
    echo ""
    echo "Options:"
    echo "  --config CONFIG_FILE  Path to the TOML configuration file to validate"
    echo "                        (default: vllmd-hypervisor-runtime-defaults.toml)"
    echo "  --help                Display this help message and exit"
}

# Default values
CONFIG_PATH="vllmd-hypervisor-runtime-defaults.toml"
SCHEMA_PATH="vllmd-hypervisor-config-schema.json"

# Process command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --config=*)
            CONFIG_PATH="${1#*=}"
            shift
            ;;
        --config)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --config requires a value"
                exit 1
            fi
            CONFIG_PATH="$2"
            shift 2
            ;;
        --help)
            print_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# Check for required tools
if ! command -v python3 &> /dev/null; then
    echo "Error: python3 is required for validation"
    exit 1
fi

# Check if files exist
if [ ! -f "$CONFIG_PATH" ]; then
    echo "Error: Configuration file not found: $CONFIG_PATH"
    exit 1
fi

if [ ! -f "$SCHEMA_PATH" ]; then
    echo "Error: Schema file not found: $SCHEMA_PATH"
    exit 1
fi

# Simple one-time validation script using Python
python3 - "$CONFIG_PATH" "$SCHEMA_PATH" <<EOF
import sys
import json
try:
    import tomli as toml
except ImportError:
    try:
        import tomllib as toml
    except ImportError:
        print("Error: No TOML parser found. Install with: pip install tomli")
        sys.exit(1)

try:
    import jsonschema
except ImportError:
    print("Error: jsonschema package not found. Install with: pip install jsonschema")
    sys.exit(1)

try:
    config_path = sys.argv[1]
    schema_path = sys.argv[2]
    
    # Load the TOML configuration
    with open(config_path, "rb") as f:
        config = toml.load(f)
    
    # Load the JSON Schema
    with open(schema_path, "r") as f:
        schema = json.load(f)
    
    # Validate the configuration against the schema
    jsonschema.validate(config, schema)
    print(f"✅ Configuration file '{config_path}' is valid!")
    sys.exit(0)
    
except jsonschema.exceptions.ValidationError as e:
    print(f"❌ Validation error: {e.message}")
    if e.path:
        path_str = ".".join(str(p) for p in e.path)
        print(f"   Error location: {path_str}")
    sys.exit(1)
except Exception as e:
    print(f"❌ Error: {e}")
    sys.exit(1)
EOF

exit_code=$?

if [ $exit_code -ne 0 ]; then
    echo "Validation failed."
    exit 1
fi

echo "Configuration is valid and follows the schema definition."
exit 0