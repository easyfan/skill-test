# Tool Invocation Details

How to invoke each tool in the skill-test pipeline.

---

## Tool Path Resolution (priority)

| Tool | Project-level path | Fallback |
|------|-------------------|---------|
| skill-review | `~/.claude/commands/skill-review.md` | `/workspace/demo/commands/skill-review.md` |
| pattern-review | `~/.claude/commands/pattern-review.md` | `/workspace/demo/commands/pattern-review.md` |
| patterns | `~/.claude/commands/patterns.md` | — |
| looper | `~/.claude/skills/looper/SKILL.md` | — |

If the project-level path does not exist, use the fallback; if the fallback also does not exist, skip the stage and issue a warning.

---

## skill-review Invocation

skill-review is a command (markdown file), not a subagent. Invocation:

```
Read $SKILL_REVIEW_CMD, follow its instructions to review <TARGET_PATH>.

Flag meanings:
  no flag         → full mode (with researcher, 4 reviewers + Challenger + Reporter)
  --quick         → Triage mode (coordinator inline, no child agents)
  --regression    → regression mode (S1+S4 only, skip S2/S3 and Challenger)

Example prompts to pass to subtasks:
  "Follow the instructions in [skill-review file path], review [target file path] in --quick mode"
  "Follow the instructions in [skill-review file path], review [target file path] in full mode"
  "Follow the instructions in [skill-review file path], review [target file path] in --regression mode"
```

**Note**: skill-review internally launches multiple parallel subagents (Stage 1 reviewers) and uses Challenger (opus), requiring a generous tool budget. When wrapping in a Task tool, ensure sufficient context is passed.

---

## pattern-review Invocation

Same as skill-review, but the target is a pattern name rather than a file path:

```
"Follow the instructions in [pattern-review file path], review pattern [PATTERN_NAME] in [mode] mode"

Modes:
  --quick         → Triage
  no flag         → full mode (with P4 researcher)
  --regression    → regression mode (P1+P2 only)
```

---

## patterns (settle-down) Invocation

```
"Follow the instructions in ~/.claude/commands/patterns.md (patterns skill), instantiate pattern [PATTERN_NAME] in the current project"

Output verification:
  grep -r "generated-from: [PATTERN_NAME]" .claude/
```

---

## skill-creator eval Invocation

skill-creator eval is executed via the skill-creator plugin or a manual workflow. Core steps:

1. Confirm evals.json exists in the target skill directory
2. Launch two parallel subagent groups (with_skill + without_skill/old_skill)
3. Wait for completion, run grader, aggregate benchmark
4. Generate eval viewer (`generate_review.py --static`)
5. Wait for user review

For plugin skill targets (located under plugins/), the skill path format passed to subagents:
```
Skill path: <absolute_path>/<skill-name>/
```

**Concrete invocation template** (follow the skill-creator instructions to run eval):

```
Follow the instructions in $SKILL_CREATOR_CMD to run eval for skill at <TARGET_PATH>.

Steps:
1. Read evals/evals.json at the skill directory — require ≥3 test cases
2. Spawn with_skill and without_skill (or old_skill) as parallel subagent runs
3. Wait for all runs to complete
4. Grade results: count pass/fail per case, compute pass rate
5. Run: python3 generate_review.py --static   (if available)
6. Present graded results to user and wait for feedback
7. If pass rate < target: suggest targeted improvements, then EVAL_ROUND++
```

If SKILL_CREATOR_CMD is not found:
```
Print: ⏭️ Stage 3 skipped — skill-creator not installed.
       Install via: /plugin marketplace add skill-creator → then retry
```

---

## looper Invocation

```
"Follow the instructions in the looper skill, verify [TARGET_PATH] behavior in a clean CC environment"
```

looper typically checks:
- description trigger accuracy (multiple independent session tests)
- installation completeness (install then run in a clean directory)
- integration break (does it still work after CC configuration reset)

---

## State File Read/Write

```bash
# Write stage state (atomic: write to .tmp then rename to avoid partial-write corruption)
python3 -c "
import json, os
f = os.environ.get('STATE_FILE')
state = json.load(open(f)) if os.path.exists(f) else {}
state.setdefault('stages', {})['<N>'] = {'status': 'completed', 'result': 'pass'}
state['current_stage'] = <N>
tmp = f + '.tmp'
json.dump(state, open(tmp, 'w'), ensure_ascii=False, indent=2)
os.replace(tmp, f)
"

# Read stage state
python3 -c "
import json, os
f = os.environ.get('STATE_FILE')
if os.path.exists(f):
    s = json.load(open(f))
    print(s.get('stages', {}).get('<N>', {}).get('status', 'not_started'))
"
```
