---
name: skill-test
description: "Full testing pipeline coordinator for skills, agents, and patterns. Orchestrates the three-phase quality pipeline: static review (skill-review/pattern-review) → behavioral eval (skill-creator eval loop) → deployment verification (looper). Use this skill whenever someone asks to test, validate, or run the full quality pipeline for a skill, agent, or pattern file — including when they say \"run the test pipeline\", \"validate this skill end-to-end\", \"测试这个 skill\", \"跑流水线\", or asks which testing stages are needed. Also triggers when someone asks about resuming a pipeline with --from-stage or handling looper failure. Do NOT trigger for single-stage review requests (use skill-review directly) or deployment-only checks (use looper directly)."
---

# Skill Test — Testing Pipeline Coordinator

## Responsibility

Connects three orthogonal testing tools (static review → behavioral eval → deployment verification) into a complete pipeline. Automatically selects the right path based on target type (skill/agent vs pattern), maintains stage progress state, and supports resuming from a checkpoint.

Design principles:
1. **Cheap first, expensive later; structure before behavior before integration**
2. **Stop immediately on a blocker, fix it and retry — never skip a failed stage**
3. Each stage has a clear exit condition to avoid iterating on the wrong layer

**Stage count**: Skill/Agent path — 5+1 stages (including Stage 0.5 doc lint); Pattern path — 7+1 stages.

## Usage

```
/skill-test [--from-stage N] <target>
/skill-test [--from-stage N] --pattern <name>
```

- `<target>`: absolute path to a skill/agent/command file (e.g. `~/.claude/commands/my-skill.md`)
- `--pattern <name>`: pattern name without path or .md suffix (e.g. `agent-monitoring`)
- `--from-stage N`: start from stage N, skipping already-completed stages (for resuming)

**Examples**:
```bash
/skill-test ~/.claude/commands/patterns.md              # skill full pipeline
/skill-test --pattern agent-monitoring                  # pattern full pipeline
/skill-test --from-stage 3 ~/.claude/commands/my.md    # resume from eval stage
```

---

## Step 0: Initialization and Type Detection

**Step 0a: Parse arguments**

If no arguments are provided, output usage reminder and halt:
```
Usage: /skill-test [--from-stage N] <target>
       /skill-test [--from-stage N] --pattern <name>
       /skill-test --dry-run [--from-stage N] <target>
```

```
If --dry-run is present           → DRY_RUN=true (resolve tools, validate target, print stage plan, then exit without executing stages)
If --pattern <name> is present    → TARGET_TYPE=pattern, TARGET_NAME=<name>
If --from-stage N is present      → FROM_STAGE=N (default: 1)
Otherwise                         → TARGET_TYPE=skill, TARGET_PATH=<target>
```

If TARGET_PATH is set (skill/agent path), check subtype:
```
If TARGET_PATH is under agents/   → TARGET_SUBTYPE=agent
Otherwise                         → TARGET_SUBTYPE=skill
```

After parsing, validate FROM_STAGE if set:
- Skill/Agent path valid stages: {0.5, 1, 2, 3, 4, 5}
- Pattern path valid stages: {0.5, 1, 2, 3, 4, 5, 6, 7}
- If FROM_STAGE is not in the valid set → halt: "Error: --from-stage N is out of range. Valid values: {list}"
- Note: --from-stage 1 begins at Stage 1 (Stage 0.5 doc lint is skipped)

**Step 0b: Resolve tool paths (priority: project-level > user-level > demo)**

Locate the following tool command files:

```bash
# skill-review
SKILL_REVIEW_CMD="$(ls ~/.claude/commands/skill-review.md 2>/dev/null || \
                    ls /workspace/demo/commands/skill-review.md 2>/dev/null)"

# skill-creator (optional; used in Stage 3 behavioral eval)
SKILL_CREATOR_CMD="$(ls ~/.claude/skills/skill-creator/SKILL.md 2>/dev/null)"

# pattern-review (pattern path only)
PATTERN_REVIEW_CMD="$(ls ~/.claude/commands/pattern-review.md 2>/dev/null || \
                      ls /workspace/demo/commands/pattern-review.md 2>/dev/null)"

# Detect if target is from packer/<pkg>/ (for Stage 0.5 doc lint)
PKG_DIR=""
if echo "$TARGET_PATH" | grep -q "/packer/[^/]*/"; then
  PKG_DIR=$(echo "$TARGET_PATH" | sed 's|.*/packer/\([^/]*\)/.*|packer/\1|')
fi
LINT_SCRIPT="$(pwd)/packer/skill-test/scripts/lint-docs.sh"
```

If skill-review is not available, halt:
```
⛔ skill-review is required but not installed.
Install via: /plugin marketplace add skill-review → then retry
```

If TARGET_TYPE=skill and TARGET_PATH is set, verify file existence:
```
If TARGET_PATH does not exist → halt: "Error: target file not found: <TARGET_PATH>"
```

