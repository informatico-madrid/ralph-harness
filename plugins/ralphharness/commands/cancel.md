---
description: Cancel active execution loop, cleanup state, and remove spec
argument-hint: [spec-name-or-path]
allowed-tools: [Read, Bash, Task]
---

# Cancel Execution

You are canceling the active execution loop, cleaning up state files, and removing the spec directory.

## Multi-Directory Resolution

This command uses the path resolver for multi-root spec discovery:

```bash
# Source the path resolver (conceptual - commands use these patterns)
# ralph_find_spec(name)   - Find spec by name across all roots
# ralph_resolve_current() - Get current spec's full path
```

## Determine Target Spec

1. If `$ARGUMENTS` contains input:
   - If starts with `./` or `/`: treat as full path, validate it exists
   - Otherwise: treat as spec name, use `ralph_find_spec()` pattern to search
2. If no argument provided:
   - Use `ralph_resolve_current()` pattern to get active spec path from `.current-spec`
3. If no active spec and no argument, inform user there's nothing to cancel

### Handle Disambiguation

If spec name exists in multiple roots (exit code 2 from find):

```
Multiple specs named '$name' found:
1. ./specs/$name
2. ./packages/api/specs/$name

Specify: /ralphharness:cancel ./packages/api/specs/$name
```

Do NOT automatically select one. User must specify the full path.

## Check State

1. Check if `$spec_path/.ralph-state.json` exists (where `$spec_path` is the resolved full path)
2. If not, inform user no active loop for this spec

## Read Current State

If state file exists, read and display:
- Current phase
- Task progress (taskIndex/totalTasks)
- Iteration count

## Cleanup

1. Delete state file:
   ```bash
   rm $spec_path/.ralph-state.json
   ```

2. Remove spec directory:
   ```bash
   rm -rf $spec_path
   ```

3. Clear current spec marker:
   ```bash
   rm -f ./specs/.current-spec
   ```

4. Clean up epic state (if spec belongs to the active epic):
   ```bash
   # Read active epic from .current-epic
   EPIC_NAME=$(cat "$CWD/specs/.current-epic" 2>/dev/null || true)
   SPEC_NAME="${spec_path##*/}"
   if [ -n "$EPIC_NAME" ] && [ -f "$CWD/specs/_epics/$EPIC_NAME/.epic-state.json" ]; then
       EPIC_STATE="$CWD/specs/_epics/$EPIC_NAME/.epic-state.json"
       # Check if this spec exists in the epic's specs array
       if jq -e --arg name "$SPEC_NAME" '.specs[] | select(.name == $name)' "$EPIC_STATE" >/dev/null 2>&1; then
           # Remove the spec entry from the epic's specs array (atomic via same-dir mktemp + mv)
           TMP=$(mktemp "$(dirname "$EPIC_STATE")/.epic-state.XXXXXX")
           jq --arg name "$SPEC_NAME" 'del(.specs[] | select(.name == $name))' "$EPIC_STATE" > "$TMP"
           mv "$TMP" "$EPIC_STATE"
       else
           rm -f "$TMP"
       fi
   fi
   ```

5. Update Spec Index (removes deleted spec from index):
   ```bash
   ./plugins/ralphharness/hooks/scripts/update-spec-index.sh --quiet
   ```

## Output

```
Canceled execution for spec: $spec_name

Location: $spec_path
State before cancellation:
- Phase: <phase>
- Progress: <taskIndex>/<totalTasks> tasks
- Iterations: <globalIteration>

Cleanup:
- [x] Removed .ralph-state.json
- [x] Removed spec directory ($spec_path)
- [x] Cleared current spec marker
- [x] Cleaned up epic state (removed spec from epic registry)

The spec and all its files have been permanently removed.

To start a new spec:
- Run /ralphharness:new <name>
- Or /ralphharness:start <name> <goal>
```

## If No Active Loop

If there's no `.ralph-state.json`, still proceed with removing the spec directory and clearing `.current-spec`:

```
No active execution loop found for spec: $spec_name

Location: $spec_path
Cleanup:
- [x] Removed spec directory ($spec_path)
- [x] Cleared current spec marker

The spec has been removed.

To start a new spec:
- Run /ralphharness:new <name>
- Or /ralphharness:start <name> <goal>
```
