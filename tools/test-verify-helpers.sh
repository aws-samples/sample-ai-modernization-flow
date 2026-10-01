#!/bin/bash
# =============================================================================
# test-verify-helpers.sh — scenario tests for the record extractors in
#                          harness/verify.sh.template (ja and en)
# =============================================================================
#
# Why this exists. The gates count rows in the project's own records (adaptation
# ledger, decisions.md). If an extractor silently drops rows, the gate reports
# "PASS" while having inspected nothing — the worst failure mode a gate has.
# Downstream projects hit this class of bug five times in one migration, each
# time in a different hand-rolled extractor, and each time it was found only by
# accident. The extractors are now two shared functions; these are their tests.
#
# The tests must hold for BOTH language trees: the templates are under the
# `code-identical` i18n flag, so a divergence here is also an i18n failure.
#
# Usage:  tools/test-verify-helpers.sh [-q]
# Exit:   0 = PASS, 1 = FAIL
# =============================================================================
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
QUIET=0
[ "${1:-}" = "-q" ] && QUIET=1

FAIL=0
CASES=0
note() { [ "$QUIET" -eq 1 ] || echo "$@"; }
err()  { echo "❌ $*"; FAIL=1; }

# Pull one function definition out of a template so it can be evaluated here.
# The template ends with a `case` block that would run a gate if sourced, so the
# functions are extracted by name instead. Every one of them closes with a lone
# `}` in column 1.
extract_fn() {  # $1=template path, $2=function name
  awk -v fn="$2" '
    $0 == fn "() {" { inFn = 1 }
    inFn { print }
    inFn && $0 == "}" { exit }
  ' "$1"
}

# $1=description, $2=expected, $3=actual
expect_eq() {
  CASES=$((CASES+1))
  if [ "$2" = "$3" ]; then
    note "  ✅ $1"
  else
    err "$1"
    note "       expected: [$2]"
    note "       actual:   [$3]"
  fi
}

# --- fixtures ----------------------------------------------------------------
# Every fixture carries the traps that actually broke a real project's gates.
make_ledger() {  # $1=path
  cat > "$1" <<'FIXTURE'
# Adaptation ledger fixture

<!-- A leading comment block that mentions AP-1 and spans
     several lines, holding an example row:
| AP-900 | MP-9 | 1 | x.cs:1 | 未対応 | |
-->

| ID | 観点（MP-N） | 検出件数 | 根拠（path:line） | 処理区分 | 対応 SC / 理由 |
|----|------------|---------|-----------------|---------|--------------|
| AP-1 | MP-1 | 4 | a.cs:10 | 対応済 | SC-1 |
| AP-2 | MP-2 | 0 | b.cs:20 | 対応不要 | 既存バグ。<!-- POPULATION-DEFINED は関係ない --> |
| AP-3 | MP-3 | 2 | c.cs:30 | 代替実装 | d.cs へ移設 |
| AP-4 |  | 1 | e.cs:40 | 未対応 | |

<!-- POPULATION-DEFINED: perspectives=4 (silent=3 misleading=1) excluded=0 -->
FIXTURE
}

make_decisions() {  # $1=path
  cat > "$1" <<'FIXTURE'
# Decisions fixture

## 独立検証の記録

<!-- INDEPENDENT-VERIFICATION -->
<!-- Explanatory comment holding an example row that must NOT count:
| 移行完了宣言 | 2020-01-01 | 1 | 別エージェント | UPHELD / UPHELD | 観点4件 | なし | 0件 |
-->

| 宣言 | 実施日 | 回数 | 手段 | レンズ別判定 | 検証範囲 | 差し戻し | 繰り越し |
|------|--------|------|------|------------|---------|---------|---------|
| 移行完了宣言 / 機能除外(ADR-N) | | | | | | | |
| 移行完了宣言 | 2026-09-15 | 1 | 別エージェント | REFUTED / UPHELD | 観点4件 | AP-5 | 1件 (AP-5) |

## 否定テストの記録

<!-- NEGATIVE-TEST -->
<!-- Explanatory comment holding an example row that must NOT count:
| MP-900 | 2020-01-01 | pattern を削って再実行 | EXIT=0 / 4件→0件 |
-->

| 観点 ID | 実施日 | どう壊したか | 何が出たか |
|---------|--------|------------|-----------|
| MP-N | | | |
| MP-1 | 2026-09-15 | 走査パターンの末尾を削った | EXIT=0 / 4件→0件 |
| MP-2 | 2026-09-15 | 除外条件を反転した <!-- 補足 --> | EXIT=0 / 2件→0件 |
| MP-3 | 2026-09-15 | 置換先の実在判定を外した | EXIT=0 / 2件→0件 |
FIXTURE
}

make_analysis_runs() {  # $1=path
  cat > "$1" <<'FIXTURE'
# Analysis runs fixture

## 分析実行の記録

<!-- A comment between the heading and the table. -->

| repo-id | 分析種別 | source | 終了コード |
|---------|---------|--------|-----------|
| repo-a | CCA | executed | 0 |
<!-- A comment INSIDE the table must not end it. -->
| repo-b | CCA | imported | 0 |
| <repo-id> | CCA | executed | 0 |

## 別の節

| repo-id | 状態 |
|---------|------|
| repo-c | 未実行 |
FIXTURE
}

