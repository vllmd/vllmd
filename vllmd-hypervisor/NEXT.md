# VLLMD Hypervisor Next Steps

This document outlines the planned next steps for the VLLMD Hypervisor project, focusing on enhancing configuration management and validation.

## Upcoming Features

### 1. Dry Run Mode

Add a dry-run flag to the installer script that shows what would be done without making any changes:

- Show which files would be created
- Display systemd services that would be enabled
- Output environment file contents
- No actual filesystem or systemd changes

**Issue**: #TBD - "Add dry-run mode to VLLMD Hypervisor systemd installer"

### 2. Configuration Schema Definition

Create a JSON Schema definition for the TOML configuration file:

- Define all valid configuration options
- Document field purposes and constraints
- Specify required vs. optional fields
- Provide type definitions and validation rules

**Issue**: #TBD - "Add configuration schema definition for VLLMD Hypervisor"

### 3. Schema Validation

Implement schema validation for the configuration file:

- Validate configuration against the schema definition
- Provide helpful error messages for invalid configurations
- Support strict and lenient validation modes
- Add schema version tracking

**Issue**: #TBD - "Implement schema validation for VLLMD Hypervisor configuration"

## Implementation Plan

Each feature will be implemented independently with its own:
- GitHub issue for tracking
- Feature branch for development
- Pull request for review
- Documentation updates

<!--
INSTRUCTIONS:

This is an iterative development process with the following steps for each feature:

1. ISSUE CREATION:
- Create a detailed GitHub issue for the feature
- Include motivation, requirements, and acceptance criteria
- Add relevant labels and assign to the sprint

2. BRANCH CREATION:
- Create a topic branch named: vllmd-hypervisor/<feature-name>
- Base it on the latest main branch

3. IMPLEMENTATION:
- Develop the feature according to the requirements
- Add tests to verify functionality
- Update documentation to reflect changes
- Follow existing coding patterns and style

4. PULL REQUEST:
- Create a pull request with a detailed description
- Reference the issue number with "Resolves #XX"
- Include testing evidence and implementation notes
- Request review from the team

5. REVIEW AND MERGE:
- Address review feedback
- Update the PR as needed
- Merge using rebase strategy (not merge commits)
- Delete the branch after successful merge

The features should be implemented in this order:
1. Dry Run Mode
2. Configuration Schema Definition
3. Schema Validation

Each feature builds upon the previous one but should be implemented with minimal dependencies to allow independent review and merging.
-->