# VLLMD Hypervisor Configuration Validation

This document describes the configuration validation features for VLLMD Hypervisor.

## Overview

VLLMD Hypervisor includes robust configuration validation to ensure that your configuration files are correct before using them. This helps prevent runtime errors and provides clear feedback about configuration issues.

## Validation Methods

### 1. Standalone Validation

Use the `validate-config.sh` script to validate a configuration file against the schema:

```bash
# Basic validation with default settings
bash validate-config.sh

# Validate a specific configuration file
bash validate-config.sh --config=my-config.toml

# Validate with strict checking (fails on any issue)
bash validate-config.sh --strict

# Validate with lenient checking (warns on minor issues)
bash validate-config.sh --lenient

# Show a summary of validation results
bash validate-config.sh --summary
```

### 2. Integrated Validation

The installer script `install-vllmd-hypervisor-systemd.sh` includes built-in validation:

```bash
# Run with validation (default is lenient if validate-config.sh exists)
bash install-vllmd-hypervisor-systemd.sh

# Force validation in strict mode
bash install-vllmd-hypervisor-systemd.sh --validate-strict

# Skip validation
bash install-vllmd-hypervisor-systemd.sh --no-validate
```

## Validation Modes

### Strict Mode

- Fails on any schema violation, including minor issues
- Recommended for CI/CD pipelines and deployment systems
- Ensures complete compliance with the schema

```bash
bash validate-config.sh --strict
```

### Lenient Mode

- Warns on minor issues (like missing optional fields)
- Fails only on critical errors
- Better for development and testing

```bash
bash validate-config.sh --lenient
```

## Validation Checks

The validation system performs the following checks:

1. **Schema Compliance**: Verifies that the configuration follows the JSON Schema definition
2. **Type Checking**: Ensures values have the correct types (string, integer, etc.)
3. **Constraint Validation**: Checks minimum/maximum values, patterns, etc.
4. **Required Fields**: Confirms all required fields are present
5. **Duplicate Detection**: Identifies duplicate runtime names or indices
6. **Format Validation**: Ensures values like PCI addresses follow the correct format

## Error Messages

Validation errors include:

- The error type (ERROR, WARNING, INFO)
- The path to the problematic field
- A clear message explaining the issue

Example:
```
❌ ERROR at runtimes.0.gpus.0: String '0000X:01:00.0' does not match pattern '^[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\\.[0-9a-fA-F]$'
```

## Schema Version

The configuration schema includes version information to track changes over time:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "VLLMD Hypervisor Configuration Schema",
  "description": "Schema definition for VLLMD Hypervisor configuration",
  "version": "1.0.0",
  ...
}
```

This versioning allows for future schema changes while maintaining compatibility with existing configurations.

## Best Practices

1. Always validate your configuration before use
2. Use strict validation in production environments
3. Fix all validation errors, even in lenient mode
4. Add schema references to your configuration files (`# $schema: vllmd-hypervisor-config-schema.json`)
5. Use the summary option for a quick overview of validation results