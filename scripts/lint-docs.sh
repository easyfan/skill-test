#!/usr/bin/env bash
# packer/skill-test/scripts/lint-docs.sh
#
# Packer package doc lint — validates documentation and structure of packer/<pkg>/
# Bash + grep + sed; L6 language check requires python3 (available on all modern macOS/Linux)
#
# Usage:
#   bash packer/skill-test/scripts/lint-docs.sh <pkg_dir>
#   bash packer/skill-test/scripts/lint-docs.sh packer/skill-review
#
# Exit code:
#   0 — all pass (or warnings only)
#   1 — one or more FAIL items

set -euo pipefail

PKG_DIR="${1:-}"
if [ -z "$PKG_DIR" ] || [ ! -d "$PKG_DIR" ]; then
  echo "Usage: $0 <pkg_dir>" >&2
  exit 1
fi

PKG_NAME=$(basename "$PKG_DIR")
PLUGIN_JSON="$PKG_DIR/.claude-plugin/plugin.json"
README="$PKG_DIR/README.md"
INSTALL_SH="$PKG_DIR/install.sh"
# SKILL.md may live under skills/<pkg_name>/SKILL.md (plugin layout) or at package root
if [ -f "$PKG_DIR/skills/$PKG_NAME/SKILL.md" ]; then
  SKILL_MD="$PKG_DIR/skills/$PKG_NAME/SKILL.md"
else
  SKILL_MD="$PKG_DIR/SKILL.md"
fi
PKG_JSON="$PKG_DIR/package.json"

FAIL=0
WARN=0

# Detect non-plugin distribution packages (developer infrastructure tools that
# do not go through /plugin marketplace)
PLUGIN_DIST=true
if [ -f "$PKG_JSON" ]; then
  grep -q '"pluginDistribution":[[:space:]]*false' "$PKG_JSON" && PLUGIN_DIST=false || true
fi

pass() { echo "  ✅ $1"; }
fail() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }
warn() { echo "  ⚠️  $1"; WARN=$((WARN + 1)); }

echo "[Packer Doc Lint] $PKG_NAME"
echo ""

# ── L1: install.sh ────────────────────────────────────────────────────────────
echo "L1 install.sh"
if [ ! -f "$INSTALL_SH" ]; then
  fail "install.sh not found"
else
  pass "install.sh exists"
  grep -q "CLAUDE_DIR" "$INSTALL_SH" \
    && pass "CLAUDE_DIR convention supported" \
    || fail "CLAUDE_DIR support missing (required for packer/looper calls)"
  grep -q "\-\-target" "$INSTALL_SH" \
    && pass "--target flag supported" \
    || warn "--target flag not declared (recommended)"
fi

echo ""

# ── L2: plugin.json ───────────────────────────────────────────────────────────
echo "L2 plugin.json"
if [ "$PLUGIN_DIST" = "false" ]; then
  pass "pluginDistribution=false — non-plugin package, skipping L2"
elif [ ! -f "$PLUGIN_JSON" ]; then
  fail ".claude-plugin/plugin.json not found"
else
  pass "plugin.json exists"
  # Field-level and path-format validation delegated to validate-plugin-manifest skill
  grep -q '"version"' "$PLUGIN_JSON" \
    && pass "plugin.json has version field (required for version-based cache path)" \
    || fail "plugin.json missing version field — CC falls back to SHA-based cache path, triggers ENAMETOOLONG on install"
  grep -q '"homepage"' "$PLUGIN_JSON" \
    && pass "plugin.json has homepage field" \
    || warn "plugin.json missing homepage field (recommended)"
fi

echo ""

# ── L3: README ────────────────────────────────────────────────────────────────
echo "L3 README"
if [ ! -f "$README" ]; then
  fail "README.md not found"
else
  pass "README.md exists"

  grep -qiE "^## .*install" "$README" \
    && pass "Install section present" \
    || fail "Install section missing"

  if [ "$PLUGIN_DIST" = "false" ]; then
    pass "pluginDistribution=false — skipping plugin marketplace entry checks"
  else
    grep -q "plugin marketplace add" "$README" \
      && pass "contains /plugin marketplace add" \
      || fail "missing /plugin marketplace add (plugin install step 1)"

    grep -qE "/plugin install .+@.+" "$README" \
      && pass "contains /plugin install X@X (@ sign present)" \
      || fail "missing /plugin install X@X (plugin install step 2 — must include @ sign)"
  fi

  grep -q "install\.sh" "$README" \
    && pass "contains bash install.sh option" \
    || fail "missing bash install.sh install option"

  grep -q "CLAUDE_DIR" "$README" \
    && pass "contains CLAUDE_DIR example" \
    || warn "CLAUDE_DIR example not shown in README (recommended)"
fi

echo ""

# ── L4: cross-file consistency ────────────────────────────────────────────────
echo "L4 consistency"

# plugin-id extraction (pure sed); skip for non-plugin packages
if [ "$PLUGIN_DIST" = "false" ]; then
  pass "pluginDistribution=false — skipping plugin-id consistency check"
