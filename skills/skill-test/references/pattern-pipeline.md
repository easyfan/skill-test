# Pattern Testing Pipeline (7+1 stages)

Applies to: `~/.claude/patterns/*.md` pattern template files

Patterns add a "dual-track static" layer over skills: first review **template** quality, then instantiate and review the **instantiated output** quality.

---

## Stage Overview

```
Draft
  │
  ▼
Stage 0.5: Packer Doc Lint                         ← pure Bash, <1s, non-blocking
           only for packer/<pkg>/ targets; bare pattern files skip this stage
           FAIL does not stop pipeline; flagged ⚠️ in final summary
  │
  ▼
Stage 1: Triage gate (pattern-review --quick)      ← ~5K tokens, inline
          any 🔴 → fix and retry
  │
  ▼
Stage 2: Full template static review (pattern-review)  ← run-loop ≤3 rounds
          review the template itself: Kickoff completeness, section structure, instantiation conventions
          [researcher in round 1 only; subsequent rounds use --regression]
  │
  ▼
Stage 3: Project-level settle-down (/patterns <name>)  ← 1 run, in target project
          instantiate pattern → produce command/agent files
  │
  ▼
Stage 4: Instance static bridge verification (skill-review --regression)  ← 1 round
          verify template landing quality; defects found roll back to pattern layer
  │
  ▼
Stage 5: Behavioral eval main loop (skill-creator eval)  ← ≤5 rounds
          test behavior of instantiated output
  │
  ▼
Stage 6: Regression static re-check (skill-review --regression)  ← 1 round, zero-findings auto-exit
  │
  ▼
Stage 7: Looper deployment verification            ← terminal, 1 run, failure rolls back to stage 5
```

---

## Stage 0.5: Packer Doc Lint

**Goal**: Verify packer package documentation and structure completeness. Covers blind spots not checked by pattern-review or looper.

**Applies when**: target is under `packer/<pkg>/` directory. Bare pattern files (`~/.claude/patterns/`) skip this stage.

**Operation**:

```bash
bash packer/skill-test/scripts/lint-docs.sh <PKG_DIR>
```

Checks are identical to skill-pipeline.md Stage 0.5 (L1–L6).

**Result**: FAIL does not block pipeline; continue to stage 1, flag ⚠️ in final summary.

**Write state**:
```json
"0.5": {"status": "completed", "result": "pass|warn|fail", "fail_count": <N>, "warn_count": <M>}
```

---

## Stage 1: Triage Gate

**Goal**: Quickly filter structural issues in the pattern template (missing required sections, unfilled placeholders, file too short).

**Operation**:

```
Follow the instructions in $PATTERN_REVIEW_CMD, reviewing pattern <PATTERN_NAME> in --quick mode
```

Triage checks pattern-specific items:
- Required sections present (Applicable scenarios, Invocation format/Kickoff)
- Contains `generated-from` or "instantiation conventions" declaration
- File line count ≥20 (not an empty shell)
- No unfilled placeholders

**Result** (same as skill path — 🔴 pauses pipeline).

**Write state**:
```json
"1": {"status": "completed", "result": "pass|blocked"}
```

---

## Stage 2: Full Template Static Review (run-loop)

**Goal**: Use the pattern committee to review template design quality (completeness, instantiability, internal consistency, external benchmarking).

**Operation**:

```
Follow the instructions in $PATTERN_REVIEW_CMD, reviewing pattern <PATTERN_NAME> in full mode
```

Round 1: full mode (with P4 researcher). Subsequent rounds: `--regression` (P1+P2, skip P3/P4).

**Loop control** (same as skill path — ≤3 rounds, exit when finding count reaches zero).

**Critical finding rollback**: if P2 (instantiability) has 🔴, it must be fixed before stage 3. Missing `generated-from` is a typical P2 blocker.

**Write state**:
```json
"2": {"status": "completed", "rounds": <N>, "final_finding_count": <K>}
```

---

## Stage 3: Project-Level Settle-Down