If SKILL_CREATOR_CMD is not found, note the skip path:
```
⚠️ skill-creator not installed — Stage 3 behavioral eval will be flagged as 'skipped (skill-creator not installed)' and pipeline will proceed to Stage 4.
```

If TARGET_TYPE=pattern and PATTERN_REVIEW_CMD is not found, halt:
```
⛔ pattern-review is required for pattern path but is not installed.
Install via: /plugin marketplace add pattern-review → then retry
```

**Step 0c: Initialize state directory**

```bash
PROJECT_ROOT=$(pwd)
SCRATCH_DIR="$PROJECT_ROOT/.claude/agent_scratch/skill_test_pipeline"
mkdir -p "$SCRATCH_DIR"
STATE_FILE="$SCRATCH_DIR/pipeline_state.json"
```

If `$STATE_FILE` already exists and `--from-stage` was not specified, read the previous progress and present resume prompt:

```
📂 Found existing pipeline state for: <previous_target>
   Last stage completed: <N> | Status: <status>
   Started at: <started_at>

   [WARNING] Target mismatch detected — state is for <previous_target>, current target is <current_target>.
   (omit the warning line if targets match)

Resume from stage <N+1>? (yes = resume / no = start fresh from stage 1)
```

If yes → set FROM_STAGE=<N+1>, use existing state. If no → delete state and start from stage 1.

If `--from-stage N` is used and no state file exists for this target, emit:
```
⚠️ No prior state file found for this target. Stages 1 through <N-1> will be assumed complete.
```

If `--from-stage N` is set and the state file records a prior stage as "blocked", warn before proceeding:
```
⚠️ Stage <M> previously recorded as 'blocked'. Proceeding from stage <N> may skip unresolved issues.
Proceed anyway? (yes/no)
```

Print pipeline banner:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🧪 Skill Test Pipeline
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Target:  <TARGET>
Type:    <skill | agent | pattern>
Subtype: <skill | agent>  (skill/agent path only)
Start:   stage <FROM_STAGE>
DryRun:  <yes | no>
Estimated cost: ~$1-3 (skill/agent path) | ~$3-8 (pattern path)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

If DRY_RUN=true, after printing the banner and resolving tool paths, print stage plan (tools involved per stage) and exit without executing any stages.

---

## Path Selection

Based on `TARGET_TYPE`, load the corresponding pipeline reference document:

- **Skill / Agent**: read `references/skill-pipeline.md` — execute 5+1 stage pipeline (including Stage 0.5 doc lint)
- **Pattern**: read `references/pattern-pipeline.md` — execute 7+1 stage pipeline (including Stage 0.5 doc lint)

The reference documents contain the complete step-by-step instructions for each stage. Read whichever is applicable and follow it exactly.

---

## State Persistence Format

After each stage completes, update `$STATE_FILE`:

```json
{
  "schema_version": "1",
  "target": "<path or name>",
  "target_type": "skill|pattern",
  "started_at": "<ISO datetime>",
  "current_stage": 3,
  "stages": {
    "1": {"status": "completed", "result": "pass", "completed_at": "..."},
    "2": {"status": "completed", "result": "pass", "finding_count": 2, "rounds": 2},
    "3": {"status": "in_progress"}
  }
}
```

Note: Write state atomically (write to a `.tmp` file then rename) to avoid partial-write corruption. The `schema_version` field enables forward compatibility.

---

## Shared Stage Rules

These rules apply to both skill and pattern paths:

**Loop boundaries** (prevent infinite iteration):

| Loop type | Max rounds | Exit condition |
|-----------|-----------|----------------|
| Static review run-loop (full mode) | ≤3 rounds | Finding count reaches zero or plateaus |
| Static review (regression `--regression`) | 1 round | Zero findings → auto-exit |
| skill-creator eval loop | ≤5 rounds | Pass rate ≥ target or plateau |
| looper | 1 run (no loop) | Failure rolls back to eval stage |

**looper failure handling** (applies to both paths):

looper is a terminal verifier, not an iteration tool. If looper reports failure (low trigger rate, incomplete installation, integration break in clean CC environment), **do not re-run looper**. Reason: a looper failure means the upstream filtering missed a root cause; roll back to the eval stage and iterate there.

Suggested output:
```
⚠️ looper verification failed
Failure analysis:
  • Trigger rate 0% (T3)      → description optimization may not have converged; re-run run_loop.py
  • Installation incomplete (T2) → check SKILL.md dependency declarations
  • Clean CC integration break  → eval stage may not cover integration scenarios; add eval cases

Recommended: /skill-test --from-stage <eval-stage> <target>
  (skill/agent path: <eval-stage>=3; pattern path: <eval-stage>=5)
```

---

## Reference Documents

For complete stage steps, read the applicable document based on TARGET_TYPE:

- **Skill/Agent path** → `references/skill-pipeline.md`
- **Pattern path** → `references/pattern-pipeline.md`
- **Tool invocation details** → `references/tools.md`
