[English](README.md) | [Chinese](README-zh.md) | [German](README-de.md) | [French](README-fr.md) | [Russian](README-ru.md)

# skill-test

Full testing pipeline coordinator for Claude Code skills, agents, and patterns. Connects three orthogonal testing tools into a single automated quality pipeline: static review → behavioral eval → deployment verification.

## What It Does

`/skill-test` orchestrates a quality pipeline that runs in stages, stopping immediately on blockers and resuming from checkpoints:

**Skill / Agent path — 5+1 stages:**

| Stage | Tool | Description |
|-------|------|-------------|
| 0.5 | lint-docs.sh | Packer package doc lint (non-blocking) |
| 1 | skill-review --quick | Triage gate — filter blockers fast |
| 2 | skill-review (full) | Full static review, ≤3 rounds with researcher |
| 3 | skill-creator eval | Behavioral eval loop, ≤5 rounds |
| 4 | skill-review --regression | Regression re-check after eval changes |
| 5 | looper | Deployment verification in clean CC environment |

**Pattern path — 7+1 stages** (adds settle-down and bridge verification between static review and eval).

## Installation

### Option A: Plugin Marketplace (Recommended)

In Claude Code:
```
/plugin marketplace add https://github.com/easyfan/skill-test
/plugin install skill-test@latest
```

> Partially covered by automated tests: underlying `claude plugin install` CLI verified by looper T2b (Plan B); `/plugin` REPL entry point must be verified manually.

### Option B: bash install.sh

```bash
git clone https://github.com/easyfan/skill-test.git
cd skill-test
bash install.sh
```

With custom install directory:
```bash
bash install.sh --target=~/.claude
# or
CLAUDE_DIR=~/.claude bash install.sh
```

### Option C: Manual Copy

```bash
git clone https://github.com/easyfan/skill-test.git
cp -r skill-test/skills/skill-test ~/.claude/skills/
```

After installation, restart your Claude Code session. The skill is available as `/skill-test`.

## Prerequisites

`/skill-test` coordinates other tools — they must be installed for their respective pipeline stages to run:

| Stage | Required Tool | Install |
|-------|--------------|---------|
| 1, 2, 4 | skill-review | `/plugin install skill-review@latest` |
| 3, 4 (pattern) | pattern-review | `/plugin install pattern-review@latest` |
| 3 | skill-creator eval | From skill-creator plugin |
| 3 (pattern) | patterns | `/plugin install patterns@latest` |
| 5 | looper | `/plugin install looper@latest` |

If a required tool is not installed, `skill-test` skips that stage and issues a warning.

## Usage

```
/skill-test [--from-stage N] <target>
/skill-test [--from-stage N] --pattern <name>
```

- `<target>`: absolute path to a skill, agent, or command file
- `--pattern <name>`: pattern name without path or `.md` suffix
- `--from-stage N`: resume from stage N (skipping completed stages)

**Examples:**
```bash
/skill-test ~/.claude/commands/patterns.md          # full skill pipeline
/skill-test --pattern agent-monitoring              # full pattern pipeline
/skill-test --from-stage 3 ~/.claude/commands/my.md # resume from eval stage
```

## Installed Files

```
~/.claude/skills/skill-test/
├── SKILL.md                 # main coordinator skill
└── references/
    ├── skill-pipeline.md    # 5+1 stage details for skills/agents
    ├── pattern-pipeline.md  # 7+1 stage details for patterns
    └── tools.md             # tool invocation reference
```

## Eval Suite

The plugin includes 4 trigger-accuracy test cases in `evals/evals.json`:

1. **Skill pipeline plan** — identifies 5-stage path for a skill file
2. **Pattern pipeline plan** — identifies 7-stage path with settle-down and bridge verification
3. **Resume from stage 3** — correctly skips stages 1-2 and plans from eval onward
4. **Looper failure handling** — recommends rollback to eval, not re-running looper

## Package Structure

```
packer/skill-test/
├── .claude-plugin/
│   ├── plugin.json
│   └── marketplace.json
├── skills/skill-test/
│   └── SKILL.md
├── references/
│   ├── skill-pipeline.md
│   ├── pattern-pipeline.md
│   └── tools.md
├── scripts/
│   ├── install.sh
│   └── lint-docs.sh
├── evals/
│   └── evals.json
├── install.sh           # entry point (delegates to scripts/install.sh)
└── package.json
```
