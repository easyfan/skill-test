# Skill/Agent Testing Pipeline (5+1 stages)

Applies to: command files, agent files, plugin skill files

---

## Stage Overview

```
Draft
  │
  ▼
Stage 0.5: Packer Doc Lint                         ← pure Bash, <1s, non-blocking
           only for packer/<pkg>/ targets; bare command/agent files skip this stage
           FAIL does not stop pipeline; flagged ⚠️ in final summary
  │
  ▼
Stage 1: Triage gate (skill-review --quick)        ← ~5K tokens, coordinator inline
          any 🔴 → fix and retry; no 🔴 → proceed to stage 2
  │
  ▼
Stage 2: Full static review (skill-review, with researcher)  ← run-loop ≤3 rounds
          surface structural defects, iterative fixes
          [researcher runs in round 1 only; subsequent rounds use --regression]
  │
  ▼
Stage 3: Behavioral eval main loop (skill-creator eval)  ← ≤5 rounds
          with_skill vs baseline, converge by pass rate
  │
  ▼
Stage 4: Regression static re-check (skill-review --regression)  ← 1 round, zero-findings auto-exit
          catch design regressions introduced during eval iteration
  │
  ▼
Stage 5: Looper deployment verification            ← terminal, 1 run, failure rolls back to stage 3
```

---

## Stage 0.5: Packer Doc Lint

**Goal**: Mechanically verify packer package documentation and structure completeness before entering the expensive committee review. Covers documentation blind spots not checked by either skill-review or looper.

**Applies when**: target is under a `packer/<pkg>/` directory. Bare command/agent files skip this stage.

**Operation**:

```bash
bash packer/skill-test/scripts/lint-docs.sh <PKG_DIR>
```

**Checks**:

| ID | Check | Tool |
|----|-------|------|
| L1-1 | install.sh exists | `[ -f ]` |
| L1-2 | install.sh supports `CLAUDE_DIR` convention | `grep -q` |
| L1-3 | install.sh supports `--target` flag | `grep -q` |
| L2-1 | plugin.json has required fields (name/description/install) | `grep -q` |
| L2-2 | all files in commands/ are declared in plugin.json | loop + `grep -q` |
| L2-3 | all files in agents/ are declared in plugin.json | loop + `grep -q` |
| L3-1 | README has Install section | `grep -qi` |
| L3-2 | README contains `/plugin marketplace add` (step 1) | `grep -q` |
| L3-3 | README contains `/plugin install X@X` (step 2, @ required) | `grep -qE` |
| L3-4 | README contains `bash install.sh` option | `grep -q` |
| L3-5 | README contains `CLAUDE_DIR` example | `grep -q` |
| L4-1 | plugin.json name matches `/plugin install` plugin-id in README | `sed` + `grep -q` |
| L4-2 | SKILL.md has `name:` / `description:` fields | `grep -q` |
| L4-3 | package.json version is valid semver (if present) | `grep -qE` |

**Result**:
- PASS: zero FAIL items (warnings do not count) → proceed to stage 1
- FAIL: ≥1 FAIL items → **does not block pipeline**, continue to stage 1, flag ⚠️ in final summary

**Write state**:
```json
"0.5": {"status": "completed", "result": "pass|warn|fail", "fail_count": <N>, "warn_count": <M>}
```

---

## Stage 1: Triage Gate

**Goal**: Filter obviously blocking issues at minimum cost (~5K tokens) before spending on a full committee review.

**Operation**:

Locate the skill-review command file path (`SKILL_REVIEW_CMD`), invoke in `--quick` mode on the target file:

```
Follow the instructions in $SKILL_REVIEW_CMD, reviewing <TARGET_PATH> in --quick mode
```

**Result**:
- Output contains `🟢 Triage passed` → record stage 1 complete (result: pass), proceed to stage 2
- Output contains `🔴` → record specific issues, prompt user to fix and re-trigger (do not auto-proceed to stage 2):
  ```
  ⛔ Triage found <K> blocking issue(s), pipeline paused.
  Fix the 🔴 items above then re-run /skill-test (or /skill-test --from-stage 1).
  ```

