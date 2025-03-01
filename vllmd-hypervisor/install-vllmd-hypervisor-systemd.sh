#!/bin/bash
# install-vllmd-hypervisor-systemd.sh
# Configures systemd for VLLMD virtualization
set -euo pipefail

# Default values
DRY_RUN=0
CONFIG_PATH="$HOME/.config/vllmd/vllmd-hypervisor-runtime-defaults.toml"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"

# Process command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --config=*)
            CONFIG_PATH="${1#*=}"
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Install VLLMD runtime systemd services"
            echo ""
            echo "Options:"
            echo "  --dry-run          Show what would be done without making changes"
            echo "  --config=PATH      Specify a custom config file path"
            echo "  --help             Display this help message and exit"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Output formatting for dry-run mode
DRY_RUN_PREFIX="[DRY RUN] "
print_dry_run() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo -e "${DRY_RUN_PREFIX}$1"
    fi
}

# Safe file creation function (respects dry-run mode)
safe_write_file() {
    local filepath="$1"
    local content="$2"
    
    if [[ "$DRY_RUN" -eq 1 ]]; then
        print_dry_run "Would create file: $filepath"
        print_dry_run "Content would be:"
        print_dry_run "----------------------------------------"
        echo "$content" | sed "s/^/${DRY_RUN_PREFIX}/"
        print_dry_run "----------------------------------------"
    else
        # Create parent directory if needed
        mkdir -p "$(dirname "$filepath")"
        echo "$content" > "$filepath"
        echo "Created file: $filepath"
    fi
}

# Safe mkdir function (respects dry-run mode)
safe_mkdir() {
    local dirpath="$1"
    
    if [[ "$DRY_RUN" -eq 1 ]]; then
        print_dry_run "Would create directory: $dirpath"
    else
        mkdir -p "$dirpath"
    fi
}

# Safe command execution function (respects dry-run mode)
safe_exec() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        print_dry_run "Would execute: $*"
    else
        "$@"
    fi
}

# Check for TOML parser
if ! command -v python3 &> /dev/null; then
    echo "Error: python3 is required for TOML parsing"
    exit 1
fi

# Function to parse TOML configuration using Python
parse_toml() {
    python3 - "$CONFIG_PATH" <<EOF
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
    with open(sys.argv[1], "rb") as f:
        config = toml.load(f)
    print(json.dumps(config))
except Exception as e:
    print(f"Error parsing TOML: {e}", file=sys.stderr)
    sys.exit(1)
EOF
}

# Dry run banner
if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "============================================="
    echo "VLLMD HYPERVISOR SYSTEMD INSTALLER (DRY RUN)"
    echo "============================================="
    echo "This is a dry run. No changes will be made to your system."
    echo "The following operations would be performed:"
    echo
fi

# Check if configuration file exists
if [ ! -f "$CONFIG_PATH" ]; then
    echo "Error: Configuration file not found: $CONFIG_PATH"
    echo "Please create the configuration file first."
    exit 1
fi

# Parse the TOML configuration
if [[ "$DRY_RUN" -eq 1 ]]; then
    print_dry_run "Would parse TOML configuration file: $CONFIG_PATH"
fi
CONFIG_JSON=$(parse_toml)

# Create systemd user directory if it doesn't exist
safe_mkdir "$SYSTEMD_USER_DIR"

# Enable systemd linger for current user
if ! loginctl show-user "$USER" | grep -q "Linger=yes"; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
        print_dry_run "Would enable systemd linger for user $USER"
        print_dry_run "Would execute: sudo loginctl enable-linger $USER"
    else
        echo "Enabling systemd linger for user $USER"
        sudo loginctl enable-linger "$USER"
    fi
else
    if [[ "$DRY_RUN" -eq 1 ]]; then
        print_dry_run "Systemd linger already enabled for user $USER (no changes needed)"
    else
        echo "Systemd linger already enabled for user $USER"
    fi
fi

# Create service template content
pre_start_service_content="[Unit]
Description=VLLMD Pre-start setup for runtime %i
Before=vllmd-runtime@%i.service
Slice=vllmd.slice

[Service]
Type=oneshot
RemainAfterExit=yes
EnvironmentFile=%h/.config/vllmd/runtime-%i.env
ExecStart=/bin/sh -c 'echo \"Configuring runtime %i environment\"'
# Add pre-start commands here (network setup, etc.)

[Install]
WantedBy=default.target"

main_service_content="[Unit]
Description=VLLMD Runtime %i
Requires=vllmd-runtime-pre-start@%i.service
After=vllmd-runtime-pre-start@%i.service
Slice=vllmd.slice

[Service]
Type=simple
EnvironmentFile=%h/.config/vllmd/runtime-%i.env
ExecStart=/bin/sh -c 'echo \"Starting VLLMD runtime %i\"'
# Add runtime start command here
ExecStop=/bin/sh -c 'echo \"Stopping VLLMD runtime %i\"'
# Add runtime stop command here
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target"

# Create systemd service templates
safe_write_file "$SYSTEMD_USER_DIR/vllmd-runtime-pre-start@.service" "$pre_start_service_content"
safe_write_file "$SYSTEMD_USER_DIR/vllmd-runtime@.service" "$main_service_content"

# Process runtime configurations
if [[ "$DRY_RUN" -eq 1 ]]; then
    # In dry-run mode, parse JSON and show what would be created
    echo "$CONFIG_JSON" | python3 -c "
import sys
import json
import os

