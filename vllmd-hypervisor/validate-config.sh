#!/bin/bash
# validate-config.sh - Validate VLLMD Hypervisor TOML configuration against schema
set -euo pipefail

print_usage() {
    echo "Usage: bash validate-config.sh [OPTIONS]"
    echo ""
    echo "Validate a VLLMD Hypervisor TOML configuration file against the JSON Schema."
    echo ""
    echo "Options:"
    echo "  --config CONFIG_FILE  Path to the TOML configuration file to validate"
    echo "                        (default: vllmd-hypervisor-runtime-defaults.toml)"
    echo "  --schema SCHEMA_FILE  Path to the JSON schema file"
    echo "                        (default: vllmd-hypervisor-config-schema.json)"
    echo "  --strict              Enable strict validation mode (fail on any schema violation)"
    echo "  --lenient             Enable lenient validation mode (warn on minor issues)"
    echo "  --quiet               Suppress all output except errors"
    echo "  --summary             Print a summary of validation results"
    echo "  --help                Display this help message and exit"
}

# Default values
CONFIG_PATH="vllmd-hypervisor-runtime-defaults.toml"
SCHEMA_PATH="vllmd-hypervisor-config-schema.json"
VALIDATION_MODE="strict"
QUIET=0
SUMMARY=0

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
        --schema=*)
            SCHEMA_PATH="${1#*=}"
            shift
            ;;
        --schema)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --schema requires a value"
                exit 1
            fi
            SCHEMA_PATH="$2"
            shift 2
            ;;
        --strict)
            VALIDATION_MODE="strict"
            shift
            ;;
        --lenient)
            VALIDATION_MODE="lenient"
            shift
            ;;
        --quiet)
            QUIET=1
            shift
            ;;
        --summary)
            SUMMARY=1
            shift
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

# Helper functions
log() {
    if [[ "$QUIET" -eq 0 ]]; then
        echo "$@"
    fi
}

error() {
    echo "ERROR: $@" >&2
}

warning() {
    echo "WARNING: $@" >&2
}

# Banner
if [[ "$QUIET" -eq 0 ]]; then
    log "============================================="
    log "VLLMD Hypervisor Configuration Validator"
    log "============================================="
    log "Validation mode: $VALIDATION_MODE"
    log "Configuration: $CONFIG_PATH"
    log "Schema: $SCHEMA_PATH"
    log
fi

# Check for required tools
if ! command -v python3 &> /dev/null; then
    error "python3 is required for validation"
    exit 1
fi

# Check if files exist
if [ ! -f "$CONFIG_PATH" ]; then
    error "Configuration file not found: $CONFIG_PATH"
    exit 1
fi

if [ ! -f "$SCHEMA_PATH" ]; then
    error "Schema file not found: $SCHEMA_PATH"
    exit 1
fi

# Enhanced validation script using Python with lenient/strict modes
python3 - "$CONFIG_PATH" "$SCHEMA_PATH" "$VALIDATION_MODE" "$QUIET" "$SUMMARY" <<EOF
import sys
import json
import os

# Import required modules
try:
    import tomli as toml
except ImportError:
    try:
        import tomllib as toml
    except ImportError:
        print("Error: No TOML parser found. Install with: pip install tomli", file=sys.stderr)
        sys.exit(1)

try:
    import jsonschema
except ImportError:
    print("Error: jsonschema package not found. Install with: pip install jsonschema", file=sys.stderr)
    sys.exit(1)

class ValidationError(Exception):
    def __init__(self, message, path=None, severity="error"):
        self.message = message
        self.path = path
        self.severity = severity
        super().__init__(self.message)

def format_path(path):
    """Format a JSON path into a readable string."""
    if not path:
        return "<root>"
    return ".".join(str(p) for p in path)

