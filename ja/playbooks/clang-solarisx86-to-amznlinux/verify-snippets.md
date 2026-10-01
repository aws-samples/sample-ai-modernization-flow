# verify スニペット — C / Solaris x86 → Amazon Linux

verify.sh の各ゲートを本ドメインで実装する際のスニペット集。
（verify.sh の骨格・使い方は harness の verify.sh.template を参照）

## build ゲート: 期待成果物の例

```bash
# C ネイティブプロダクトの典型的な成果物（共有ライブラリ + 実行バイナリ）
EXPECTED_ARTIFACTS=(
  "$MODERNIZED/lib/foo/libfoo.so.2.1"
  "$MODERNIZED/programs/bar/bar"
)
```

## smoke ゲート

```bash
# --- CLI: --help が rc=0 ---
smoke_cli() {
  "$MODERNIZED/path/to/cli" --help > /dev/null 2>&1 \
    && pass "cli --help" || fail "cli --help"
}

# --- デーモン: 2秒生存（timeout の rc=124 は「生存」= PASS）---
smoke_daemon() {
  timeout 2 "$MODERNIZED/path/to/daemon" <ARGS>; rc=$?
  if [ "$rc" -eq 124 ] || [ "$rc" -eq 0 ]; then
    pass "daemon alive (rc=$rc)"
  else
    fail "daemon died (rc=$rc; 139=SIGSEGV, 127=lib missing)"
  fi
}

# --- 共有ライブラリ: 未解決依存なし ---
smoke_libs() {
  local lib unresolved=0
  for lib in "${EXPECTED_ARTIFACTS[@]}"; do
    case "$lib" in *.so*)
      if ldd "$lib" | grep -q "not found"; then
        fail "$lib: unresolved deps"; ldd "$lib" | grep "not found"
        unresolved=1
      fi ;;
    esac
  done
  if [ "$unresolved" -eq 0 ]; then pass "all libs resolve"; fi
}
```

注意: smoke テストの前提条件（rpcbind 等の前提デーモン、LD_LIBRARY_PATH、DISPLAY/Xvfb）は
test-procedures.md の「前提条件」に明文化し、verify.sh 内でセットアップまたは検査する。

## integration ゲート

- ToolTalk/RPC 系: `rpcinfo -p | grep <prog-number>` で登録確認
- X11 系: `xprop -root`（または `-id <win>`）でプロパティ確認
- 各テストは 02-test/integration/*.sh に自己完結スクリプト化（rc=0 = PASS）

## 複数リポジトリ構成と診断マーカー走査

```bash
# 1プロダクトが複数リポジトリに分かれている場合（例: 共有ライブラリ群と実行系が別リポジトリ）
# は全て列挙する。repository-inventory.md の repo-id と対応させること。
MODERNIZED_TREES=(
  "../libs-modernized"
  "../programs-modernized"
)

# 診断コードマーカー（DIAG-）の走査対象。C なら実装ソースに絞ると速い
DIAG_SCAN_PATHS=(
  "lib"
  "programs"
)
```

期待成果物・integration テストはリポジトリ横断で1つのリストにまとめる
（ゲートは「システムとして動くか」を見るため、リポジトリ単位に分割しない）。

## 機能欠落の機械検知

```bash
# CLI/デーモン型では golden-path は「実ユーザーが必ず通す一連の操作」を指す。
# UI がないなら REQUIRE_GOLDEN_PATH は 0 のままでよいが、
# 代わりに「起動→リクエスト処理→正常終了」の一連を integration に必ず置く
REQUIRE_GOLDEN_PATH=0
GOLDEN_PATH_TESTS=(
  # "02-test/integration/e2e-request-lifecycle.sh"
)

# コミット済みコードに現れてはならないパターン（意図せぬ無効化の第二の網）
# 一時的なものには `/* STUB-<id>: */` を付ける（repo-sync ゲートが検出する）
FORBIDDEN_PATTERNS=(
  "not implemented"
  "/\\* *stub *\\*/"
  "return NULL; */\\* *(temporary|stub)"
)
FORBIDDEN_SCAN_PATHS=(
  "lib"
  "programs"
)
```

**C 固有の注意:**

| パターン | 注意 |
|---------|------|
| `#if 0` | 無効化されたコードブロックの強いシグナル。移行で一時的に囲んだまま忘れる事故が起きやすい。`FORBIDDEN_PATTERNS` に入れる価値が高い |
| `#ifdef NOTYET` 等 | プロジェクト固有の慣習を実測して追加する |
| `abort()` / `assert(0)` | 未実装パスの目印として使われていることがある。実測して判断する |

移行では「ビルドは通るが機能が無効化されている」が最も見えにくい。
`#if 0` で囲んだ範囲は**移行対応台帳の該当行と対応づけ**、処理区分を `対応不要`（理由必須）にする。

## nonfunc ゲート（opt-in）

```bash
# --- リソースリーク（長時間 — AIがバックグラウンド実行＋ログ監視で対応可）---
nonfunc_leak() {
  valgrind --leak-check=yes --error-exitcode=1 "$MODERNIZED/path/to/binary" <ARGS>
}

# --- 性能（baseline比較。±20%許容の例）---
nonfunc_perf() {
  for i in $(seq 1 10); do
    /usr/bin/time -p "$MODERNIZED/path/to/cli" <ARGS> 2>&1 | awk '/^real/{print $2}'
  done > /tmp/perf-current.txt
  # 02-test/test-results/baseline/ の実測値と比較
}
```