**Write state**:
```json
"1": {"status": "completed", "result": "pass|blocked", "triage_issues": <K>}
```

---

## Stage 2: Full Static Review (run-loop)

**Goal**: Use the full committee (4 reviewers + Challenger + Reporter) to surface structural design defects. The researcher runs external benchmarking in round 1 only; subsequent rounds skip it.

**Operation (each round)**:

```
Follow the instructions in $SKILL_REVIEW_CMD, reviewing <TARGET_PATH> in full mode (no flags),
complete all stages non-interactively (Stage 1 → Challenger → Reporter),
do not present inter-stage confirmation gates to the user.
```

Round 1: full mode (with researcher). Round ≥2: use `--regression` to skip researcher and Challenger.

> **Note**: skill-review's protocol includes a Stage 1 confirmation gate for direct interactive use. When called by skill-test as a coordinator, run the full flow non-interactively and summarize at the end; do not surface intermediate gates to the user.

**Loop control**:

```
ROUND=1, MAX_ROUNDS=3
while ROUND ≤ MAX_ROUNDS:
  run review
  read Stage 1 finding count (CURRENT_COUNT)
  if CURRENT_COUNT == 0              → exit loop (converged)
  if CURRENT_COUNT == previous count → prompt user to decide whether to continue (may have hit ceiling)
  if ROUND == MAX_ROUNDS             → notify max rounds reached, proceed to next stage
  wait for user fix confirmation → ROUND++
```

**Write state**:
```json
"2": {"status": "completed", "result": "pass", "rounds": <N>, "final_finding_count": <K>}
```

---

## Stage 3: Behavioral Eval Main Loop

**Goal**: Verify that the skill behaves as designed under real user prompts.

**Scope**: Only applies to skills triggered implicitly via `description`. Skills that are explicitly invoked commands skip this stage and proceed directly to stage 4.

**Pre-conditions check**:
1. Check triggering mode: read the `description` field of the target file; if it contains "explicit invocation only" or equivalent → skip stage 3, mark as "skipped (explicit invocation)"
2. Verify evals.json exists and is valid
3. Verify SKILL.md exists with front-matter
4. If any check fails → **BLOCKER**, halt pipeline immediately, provide repair guidance

**Operation**:

Follow the skill-creator workflow:
1. Confirm evals.json exists (if absent, guide user to design 2-3 eval cases based on skill function)
2. Launch with_skill + without_skill (or old_skill) as parallel subagent runs
3. Wait for completion, grade, aggregate, generate eval viewer (`generate_review.py --static`)
4. Wait for user review feedback

**Loop control**:

```
EVAL_ROUND=1, MAX_EVAL_ROUNDS=5
while EVAL_ROUND ≤ MAX_EVAL_ROUNDS:
  run eval
  if eval execution fails (tool error, format error, etc.) → BLOCKER, halt pipeline
  review results
  if pass rate meets target (or user satisfied) → exit loop
  if pass rate plateaus for 2 rounds → suggest possible improvement ceiling; review eval quality
  if EVAL_ROUND == MAX_EVAL_ROUNDS   → notify max rounds reached
  improve skill → EVAL_ROUND++
```

eval workspace path: `<PROJECT_ROOT>/<skill-name>-workspace/` (sibling to skill directory)

**Write state**:
```json
"3": {"status": "completed", "eval_rounds": <N>, "final_pass_rate": 0.92}
```

---

## Stage 4: Regression Static Re-check

**Goal**: Catch design regressions introduced during eval iteration (the eval loop may restructure the skill).

**Operation**:

```
Follow the instructions in $SKILL_REVIEW_CMD, reviewing <TARGET_PATH> in --regression mode
```

**Result**:
- `[Regression check complete] zero new findings` → record complete (result: pass), proceed to stage 5
- Findings present → show to user, wait for fix confirmation (no loop here; fix and proceed directly to stage 5)

**Write state**:
```json
"4": {"status": "completed", "result": "pass|issues_found", "finding_count": <K>}
```

---

## Stage 5: Looper Deployment Verification