def validate_config(config_path, schema_path, mode="strict"):
    """Validate a TOML configuration against a JSON Schema."""
    issues = []
    
    try:
        # Load the TOML configuration
        with open(config_path, "rb") as f:
            config = toml.load(f)
        
        # Load the JSON Schema
        with open(schema_path, "r") as f:
            schema = json.load(f)
        
        # Check schema version
        schema_version = schema.get("$schema")
        if schema_version and schema_version != "http://json-schema.org/draft-07/schema#":
            issues.append(ValidationError(
                f"Schema version mismatch. Expected draft-07, found: {schema_version}",
                severity="warning"
            ))
        
        # Pre-validation checks (lenient mode extra checks)
        if mode == "lenient":
            # Check for potentially missing optional fields with defaults
            for section, props in schema.get("properties", {}).items():
                if section not in config and section not in schema.get("required", []):
                    issues.append(ValidationError(
                        f"Optional section '{section}' is missing. Default values will be used.",
                        severity="info"
                    ))
                elif section in config and isinstance(props, dict):
                    section_props = props.get("properties", {})
                    for prop, details in section_props.items():
                        if prop not in config[section] and "default" in details:
                            issues.append(ValidationError(
                                f"Optional property '{section}.{prop}' is missing. " + 
                                f"Default value will be used: {details['default']}",
                                [section, prop],
                                severity="info"
                            ))
        
        # Perform schema validation
        jsonschema.validate(config, schema)
        
        # Post-validation checks (both modes)
        if "runtimes" in config:
            # Check for duplicate indices
            indices = [r.get("index") for r in config["runtimes"] if "index" in r]
            if len(indices) != len(set(indices)):
                # Find the duplicates
                seen = set()
                dupes = [x for x in indices if x in seen or seen.add(x)]
                issues.append(ValidationError(
                    f"Duplicate runtime indices found: {dupes}",
                    ["runtimes"],
                    severity="error"
                ))
            
            # Check for duplicate names
            names = [r.get("name") for r in config["runtimes"] if "name" in r]
            if len(names) != len(set(names)):
                # Find the duplicates
                seen = set()
                dupes = [x for x in names if x in seen or seen.add(x)]
                issues.append(ValidationError(
                    f"Duplicate runtime names found: {dupes}",
                    ["runtimes"],
                    severity="error"
                ))
        
        return issues
    except jsonschema.exceptions.ValidationError as e:
        issues.append(ValidationError(
            e.message,
            list(e.path),
            severity="error"
        ))
        return issues
    except Exception as e:
        issues.append(ValidationError(
            str(e),
            severity="error"
        ))
        return issues

# Parse command line arguments
config_path = sys.argv[1]
schema_path = sys.argv[2]
validation_mode = sys.argv[3]
quiet = int(sys.argv[4])
summary = int(sys.argv[5])

# Run validation
issues = validate_config(config_path, schema_path, validation_mode)

# Process results
errors = [i for i in issues if i.severity == "error"]
warnings = [i for i in issues if i.severity == "warning"]
infos = [i for i in issues if i.severity == "info"]

# Print issues
if not quiet:
    # Print errors
    for issue in errors:
        path_str = format_path(issue.path) if hasattr(issue, 'path') and issue.path else ""
        loc = f" at {path_str}" if path_str else ""
        print(f"❌ ERROR{loc}: {issue.message}", file=sys.stderr)
    
    # Print warnings
    for issue in warnings:
        path_str = format_path(issue.path) if hasattr(issue, 'path') and issue.path else ""
        loc = f" at {path_str}" if path_str else ""
        print(f"⚠️ WARNING{loc}: {issue.message}")
    
    # Print info messages in lenient mode
    if validation_mode == "lenient":
        for issue in infos:
            path_str = format_path(issue.path) if hasattr(issue, 'path') and issue.path else ""
            loc = f" at {path_str}" if path_str else ""
            print(f"ℹ️ INFO{loc}: {issue.message}")

# Print summary if requested
if summary:
    print(f"\nValidation Summary:")
    print(f"  Configuration file: {os.path.basename(config_path)}")
    print(f"  Validation mode: {validation_mode}")
    print(f"  Errors: {len(errors)}")
    print(f"  Warnings: {len(warnings)}")
    print(f"  Info messages: {len(infos)}")

# Determine exit code
if errors:
    # Always fail on errors
    sys.exit(1)
elif warnings and validation_mode == "strict":
    # Fail on warnings in strict mode
    sys.exit(1)
else:
    # Success in lenient mode or no issues
    if not quiet and not errors and not warnings:
        print(f"✅ Configuration file '{config_path}' is valid!")
    sys.exit(0)
EOF

exit_code=$?

# Final output
if [[ "$exit_code" -eq 0 ]]; then
    if [[ "$SUMMARY" -eq 1 && "$QUIET" -eq 0 ]]; then
        log "============================================="
        log "Validation completed successfully"
        log "============================================="
    elif [[ "$QUIET" -eq 0 ]]; then
        log "Configuration is valid and follows the schema definition."
    fi
    exit 0
else
    if [[ "$SUMMARY" -eq 1 && "$QUIET" -eq 0 ]]; then
        log "============================================="
        log "Validation failed"
        log "============================================="
    elif [[ "$QUIET" -eq 0 ]]; then
        error "Validation failed. Please fix the errors above."
    fi
    exit 1
fi