config = json.load(sys.stdin)
dry_run_prefix = '[DRY RUN] '

if 'runtimes' not in config:
    print(f'{dry_run_prefix}Error: No runtimes defined in configuration')
    sys.exit(1)

print(f'{dry_run_prefix}Found {len(config['runtimes'])} runtime(s) in configuration')

# Process each runtime
for runtime in config['runtimes']:
    if 'index' not in runtime or 'name' not in runtime:
        print(f'{dry_run_prefix}Warning: Skipping runtime without index or name')
        continue
        
    index = runtime['index']
    name = runtime['name']
    
    # Show environment file that would be created
    env_path = os.path.expandvars(f'\$HOME/.config/vllmd/runtime-{index}.env')
    
    print(f'{dry_run_prefix}Would create environment file: {env_path}')
    print(f'{dry_run_prefix}Content would be:')
    print(f'{dry_run_prefix}----------------------------------------')
    print(f'{dry_run_prefix}# VLLMD Runtime {index} Environment')
    print(f'{dry_run_prefix}VLLMD_RUNTIME_NAME={name}')
    
    # Add GPUs
    if 'gpus' in runtime and isinstance(runtime['gpus'], list):
        gpus_str = ','.join(runtime['gpus'])
        print(f'{dry_run_prefix}VLLMD_RUNTIME_GPUS={gpus_str}')
        
    # Add memory
    if 'memory_gb' in runtime:
        print(f'{dry_run_prefix}VLLMD_RUNTIME_MEMORY={runtime['memory_gb']}G')
        
    # Add CPUs
    if 'cpus' in runtime:
        print(f'{dry_run_prefix}VLLMD_RUNTIME_CPUS={runtime['cpus']}')
    
    print(f'{dry_run_prefix}----------------------------------------')
    
    # Show systemd services that would be enabled
    print(f'{dry_run_prefix}Would enable systemd services:')
    print(f'{dry_run_prefix}  - vllmd-runtime-pre-start@{index}.service')
    print(f'{dry_run_prefix}  - vllmd-runtime@{index}.service')
"
else
    # Normal mode - actually create the files
    echo "$CONFIG_JSON" | python3 -c '
import sys
import json
import os

config = json.load(sys.stdin)

if "runtimes" not in config:
    print("Error: No runtimes defined in configuration")
    sys.exit(1)

# Process each runtime
for runtime in config["runtimes"]:
    if "index" not in runtime or "name" not in runtime:
        print("Warning: Skipping runtime without index or name")
        continue
        
    index = runtime["index"]
    name = runtime["name"]
    
    # Create environment file
    env_path = os.path.expandvars(f"$HOME/.config/vllmd/runtime-{index}.env")
    
    # Ensure directory exists
    os.makedirs(os.path.dirname(env_path), exist_ok=True)
    
    with open(env_path, "w") as f:
        f.write(f"# VLLMD Runtime {index} Environment\n")
        f.write(f"VLLMD_RUNTIME_NAME={name}\n")
        
        # Add GPUs
        if "gpus" in runtime and isinstance(runtime["gpus"], list):
            gpus_str = ",".join(runtime["gpus"])
            f.write(f"VLLMD_RUNTIME_GPUS={gpus_str}\n")
            
        # Add memory
        if "memory_gb" in runtime:
            f.write(f"VLLMD_RUNTIME_MEMORY={runtime['memory_gb']}G\n")
            
        # Add CPUs
        if "cpus" in runtime:
            f.write(f"VLLMD_RUNTIME_CPUS={runtime['cpus']}\n")
    
    print(f"Created environment file for runtime-{index}")
'
fi

# Reload systemd user daemon
if [[ "$DRY_RUN" -eq 1 ]]; then
    print_dry_run "Would reload systemd user daemon"
    print_dry_run "Would execute: systemctl --user daemon-reload"
else
    echo "Reloading systemd user daemon"
    systemctl --user daemon-reload
fi

# Enable services for each runtime
if [[ "$DRY_RUN" -eq 1 ]]; then
    # In dry-run mode, we've already shown which services would be enabled
    :
else
    # Normal mode - actually enable the services
    echo "$CONFIG_JSON" | python3 -c '
import sys
import json
import subprocess

config = json.load(sys.stdin)

if "runtimes" not in config:
    print("Error: No runtimes defined in configuration")
    sys.exit(1)

# Enable services for each runtime
for runtime in config["runtimes"]:
    if "index" not in runtime:
        continue
        
    index = runtime["index"]
    
    # Enable pre-start service
    pre_start_cmd = ["systemctl", "--user", "enable", f"vllmd-runtime-pre-start@{index}.service"]
    subprocess.run(pre_start_cmd, check=True)
    
    # Enable main service
    main_cmd = ["systemctl", "--user", "enable", f"vllmd-runtime@{index}.service"]
    subprocess.run(main_cmd, check=True)
    
    print(f"Enabled services for runtime-{index}")
'
fi

# Final output
echo ""
if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "==============================================="
    echo "DRY RUN COMPLETE - NO CHANGES WERE MADE"
    echo "==============================================="
    echo "To apply these changes, run the script without the --dry-run flag:"
    echo "  bash $0"
else
    echo "Systemd services installed and enabled."
    echo "Start a specific runtime with: systemctl --user start vllmd-runtime@<index>"
    echo "Start all runtimes with: systemctl --user start vllmd.slice"
    echo "View status with: systemctl --user status vllmd-runtime@<index>"
fi