**Goal**: Verify skill trigger accuracy and installation completeness in a clean CC environment. For packer packages, all **container-testable** installation methods must be covered. This is a terminal verifier — no iteration.

**Installation method testability**:

| Method | Testable | Reason |
|--------|----------|--------|
| `/plugin marketplace add` + `/plugin install` | ❌ | Requires live CC + network registry |
| `npx <pkg>` | ❌ | Requires npm + package published to registry |
| `bash install.sh` / `CLAUDE_DIR=...` | ✅ | Local script, executable in container |
| Manual `cp` | ✅ | Pure file operation, executable in container |

**Operation**:

If looper is not available (`~/.claude/skills/looper/SKILL.md` not found), output a notice and skip:
```
⚠️ looper not installed, skipping deployment verification.
To run full verification, install looper then run: /skill-test --from-stage 5 <target>
```

If looper is available, two paths based on target type:

**Path A: bare command/agent file (not a packer package)**

```
Follow the instructions in the looper skill, verifying <TARGET_PATH> in a clean CC environment
```
Equivalent to manual `cp` then verify — single test only.

**Path B: packer package (PKG_DIR has been detected)**

Run two independent looper rounds in sequence, each with a fresh clean CC directory:

**B-1: install.sh method** (corresponds to docs Option B/C)
```
Follow the instructions in the looper skill, testing --plugin <PKG_NAME>
```
Internal: `CLAUDE_DIR=<clean_dir> bash install.sh` — verifies the install script path.

**B-2: manual cp method** (corresponds to docs Option C/D)
```
Follow the instructions in the looper skill, testing the skill file directly from packer/<PKG_NAME>/skills/<SKILL_NAME>/
```
Internal: direct `cp` from packer source — verifies the manual install path.

Both rounds must pass T1–T5. Any failure makes the overall result FAIL. T5 runs only when `evals/evals.json` is present; no evals.json → marked ⏭️ skipped, does not count as FAIL.

**Non-testable methods**: plugin marketplace and npx are explicitly noted "requires live environment, not tested" in the summary; they do not contribute to FAIL.

**Failure handling**: do not re-run looper; roll back to stage 3.

```
⚠️ looper verification failed
Failure analysis:
  • Trigger rate 0% (T3)         → description optimization may not have converged; re-run run_loop.py
  • Installation incomplete (T2) → check SKILL.md dependency declarations
  • Clean CC integration break   → eval stage may not cover integration scenarios; add eval cases
  • Eval suite failure (T5)      → clean-env behavior differs from host; check whether description
                                   depends on other installed skills or host env vars; add eval cases

Recommended: /skill-test --from-stage <eval-stage> <target>
```

**Write state**:
```json
"5": {
  "status": "completed",
  "result": "pass|fail|skipped",
  "install_methods_tested": ["install.sh", "manual-cp"],
  "install_methods_skipped": ["plugin-marketplace (live env)", "npx (live env)"],
  "eval_suite": {"result": "pass|fail|skip", "pass_rate": "N/M"},
  "looper_reports": {
    "install_sh": "<report_path>",
    "manual_cp": "<report_path>"
  }
}
```

---

## Final Output

After all stages complete:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Skill Test Pipeline Complete
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Target: <TARGET>

Stage summary:
  Stage 0.5 Doc Lint:    ✅ Pass | ⚠️ <N> issue(s) (non-blocking, fix before publish) | ⏭️ Skipped (non-packer)
  Stage 1 Triage:        ✅ Pass
  Stage 2 Static review: ✅ Pass (<N> rounds, <K> findings fixed)
  Stage 3 Behavioral eval: ✅ Pass (<N> rounds, pass rate <X>%)
  Stage 4 Regression:    ✅ Pass (zero findings)
  Stage 5 Looper:        ✅ Pass
    Installation coverage:
      ✅ install.sh (bash install.sh / CLAUDE_DIR=...)
      ✅ manual cp
      ⏭️ plugin marketplace (requires live env, not tested)
      ⏭️ npx (requires live env, not tested)
    eval suite (T5): ✅ <N>/<M> passed  |  ⏭️ skipped (no evals.json)

Quality verdict: <grade>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
