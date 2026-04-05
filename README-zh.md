[English](README.md) | [中文](README-zh.md) | [Deutsch](README-de.md) | [Français](README-fr.md) | [Русский](README-ru.md)

# skill-test

Claude Code skills、agents 和 patterns 的完整测试流水线协调器。将三个正交的测试工具串联成一条自动化质量流水线：静态审查 → 行为评估 → 部署验证。

## 功能说明

`/skill-test` 按阶段编排质量流水线，遇到阻断问题立即停止，支持从断点继续：

**Skill / Agent 路径 — 5+1 阶段：**

| 阶段 | 工具 | 说明 |
|------|------|------|
| 0.5 | lint-docs.sh | Packer 包文档检查（不阻断流水线） |
| 1 | skill-review --quick | Triage 门控 — 快速过滤阻断问题 |
| 2 | skill-review（完整） | 完整静态审查，≤3 轮，含研究员 |
| 3 | skill-creator eval | 行为测试循环，≤5 轮 |
| 4 | skill-review --regression | eval 改动后的回归复查 |
| 5 | looper | 在干净 CC 环境中验证部署 |

**Pattern 路径 — 7+1 阶段**（在静态审查和 eval 之间额外增加 settle-down 和桥接验证）。

## 安装

### 选项 A：Plugin Marketplace（推荐）

在 Claude Code 中执行：
```
/plugin marketplace add https://github.com/easyfan/skill-test
/plugin install skill-test@latest
```

> 自动化测试覆盖情况：looper T2b（Plan B）验证底层 `claude plugin install` CLI 路径；`/plugin` REPL 入口需手动验证。

### 选项 B：bash install.sh

```bash
git clone https://github.com/easyfan/skill-test.git
cd skill-test
bash install.sh
```

自定义安装目录：
```bash
bash install.sh --target=~/.claude
# 或
CLAUDE_DIR=~/.claude bash install.sh
```

### 选项 C：手动复制

```bash
git clone https://github.com/easyfan/skill-test.git
cp -r skill-test/skills/skill-test ~/.claude/skills/
```

安装完成后重启 Claude Code 会话，即可通过 `/skill-test` 使用。

## 前置依赖

`/skill-test` 依赖其他工具完成各阶段测试，需提前安装：

| 阶段 | 所需工具 | 安装方式 |
|------|---------|---------|
| 1, 2, 4 | skill-review | `/plugin install skill-review@latest` |
| 3, 4（pattern） | pattern-review | `/plugin install pattern-review@latest` |
| 3 | skill-creator eval | skill-creator 插件 |
| 3（pattern） | patterns | `/plugin install patterns@latest` |
| 5 | looper | `/plugin install looper@latest` |

如果某个工具未安装，`skill-test` 会跳过对应阶段并给出提示。

## 使用方式

```
/skill-test [--from-stage N] <目标路径>
/skill-test [--from-stage N] --pattern <名称>
```

- `<目标路径>`：skill、agent 或 command 文件的绝对路径
- `--pattern <名称>`：pattern 名称，不含路径和 `.md` 后缀
- `--from-stage N`：从第 N 阶段开始继续（跳过已完成阶段）

**示例：**
```bash
/skill-test ~/.claude/commands/patterns.md          # skill 完整流水线
/skill-test --pattern agent-monitoring              # pattern 完整流水线
/skill-test --from-stage 3 ~/.claude/commands/my.md # 从 eval 阶段继续
```

## 安装后文件

```
~/.claude/skills/skill-test/
├── SKILL.md                 # 主协调器 skill
└── references/
    ├── skill-pipeline.md    # skill/agent 5+1 阶段详情
    ├── pattern-pipeline.md  # pattern 7+1 阶段详情
    └── tools.md             # 工具调用参考
```

## Eval 套件

插件包含 4 个触发准确率测试用例（`evals/evals.json`）：

1. **Skill 流水线规划** — 正确识别 skill 文件的 5 阶段路径
2. **Pattern 流水线规划** — 正确识别含 settle-down 和桥接验证的 7 阶段路径
3. **从阶段 3 继续** — 正确跳过阶段 1-2，从 eval 开始规划
4. **looper 失败处理** — 建议回溯到 eval 阶段，而非重新运行 looper

## 包结构

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
├── install.sh           # 入口点（委托到 scripts/install.sh）
└── package.json
```
