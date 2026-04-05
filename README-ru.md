[English](README.md) | [中文](README-zh.md) | [Deutsch](README-de.md) | [Français](README-fr.md) | [Русский](README-ru.md)

# skill-test

Координатор полного тестового конвейера для Skills, Agents и Patterns Claude Code. Объединяет три независимых инструмента тестирования в автоматизированный конвейер качества: статический анализ → поведенческая оценка → верификация развёртывания.

## Описание

`/skill-test` организует конвейер качества, выполняемый поэтапно. При обнаружении блокирующей проблемы останавливается немедленно; продолжение возможно с контрольной точки.

**Путь Skill / Agent — 5+1 этапов:**

| Этап | Инструмент | Описание |
|------|-----------|----------|
| 0.5 | lint-docs.sh | Проверка документации packer-пакета (неблокирующая) |
| 1 | skill-review --quick | Ворота сортировки — быстрая фильтрация блокеров |
| 2 | skill-review (полный) | Полный статический анализ, ≤3 раунда с исследователем |
| 3 | skill-creator eval | Цикл поведенческой оценки, ≤5 раундов |
| 4 | skill-review --regression | Регрессионная проверка после изменений в eval |
| 5 | looper | Верификация развёртывания в чистой среде CC |

**Путь Pattern — 7+1 этапов** (дополнительно: settle-down и мостовая верификация между статическим анализом и eval).

## Установка

### Вариант A: Plugin Marketplace (Рекомендуется)

В Claude Code:
```
/plugin marketplace add easyfan/skill-test
/plugin install skill-test@skill-test
```

> Покрытие автоматизированными тестами: looper T2b (Plan B) верифицирует путь CLI `claude plugin install`; точка входа REPL `/plugin` требует ручной проверки.

### Вариант B: bash install.sh

```bash
git clone https://github.com/easyfan/skill-test.git
cd skill-test
bash install.sh
```

С указанием пользовательского каталога установки:
```bash
bash install.sh --target=~/.claude
# или
CLAUDE_DIR=~/.claude bash install.sh
```

### Вариант C: Ручное копирование

```bash
git clone https://github.com/easyfan/skill-test.git
cp -r skill-test/skills/skill-test ~/.claude/skills/
```

После установки перезапустите сессию Claude Code. Skill доступен через `/skill-test`.

## Предварительные требования

`/skill-test` координирует другие инструменты — они должны быть установлены для работы соответствующих этапов:

| Этап | Требуемый инструмент | Установка |
|------|--------------------|-----------| 
| 1, 2, 4 | skill-review | `/plugin install skill-review@skill-review` |
| 3, 4 (pattern) | pattern-review | `/plugin install pattern-review@pattern-review` |
| 3 | skill-creator eval | Из плагина skill-creator |
| 3 (pattern) | patterns | `/plugin install patterns@patterns` |
| 5 | looper | `/plugin install looper@looper` |

Если требуемый инструмент не установлен, `skill-test` пропускает соответствующий этап и выдаёт предупреждение.

## Использование

```
/skill-test [--from-stage N] <цель>
/skill-test [--from-stage N] --pattern <имя>
```

- `<цель>`: абсолютный путь к файлу skill, agent или command
- `--pattern <имя>`: имя паттерна без пути и суффикса `.md`
- `--from-stage N`: продолжить с этапа N (пропустив завершённые)

**Примеры:**
```bash
/skill-test ~/.claude/commands/patterns.md          # полный конвейер skill
/skill-test --pattern agent-monitoring              # полный конвейер pattern
/skill-test --from-stage 3 ~/.claude/commands/my.md # продолжить с этапа eval
```

## Установленные файлы

```
~/.claude/skills/skill-test/
├── SKILL.md                 # основной координирующий skill
└── references/
    ├── skill-pipeline.md    # детали 5+1 этапов для skills/agents
    ├── pattern-pipeline.md  # детали 7+1 этапов для patterns
    └── tools.md             # справочник по вызову инструментов
```

## Набор тестов (Eval Suite)

Плагин включает 4 тест-кейса точности срабатывания в `evals/evals.json`:

1. **Планирование конвейера skill** — определяет 5-этапный путь для файла skill
2. **Планирование конвейера pattern** — определяет 7-этапный путь с settle-down и мостовой верификацией
3. **Возобновление с этапа 3** — корректно пропускает этапы 1–2 и планирует с eval
4. **Обработка сбоя looper** — рекомендует откат к eval, не повторный запуск looper
