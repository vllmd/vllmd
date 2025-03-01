# VLLMD Hypervisor Configuration Schema

This document describes the JSON Schema for the VLLMD Hypervisor TOML configuration file.

## Overview

The `vllmd-hypervisor-config-schema.json` file defines the structure, constraints, and validation rules for the VLLMD Hypervisor configuration. While the configuration itself is in TOML format, the schema is defined in JSON Schema format (draft-07) for broader compatibility and tooling support.

## Schema Structure

The schema defines the following top-level sections:

### Global Settings

These settings apply to all runtimes and define the overall configuration.

```toml
[global]
user = "sdake"
state_dir = "$HOME/.local/state/vllmd-hypervisor"
config_dir = "$HOME/.config/vllmd"
default_memory_gb = 16
default_cpus = 4
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `user` | string | Yes | Username for systemd services |
| `state_dir` | string | No | Directory path for state data |
| `config_dir` | string | No | Directory path for configuration files |
| `default_memory_gb` | integer | No | Default memory allocation in GB |
| `default_cpus` | integer | No | Default CPU allocation |

### Runtime Definitions

These define the virtual machine runtimes, each with its own resource allocations and configuration.

```toml
[[runtimes]]
index = 1
gpus = ["0000:01:00.0"]
memory_gb = 32
cpus = 8
name = "runtime-1"
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `index` | integer | Yes | Unique index for the runtime (min: 1) |
| `name` | string | Yes | Descriptive name for the runtime |
| `gpus` | array | No | Array of GPU PCI addresses |
| `memory_gb` | integer | No | Memory allocation in GB |
| `cpus` | integer | No | Number of CPU cores |

### Network Configuration

These settings define the network configuration for VM connectivity.

```toml
[network]
default_interface = "eth0"
bridge_name = "vllmd-br0"
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `default_interface` | string | No | Default host network interface |
| `bridge_name` | string | No | Name of the bridge interface |

## Validation

You can validate your TOML configuration against this schema using tools such as:

- [toml-to-json](https://www.npmjs.com/package/toml-to-json) to convert TOML to JSON
- [jsonschema](https://python-jsonschema.readthedocs.io/) for Python validation
- [ajv](https://ajv.js.org/) for JavaScript validation

Example validation with Python:

```python
import tomli
import json
import jsonschema

# Load the configuration
with open('vllmd-hypervisor-runtime-defaults.toml', 'rb') as f:
    config = tomli.load(f)

# Load the schema
with open('vllmd-hypervisor-config-schema.json') as f:
    schema = json.load(f)

# Validate the configuration against the schema
jsonschema.validate(config, schema)
```

## IDE Integration

Many IDEs support JSON Schema validation. You can add a reference to the schema in your TOML file using a comment:

```toml
# $schema: file:///path/to/vllmd-hypervisor-config-schema.json
# VLLMD Hypervisor Runtime Defaults
# Configuration file for VLLMD virtual machine runtime resources

[global]
# ...
```

Note that IDE support for TOML schemas varies, and you may need additional plugins or tools for full validation support.

## Best Practices

1. Always validate your configuration against the schema before using it
2. Use descriptive names for your runtimes
3. Set appropriate resource limits based on your hardware
4. Keep PCI addresses in the format `0000:00:00.0`
5. Use environment variables in paths when appropriate