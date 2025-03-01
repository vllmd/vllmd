#!/bin/bash
# install-vllmd-hypervisor-systemd.sh
# Configures systemd for VLLMD virtualization
set -euo pipefail

# Default configuration path
CONFIG_PATH="$HOME/.config/vllmd/vllmd-hypervisor-runtime-defaults.toml"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"

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

# Check if configuration file exists
if [ ! -f "$CONFIG_PATH" ]; then
    echo "Error: Configuration file not found: $CONFIG_PATH"
    echo "Please create the configuration file first."
    exit 1
fi

# Parse the TOML configuration
CONFIG_JSON=$(parse_toml)

# Create systemd user directory if it doesn't exist
mkdir -p "$SYSTEMD_USER_DIR"

# Enable systemd linger for current user
if ! loginctl show-user "$USER" | grep -q "Linger=yes"; then
    echo "Enabling systemd linger for user $USER"
    sudo loginctl enable-linger "$USER"
fi

# Create systemd service templates
cat > "$SYSTEMD_USER_DIR/vllmd-runtime-pre-start@.service" <<EOF
[Unit]
Description=VLLMD Pre-start setup for runtime %i
Before=vllmd-runtime@%i.service
Slice=vllmd.slice

[Service]
Type=oneshot
RemainAfterExit=yes
EnvironmentFile=%h/.config/vllmd/runtime-%i.env
ExecStart=/bin/sh -c 'echo "Configuring runtime %i environment"'
# Add pre-start commands here (network setup, etc.)

[Install]
WantedBy=default.target
EOF

cat > "$SYSTEMD_USER_DIR/vllmd-runtime@.service" <<EOF
[Unit]
Description=VLLMD Runtime %i
Requires=vllmd-runtime-pre-start@%i.service
After=vllmd-runtime-pre-start@%i.service
Slice=vllmd.slice

[Service]
Type=simple
EnvironmentFile=%h/.config/vllmd/runtime-%i.env
ExecStart=/bin/sh -c 'echo "Starting VLLMD runtime %i"'
# Add runtime start command here
ExecStop=/bin/sh -c 'echo "Stopping VLLMD runtime %i"'
# Add runtime stop command here
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

# Process runtime configurations
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

# Reload systemd user daemon
systemctl --user daemon-reload

# Enable services for each runtime
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

echo ""
echo "Systemd services installed and enabled."
echo "Start a specific runtime with: systemctl --user start vllmd-runtime@<index>"
echo "Start all runtimes with: systemctl --user start vllmd.slice"
echo "View status with: systemctl --user status vllmd-runtime@<index>"