elif [ -f "$PLUGIN_JSON" ]; then
  PLUGIN_ID=$(grep '"name"' "$PLUGIN_JSON" \
    | head -1 \
    | sed 's/.*"name":[[:space:]]*"\([^"]*\)".*/\1/')

  if [ -n "$PLUGIN_ID" ]; then
    pass "plugin.json name extracted: $PLUGIN_ID"
    # The @ prefix/suffix in /plugin install must match PLUGIN_ID
    grep -q "plugin install ${PLUGIN_ID}@" "$README" 2>/dev/null \
      && pass "/plugin install ${PLUGIN_ID}@... matches plugin.json name" \
      || fail "README /plugin install plugin-id does not match plugin.json name (${PLUGIN_ID})"
  else
    fail "could not extract name field from plugin.json"
  fi
fi

# SKILL.md required fields
if [ ! -f "$SKILL_MD" ]; then
  warn "SKILL.md not found"
else
  grep -q "^name:" "$SKILL_MD" \
    && pass "SKILL.md has name: field" \
    || fail "SKILL.md missing name: field"
  grep -q "^description:" "$SKILL_MD" \
    && pass "SKILL.md has description: field" \
    || fail "SKILL.md missing description: field"
fi

# package.json version format
if [ -f "$PKG_JSON" ]; then
  grep -qE '"version":[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+' "$PKG_JSON" \
    && pass "package.json version is valid semver" \
    || fail "package.json version is not valid semver (expected x.y.z)"
fi

echo ""

# ── L5: evals documentation ───────────────────────────────────────────────────
echo "L5 evals"
EVALS_JSON="$PKG_DIR/evals/evals.json"
if [ ! -f "$EVALS_JSON" ]; then
  warn "evals/evals.json not found (recommended: add trigger-accuracy test cases)"
else
  pass "evals/evals.json exists"

  EVAL_COUNT=$(grep -c '"id"' "$EVALS_JSON" 2>/dev/null || echo 0)
  pass "contains ${EVAL_COUNT} test case(s)"

  if [ -f "$README" ]; then
    grep -qiE "(evals|eval loop)" "$README" \
      && pass "README describes evals" \
      || fail "README missing evals documentation (evals/evals.json exists but not described)"

    grep -q "cat evals/evals.json" "$README" \
      && fail "README uses 'cat evals/evals.json' (no-op — replace with real documentation)" \
      || pass "README does not use 'cat evals/evals.json' no-op"

    README_COUNT=$(grep -oE "[0-9]+" "$README" \
      | awk -v n="$EVAL_COUNT" '$1==n{found=1} END{if(found) print n}' 2>/dev/null || true)
    if [ -n "$README_COUNT" ]; then
      pass "README mentions eval count matching evals.json (${EVAL_COUNT})"
    else
      warn "README does not mention eval count matching evals.json (${EVAL_COUNT})"
    fi
  fi
fi

echo ""

# ── L6: language purity ───────────────────────────────────────────────────────
# Rules:
#   - Human-facing files (README.md): English-only; README-zh.md is the bilingual partner
#   - Machine-facing non-semantic files (SKILL.md, install.sh, install.ps1,
#     package.json, plugin.json): English-only
#   - Semantic execution files (commands/*.md, agents/*.md, skills/*/SKILL.md):
#     excluded (translation risk — semantic drift could break Claude behavior)
echo "L6 language"

HAS_PYTHON3=false
command -v python3 &>/dev/null && HAS_PYTHON3=true

if [ "$HAS_PYTHON3" = "false" ]; then
  warn "python3 not found — L6 language check skipped"
else
  LANG_CHECK_FILES=()
  [ -f "$README" ]              && LANG_CHECK_FILES+=("$README")
  # SKILL.md excluded — semantic execution file (same as commands/*.md, agents/*.md)
  [ -f "$INSTALL_SH" ]          && LANG_CHECK_FILES+=("$INSTALL_SH")
  [ -f "$PKG_DIR/install.ps1" ] && LANG_CHECK_FILES+=("$PKG_DIR/install.ps1")
  [ -f "$PKG_JSON" ]            && LANG_CHECK_FILES+=("$PKG_JSON")
  [ -f "$PLUGIN_JSON" ]         && LANG_CHECK_FILES+=("$PLUGIN_JSON")

  for f in "${LANG_CHECK_FILES[@]}"; do
    fname=$(basename "$f")
    hit_count=$(python3 -c "
import re
pattern = re.compile(u'[\u4e00-\u9fff\u3000-\u303f]')
count = sum(1 for line in open('$f') if pattern.search(line))
print(count)
" 2>/dev/null || echo 0)
    if [ "$hit_count" -eq 0 ]; then
      pass "$fname — American English only"
    else
      fail "$fname — contains Chinese characters (${hit_count} line(s)); translate to American English or move to *-zh.md"
    fi
  done

  # README-zh.md should exist alongside README.md
  if [ -f "$README" ]; then
    README_ZH="$PKG_DIR/README-zh.md"
    [ -f "$README_ZH" ] \
      && pass "README-zh.md exists (bilingual pair)" \
      || warn "README-zh.md missing — consider adding a Simplified Chinese version"
  fi
fi

echo ""

# ── summary ───────────────────────────────────────────────────────────────────
if [ "$FAIL" -eq 0 ] && [ "$WARN" -eq 0 ]; then
  echo "Result: ✅ PASS — $PKG_NAME docs complete"
elif [ "$FAIL" -eq 0 ]; then
  echo "Result: ✅ PASS ($WARN warning(s)) — $PKG_NAME is publishable; fix warnings when possible"
else
  echo "Result: ❌ FAIL — $PKG_NAME has $FAIL issue(s) to fix ($WARN warning(s))"
fi

exit $FAIL
