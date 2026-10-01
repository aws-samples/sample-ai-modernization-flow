# verify スニペット — Java モダナイゼーション

verify.sh の各ゲートを本ドメインで実装する際のスニペット集。
（verify.sh の骨格・使い方は harness の verify.sh.template を参照）

## 共通設定

```bash
# JDKとロケールを固定する（システムデフォルトJDKや日本語ロケールでの実行を防ぐ）
export JAVA_HOME="${JAVA_HOME:-/Library/Java/JavaVirtualMachines/amazon-corretto-21.jdk/Contents/Home}"
export MAVEN_OPTS="-Duser.language=en -Duser.country=US"
MVN="${MVN:-mvn}"
```

## build ゲート

```bash
# ★ test-compile を含めること（DP-1）。compile はテスト残存を検出できない
BUILD_CMD="$MVN clean install -DskipTests"

# 期待成果物の例（war/jar）
EXPECTED_ARTIFACTS=(
  "$MODERNIZED/app/target/myapp.war"
  "$MODERNIZED/db-utils/target/db-utils.jar"
)
```

## smoke ゲート

```bash
# --- アプリ起動 + HTTP応答（コンテナプラグイン利用の例） ---
smoke_startup() {
  ( cd "$MODERNIZED" && $MVN jetty:run -pl app ) &   # またはコンテナへのwarデプロイ
  local pid=$!
  for i in $(seq 1 60); do
    code=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/<context>/ || true)
    if [ "$code" = "200" ] || [ "$code" = "301" ] || [ "$code" = "302" ]; then
      pass "startup: HTTP $code"; kill $pid; return 0
    fi
    sleep 2
  done
  fail "startup: no HTTP response"; kill $pid 2>/dev/null
}

# --- ユニットテスト（既存テスト資産がある場合は smoke 相当として毎回実行） ---
smoke_unittest() {
  ( cd "$MODERNIZED" && $MVN test -pl <module> ) && pass "unit tests" || fail "unit tests"
}
```

## integration ゲート（E2E: Selenium + ヘッドレスChrome）

```bash
# 例: 既存E2Eモジュールの実行（ビルド→E2E）
# 02-test/integration/e2e-selenium.sh として自己完結させる
( cd "$MODERNIZED" && $MVN clean install -DskipTests -pl db-utils,app && $MVN verify -pl it-selenium )
```

E2E基盤のモダナイズで必要になる典型変更（work-planのStepとして計上）:
- コンテナプラグイン: `jetty-maven-plugin` → `jetty-ee10-maven-plugin`、
  ゴール `start` → `start-war`（WARオーバーレイでは `start` はオーバーレイ内容を含まない）
- JNDI: `WEB-INF/jetty-env.xml` で定義（`jettyXmls` は無視されるコンテキストがある）
- WebDriver: Firefox → ヘッドレスChrome。Selenium 4 の Duration API
- Chromeオプション:
  ```java
  options.addArguments("--headless=new", "--no-sandbox", "--disable-dev-shm-usage",
                       "--disable-gpu", "--window-size=1920,1080", "--lang=en-US");
  ```
- プロパティのリソースフィルタリング（`${project.basedir}` 解決）を有効化

## 複数リポジトリ構成と診断マーカー走査

```bash
# 1システムが複数リポジトリで構成される場合（例: API と SPA が別リポジトリ）は全て列挙する。
# repository-inventory.md の repo-id と対応させること。
MODERNIZED_TREES=(
  "../api-modernized"
  "../web-modernized"
)

# 診断コードマーカー（DIAG-）の走査対象。Java なら実装ソースに絞ると速い
DIAG_SCAN_PATHS=(
  "app/src"
  "db-utils/src"
)
```

期待成果物・integration テストはリポジトリ横断で1つのリストにまとめる
（ゲートは「システムとして動くか」を見るため、リポジトリ単位に分割しない）。

## 機能欠落の機械検知

```bash
# 実ユーザー動線をブラウザで通す E2E。UI描画型アプリでは必須（DP-5）
REQUIRE_GOLDEN_PATH=1
GOLDEN_PATH_TESTS=(
  "02-test/integration/e2e-golden-path.sh"   # 登録→ログイン→主要CRUD→表示
)

# コミット済みコードに現れてはならないパターン（意図せぬスタブ化の第二の網）
# 一時的なものには `// STUB-<id>:` を付ける（repo-sync ゲートが検出する）
FORBIDDEN_PATTERNS=(
  "not implemented"
  "TODO: *implement"
  "return null; *// *(temporary|stub|mock)"
)
# テストコードは除外する（テストのモックは正当）
FORBIDDEN_SCAN_PATHS=(
  "app/src/main"
)
```

**誤検知しやすいパターンの扱い:**

| パターン | 注意 |
|---------|------|
| `UnsupportedOperationException` | 不変コレクション等で正当に使われる。使うなら対象パスを絞る |
| `mock` | テストコードでは正当。`FORBIDDEN_SCAN_PATHS` を `src/main` に限定する |
| `@Disabled` / `@Ignore` | テスト無効化の検出には有用だが、恒久的な skip は理由コメント必須という別ルールで扱う |

golden-path E2E の最小構成（`02-test/integration/e2e-golden-path.sh`）:

```bash
#!/bin/bash
# 実ブラウザで実ユーザー動線を通す。build/unit/smoke では捕まらない
# 「例外なし・HTTP 200・画面が空」を検出するための一級の検証。
set -e
cd "${MODERNIZED:-../<PRODUCT>-modernized}"
JAVA_HOME="${JAVA_HOME:?}" mvn -q clean install -DskipTests -pl db-utils,app
JAVA_HOME="${JAVA_HOME:?}" mvn -q verify -pl it-selenium
```

E2E は**非空アサーション**を必ず含める（描画されたことまで確認する）。
「HTTP 200 が返った」は描画の証拠にならない。

## nonfunc ゲート（opt-in）

```bash
# --- メモリ/GC観測（長時間 — AIがバックグラウンド実行＋ログ監視で対応可） ---
# 例: 起動後に負荷をかけ、jstat でGC統計・ヒープ推移を記録して baseline と比較
nonfunc_gc() {
  jstat -gcutil <pid> 10000 60 > /tmp/gc-current.txt
  # 02-test/test-results/baseline/ と比較
}
```
