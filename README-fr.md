[English](README.md) | [中文](README-zh.md) | [Deutsch](README-de.md) | [Français](README-fr.md) | [Русский](README-ru.md)

# skill-test

Coordinateur de pipeline de test complet pour les skills, agents et patterns Claude Code. Connecte trois outils de test indépendants en un pipeline de qualité automatisé : revue statique → évaluation comportementale → vérification du déploiement.

## Fonctionnement

`/skill-test` orchestre un pipeline de qualité qui s'exécute par étapes, s'arrête immédiatement sur les blocages et reprend depuis les points de contrôle :

**Chemin Skill / Agent — 5+1 étapes :**

| Étape | Outil | Description |
|-------|-------|-------------|
| 0.5 | lint-docs.sh | Vérification de la documentation du package Packer (non bloquante) |
| 1 | skill-review --quick | Porte de triage — filtrage rapide des blocages |
| 2 | skill-review (complet) | Revue statique complète, ≤3 tours avec researcher |
| 3 | skill-creator eval | Boucle d'évaluation comportementale, ≤5 tours |
| 4 | skill-review --regression | Revérification de régression après les changements d'eval |
| 5 | looper | Vérification du déploiement dans un environnement CC propre |

**Chemin Pattern — 7+1 étapes** (ajout du settle-down et de la vérification par pont entre la revue statique et l'eval).

## Installation

### Option A : Plugin Marketplace (Recommandé)

Dans Claude Code :
```
/plugin marketplace add easyfan/skill-test
/plugin install skill-test@skill-test
```

> Couverture des tests automatisés : looper T2b (Plan B) vérifie le chemin CLI `claude plugin install` sous-jacent ; le point d'entrée REPL `/plugin` doit être vérifié manuellement.

### Option B : bash install.sh

```bash
git clone https://github.com/easyfan/skill-test.git
cd skill-test
bash install.sh
```

Avec un répertoire d'installation personnalisé :
```bash
bash install.sh --target=~/.claude
# ou
CLAUDE_DIR=~/.claude bash install.sh
```

### Option C : Copie manuelle

```bash
git clone https://github.com/easyfan/skill-test.git
cp -r skill-test/skills/skill-test ~/.claude/skills/
```

Après l'installation, redémarrez votre session Claude Code. Le skill est disponible via `/skill-test`.

## Prérequis

`/skill-test` coordonne d'autres outils — ceux-ci doivent être installés pour que les étapes correspondantes du pipeline fonctionnent :

| Étape | Outil requis | Installation |
|-------|-------------|--------------|
| 1, 2, 4 | skill-review | `/plugin install skill-review@skill-review` |
| 3, 4 (pattern) | pattern-review | `/plugin install pattern-review@pattern-review` |
| 3 | skill-creator eval | Depuis le plugin skill-creator |
| 3 (pattern) | patterns | `/plugin install patterns@patterns` |
| 5 | looper | `/plugin install looper@looper` |

Si un outil requis n'est pas installé, `skill-test` ignore cette étape et émet un avertissement.

## Utilisation

```
/skill-test [--from-stage N] <cible>
/skill-test [--from-stage N] --pattern <nom>
```

- `<cible>` : chemin absolu vers un fichier skill, agent ou command
- `--pattern <nom>` : nom du pattern sans chemin ni suffixe `.md`
- `--from-stage N` : reprendre depuis l'étape N (en ignorant les étapes terminées)

**Exemples :**
```bash
/skill-test ~/.claude/commands/patterns.md          # pipeline skill complet
/skill-test --pattern agent-monitoring              # pipeline pattern complet
/skill-test --from-stage 3 ~/.claude/commands/my.md # reprendre depuis l'étape eval
```

## Fichiers installés

```
~/.claude/skills/skill-test/
├── SKILL.md                 # skill coordinateur principal
└── references/
    ├── skill-pipeline.md    # détails des 5+1 étapes pour skills/agents
    ├── pattern-pipeline.md  # détails des 7+1 étapes pour patterns
    └── tools.md             # référence d'invocation des outils
```

## Suite d'évaluation

Le plugin inclut 4 cas de test de précision de déclenchement dans `evals/evals.json` :

1. **Planification du pipeline skill** — identifie le chemin à 5 étapes pour un fichier skill
2. **Planification du pipeline pattern** — identifie le chemin à 7 étapes avec settle-down et vérification par pont
3. **Reprise depuis l'étape 3** — ignore correctement les étapes 1–2 et planifie depuis eval
4. **Gestion des échecs looper** — recommande le retour à eval, pas de relancement de looper
