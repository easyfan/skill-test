---
name: skill-test
description: Full testing pipeline coordinator for skills, agents, and patterns. Orchestrates the three-phase quality pipeline: static review (skill-review/pattern-review) → behavioral eval (skill-creator eval loop) → deployment verification (looper). Use this skill whenever someone asks to test, validate, or run the full quality pipeline for a skill, agent, or pattern file — including when they say "run the test pipeline", "validate this skill end-to-end", "测试这个 skill", "跑流水线", or asks which testing stages are needed. Also triggers when someone asks about resuming a pipeline with --from-stage or handling looper failure.
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

```
If --pattern <name> is present    → TARGET_TYPE=pattern, TARGET_NAME=<name>
If --from-stage N is present      → FROM_STAGE=N (default: 1)
Otherwise                         → TARGET_TYPE=skill, TARGET_PATH=<target>
```

**Step 0b: Resolve tool paths (priority: project-level > user-level > demo)**

Locate the following tool command files:

```bash
# skill-review
SKILL_REVIEW_CMD="$(ls ~/.claude/commands/skill-review.md 2>/dev/null || \
                    ls /workspace/demo/commands/skill-review.md 2>/dev/null)"

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

If skill-review is not available, halt and prompt the user to install it.

**Step 0c: Initialize state directory**

```bash
PROJECT_ROOT=$(pwd)
SCRATCH_DIR="$PROJECT_ROOT/.claude/agent_scratch/skill_test_pipeline"
mkdir -p "$SCRATCH_DIR"
STATE_FILE="$SCRATCH_DIR/pipeline_state.json"
```

If `$STATE_FILE` already exists and `--from-stage` was not specified, read the previous progress and ask the user whether to resume.

Print pipeline banner:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🧪 Skill Test Pipeline
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Target: <TARGET>
Type:   <skill/agent | pattern>
Start:  stage <FROM_STAGE>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

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
```

---

## Reference Documents

For complete stage steps, read the applicable document based on TARGET_TYPE:

- **Skill/Agent path** → `references/skill-pipeline.md`
- **Pattern path** → `references/pattern-pipeline.md`
- **Tool invocation details** → `references/tools.md`
