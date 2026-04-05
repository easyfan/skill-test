[English](README.md) | [中文](README-zh.md) | [Deutsch](README-de.md) | [Français](README-fr.md) | [Русский](README-ru.md)

# skill-test

Vollständiger Test-Pipeline-Koordinator für Claude Code Skills, Agents und Patterns. Verbindet drei unabhängige Test-Werkzeuge zu einer automatisierten Qualitäts-Pipeline: statische Überprüfung → Verhaltenstests → Deployment-Verifikation.

## Funktionsübersicht

`/skill-test` orchestriert eine Qualitäts-Pipeline, die stufenweise abläuft, bei Blockern sofort stoppt und von Checkpoints fortgesetzt werden kann:

**Skill / Agent Pfad — 5+1 Stufen:**

| Stufe | Werkzeug | Beschreibung |
|-------|----------|--------------|
| 0.5 | lint-docs.sh | Packer-Paket-Dokumentationsprüfung (nicht blockierend) |
| 1 | skill-review --quick | Triage-Gate — schnelle Filterung von Blockern |
| 2 | skill-review (vollständig) | Vollständige statische Überprüfung, ≤3 Runden mit Researcher |
| 3 | skill-creator eval | Verhaltenstest-Schleife, ≤5 Runden |
| 4 | skill-review --regression | Regressionsprüfung nach Eval-Änderungen |
| 5 | looper | Deployment-Verifikation in sauberer CC-Umgebung |

**Pattern-Pfad — 7+1 Stufen** (zusätzlich Settle-down und Bridge-Verifikation zwischen statischer Überprüfung und Eval).

## Installation

### Option A: Plugin Marketplace (Empfohlen)

In Claude Code:
```
/plugin marketplace add https://github.com/easyfan/skill-test
/plugin install skill-test@latest
```

> Automatisierte Testabdeckung: looper T2b (Plan B) verifiziert den zugrunde liegenden `claude plugin install` CLI-Pfad; der `/plugin` REPL-Einstiegspunkt muss manuell verifiziert werden.

### Option B: bash install.sh

```bash
git clone https://github.com/easyfan/skill-test.git
cd skill-test
bash install.sh
```

Mit benutzerdefiniertem Installationsverzeichnis:
```bash
bash install.sh --target=~/.claude
# oder
CLAUDE_DIR=~/.claude bash install.sh
```

### Option C: Manuelles Kopieren

```bash
git clone https://github.com/easyfan/skill-test.git
cp -r skill-test/skills/skill-test ~/.claude/skills/
```

Nach der Installation Claude Code neu starten. Der Skill ist als `/skill-test` verfügbar.

## Voraussetzungen

`/skill-test` koordiniert andere Werkzeuge — diese müssen für die jeweiligen Pipeline-Stufen installiert sein:

| Stufe | Erforderliches Werkzeug | Installation |
|-------|------------------------|--------------|
| 1, 2, 4 | skill-review | `/plugin install skill-review@latest` |
| 3, 4 (Pattern) | pattern-review | `/plugin install pattern-review@latest` |
| 3 | skill-creator eval | Aus dem skill-creator-Plugin |
| 3 (Pattern) | patterns | `/plugin install patterns@latest` |
| 5 | looper | `/plugin install looper@latest` |

Wenn ein erforderliches Werkzeug nicht installiert ist, überspringt `skill-test` die entsprechende Stufe und gibt eine Warnung aus.

## Verwendung

```
/skill-test [--from-stage N] <Ziel>
/skill-test [--from-stage N] --pattern <Name>
```

- `<Ziel>`: Absoluter Pfad zu einer Skill-, Agent- oder Command-Datei
- `--pattern <Name>`: Pattern-Name ohne Pfad und `.md`-Suffix
- `--from-stage N`: Ab Stufe N fortsetzen (abgeschlossene Stufen überspringen)

**Beispiele:**
```bash
/skill-test ~/.claude/commands/patterns.md          # vollständige Skill-Pipeline
/skill-test --pattern agent-monitoring              # vollständige Pattern-Pipeline
/skill-test --from-stage 3 ~/.claude/commands/my.md # ab Eval-Stufe fortsetzen
```

## Installierte Dateien

```
~/.claude/skills/skill-test/
├── SKILL.md                 # Haupt-Koordinator-Skill
└── references/
    ├── skill-pipeline.md    # 5+1-Stufen-Details für Skills/Agents
    ├── pattern-pipeline.md  # 7+1-Stufen-Details für Patterns
    └── tools.md             # Werkzeugaufruf-Referenz
```

## Eval-Suite

Das Plugin enthält 4 Trigger-Genauigkeits-Testfälle in `evals/evals.json`:

1. **Skill-Pipeline-Planung** — erkennt den 5-Stufen-Pfad für eine Skill-Datei
2. **Pattern-Pipeline-Planung** — erkennt den 7-Stufen-Pfad mit Settle-down und Bridge-Verifikation
3. **Fortsetzen ab Stufe 3** — überspringt korrekt die Stufen 1–2 und plant ab Eval
4. **Looper-Fehlerbehandlung** — empfiehlt Rollback zu Eval, nicht erneutes Ausführen von Looper