**Goal**: Instantiate the pattern in the target project, producing real command/agent files. This step verifies that "the template can be executed."

**Operation**:

```
In the target project directory, follow the instructions in ~/.claude/commands/patterns.md (or the patterns skill), executing:
/patterns <PATTERN_NAME>
```

Output file path is typically: `<PROJECT>/.claude/commands/<PATTERN_NAME>.md` (or under agents/)

**Checks**:
1. Output file exists
2. File contains `generated-from: <PATTERN_NAME>` front-matter field
3. File is not an empty shell (line count > 20)

If `generated-from` is missing, the pattern file does not self-document its instantiation convention → roll back to stage 2 to fix the pattern, then re-run settle-down.

**Write state**:
```json
"3": {"status": "completed", "instance_path": "<path>", "generated_from_present": true}
```

---

## Stage 4: Instance Static Bridge Verification

**Goal**: Verify "landing quality" of the template — does the instantiated output meet skill review standards? Defects found must be **rolled back to the pattern layer** rather than only fixed in the instance file.

**Operation**:

```
Follow the instructions in $SKILL_REVIEW_CMD, reviewing <INSTANCE_PATH> in --regression mode
```

**Rollback logic**:
- 🔴 found → analyze root cause (pattern template issue vs settle-down output issue) → roll back to stage 2 to fix template, then re-run settle-down (stage 3)
- Zero findings → proceed to stage 5

**Write state**:
```json
"4": {"status": "completed", "result": "pass|backtrack", "backtrack_to_stage": 2}
```

---

## Stage 5: Behavioral Eval Main Loop

**Goal**: Test the behavior of the instantiated output under real user prompts. Identical to stage 3 in skill-pipeline.md.

The eval test subject is the **instance file** (`<INSTANCE_PATH>`), not the pattern template file.

Operations and loop control are the same as skill-pipeline.md stage 3.

**Write state**:
```json
"5": {"status": "completed", "eval_rounds": <N>, "final_pass_rate": 0.92}
```

---

## Stage 6: Regression Static Re-check

Same as skill-pipeline.md stage 4. The review subject is the instance file `<INSTANCE_PATH>`.

**Write state**:
```json
"6": {"status": "completed", "result": "pass|issues_found"}
```

---

## Stage 7: Looper Deployment Verification

Same as the complete logic in skill-pipeline.md stage 5, including:
- Path A (bare pattern file): single `--command` run
- Path B (packer package): `--plugin` (install.sh) + `--command` (manual cp) dual run
- plugin marketplace / npx noted as "requires live environment, not tested"

Failure handling: roll back to stage 5 (eval stage), do not re-run looper.

**Write state**:
```json
"7": {
  "status": "completed",
  "result": "pass|fail|skipped",
  "install_methods_tested": ["install.sh", "manual-cp"],
  "install_methods_skipped": ["plugin-marketplace (live env)", "npx (live env)"]
}
```

---

## Final Output

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Skill Test Pipeline Complete (Pattern path)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Pattern:       <PATTERN_NAME>
Instance file: <INSTANCE_PATH>

Stage summary:
  Stage 0.5 Doc Lint:           ✅ Pass | ⚠️ <N> issue(s) (non-blocking) | ⏭️ Skipped (non-packer)
  Stage 1 Triage:               ✅ Pass
  Stage 2 Template static:      ✅ Pass (<N> rounds)
  Stage 3 Settle-down:          ✅ Pass (generated-from present)
  Stage 4 Bridge verification:  ✅ Pass (zero findings)
  Stage 5 Behavioral eval:      ✅ Pass (<N> rounds, pass rate <X>%)
  Stage 6 Regression:           ✅ Pass
  Stage 7 Looper:               ✅ Pass
    Installation coverage:
      ✅ install.sh (bash install.sh / CLAUDE_DIR=...)
      ✅ manual cp
      ⏭️ plugin marketplace (requires live env, not tested)
      ⏭️ npx (requires live env, not tested)

Quality verdict: <grade>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