# --- the tests ---------------------------------------------------------------
run_suite() {  # $1=label, $2=template path
  local label="$1" tpl="$2" tmp fn
  note ""
  note "--- $label ---"

  tmp="$(mktemp -d)"
  ADAPTATION_LEDGER="$tmp/adaptation-ledger.md"
  DECISIONS_FILE="$tmp/decisions.md"
  ANALYSIS_RUNS="$tmp/analysis-runs.md"
  make_ledger "$ADAPTATION_LEDGER"
  make_decisions "$DECISIONS_FILE"
  make_analysis_runs "$ANALYSIS_RUNS"

  for fn in strip_comments marker_rows ledger_rows independent_verification_rows \
            ledger_detector_ids negative_test_ids section_rows; do
    local src
    src="$(extract_fn "$tpl" "$fn")"
    if [ -z "$src" ]; then
      err "$label: cannot extract $fn() from the template"
      rm -rf "$tmp"
      return 0
    fi
    eval "$src"
  done

  # 1. A data row that contains an inline comment keeps its prose and is counted.
  #    The old `/<!--/ { inc=1 } inc { ...; next }` form dropped the whole row,
  #    which silently lowered every count the gate derives from the ledger.
  expect_eq "$label: inline comment in a data row does not drop the row" \
    "既存バグ。" \
    "$(ledger_rows | awk -F'|' '$2 ~ /AP-2/ { gsub(/^[ \t]+|[ \t]+$/,"",$7); print $7 }')"

  # 2. Row count: 4 real rows; the example row inside the leading comment block
  #    must not be counted (pothole 7 — templates must not satisfy their gate).
  expect_eq "$label: ledger_rows counts only real rows" \
    "4" "$(ledger_rows | wc -l | tr -d ' ')"
  expect_eq "$label: ledger_rows ignores example rows inside comments" \
    "0" "$(ledger_rows | grep -c 'AP-900' || true)"

  # 3. Dispositions still resolve per row (the columns are not shifted by the
  #    comment removal).
  expect_eq "$label: unaddressed rows are still identified" \
    "1" \
    "$(ledger_rows | awk -F'|' '{ d=$6; gsub(/^[ \t]+|[ \t]+$/,"",d); if (d ~ /(未対応|unaddressed)/) c++ } END { print c+0 }')"
  #    AP-2 is `対応不要`, which is bound by its mandatory reason instead, so it
  #    must NOT appear here.
  expect_eq "$label: addressed and replaced rows require negative tests" \
    "MP-1 MP-3" "$(ledger_detector_ids | tr '\n' ' ' | sed 's/ $//')"

  # 4. Independent-verification records: only dated rows count. The template's
  #    own placeholder row has no date, the example row is inside a comment, and
  #    the dated rows of the NEXT section must not leak in.
  expect_eq "$label: independent verification counts dated rows only" \
    "1" "$(independent_verification_rows | wc -l | tr -d ' ')"
  expect_eq "$label: independent verification ignores commented examples" \
    "0" "$(independent_verification_rows | grep -c '2020-01-01' || true)"

  # 5. Negative-test records: same rules, plus an inline comment inside a row.
  expect_eq "$label: negative test ids are read from dated rows" \
    "MP-1 MP-2 MP-3" "$(negative_test_ids | tr '\n' ' ' | sed 's/ $//')"
  expect_eq "$label: negative test ids ignore commented examples" \
    "0" "$(negative_test_ids | grep -c 'MP-900' || true)"

  # 6. The gate still FAILS when a record is missing — a test that only proves
  #    "it passes now" would let a gate that lost its discrimination through.
  perl -pi -e 's/^\| MP-3 \| 2026-09-15.*\n$//' "$DECISIONS_FILE"
  expect_eq "$label: a missing negative-test record is still detected" \
    "MP-1 MP-2" "$(negative_test_ids | tr '\n' ' ' | sed 's/ $//')"
  perl -pi -e 's/^\| 移行完了宣言 \| 2026-09-15.*\n$//' "$DECISIONS_FILE"
  expect_eq "$label: a missing independent-verification record is still detected" \
    "0" "$(independent_verification_rows | wc -l | tr -d ' ')"

  # 7. Heading-scoped extraction: a comment inside the table must not end it,
  #    and template example rows (containing `<`) are still discarded.
  expect_eq "$label: section_rows spans a comment inside the table" \
    "2" "$(section_rows "$ANALYSIS_RUNS" '分析実行の記録|Analysis runs' | wc -l | tr -d ' ')"
  expect_eq "$label: section_rows stops at the next heading" \
    "0" "$(section_rows "$ANALYSIS_RUNS" '分析実行の記録|Analysis runs' | grep -c 'repo-c' || true)"

  rm -rf "$tmp"
}

run_suite "ja" "$REPO/ja/harness/verify.sh.template"
run_suite "en" "$REPO/en/harness/verify.sh.template"

echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "✅ PASS — $CASES cases (ja + en)"
  exit 0
fi
echo "FAIL — see the messages above"
exit 1
