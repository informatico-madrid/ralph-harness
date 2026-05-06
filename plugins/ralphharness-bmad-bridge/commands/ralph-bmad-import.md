---
name: ralph-bmad:import
description: Import BMAD planning artifacts into a RalphHarness spec
---

# /ralph-bmad:import

Import BMAD planning artifacts into a RalphHarness spec.

## Usage

```
/ralph-bmad:import <bmad-project-path> <spec-name>
```

## Arguments

- **bmad-project-path** (required): Path to the BMAD project directory containing `_bmad-output/`
- **spec-name** (required): Name for the output spec (lowercase alphanumeric with hyphens)

## Implementation

# Parse positional arguments from $ARGUMENTS
read -r BMAD_PATH SPEC_NAME <<< "$ARGUMENTS"

# Validate parsed arguments from $ARGUMENTS
if [ -z "$BMAD_PATH" ] || [ -z "$SPEC_NAME" ]; then
  echo "Usage: /ralph-bmad:import <bmad-project-path> <spec-name>"
  exit 1
fi

# Execute import.sh with $BMAD_PATH and $SPEC_NAME ($1 $2 from $ARGUMENTS)
bash "${CLAUDE_PLUGIN_ROOT}/scripts/import.sh" "$BMAD_PATH" "$SPEC_NAME"
exit $?
