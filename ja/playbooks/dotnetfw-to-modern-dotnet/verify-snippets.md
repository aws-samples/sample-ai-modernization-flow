# verify.sh 実装スニペット — .NET Framework → モダン .NET

`verify.sh` の各ゲートを**本ドメインで実装するときの雛形**である。
検査ロジック本体はフレームワーク本体に追随し、**プロジェクト側は設定値とゲート実装だけを書く**。
スニペットは公開サンプル（AWS の Bob's Used Bookstore）の移行で実際に動いたコードから抽出している。

**観点表（[analysis-appendix.md](analysis-appendix.md)）の `MP-N` に対応する
「正しいと言える観測」（CP-4）と「否定テスト」（CP-13）は §6 に置いている。**

---

## 1. 設定値

```bash
# 実装ツリー（複数リポジトリなら全て列挙する）
MODERNIZED_TREES=(
  "../<product>-modernized"
  # "../<component2>-modernized"
)

BUILD_CMD="${BUILD_CMD:-dotnet build <Solution>.sln -c Release}"

# 診断/スタブマーカーの走査対象（実装ソースに限定する。テストコードを含めない）
DIAG_SCAN_PATHS=(
  "app"
  "db-scripts"
)

# 非機能ゲートは opt-in（Phase 1 の ADR で「対象」と決めた場合だけ 1）
RUN_NONFUNC="${RUN_NONFUNC:-0}"

# UI 描画型のアプリでは 1 を推奨する
REQUIRE_GOLDEN_PATH="${REQUIRE_GOLDEN_PATH:-1}"
```

⚠️ **`dotnet` が PATH に無い環境がある。** 各スクリプトの先頭で明示的に通す:

```bash
export PATH="$HOME/.dotnet:$PATH"
```

## 2. build ゲート — 期待成果物

**スコープ内の全成果物を work-plan 確定時（初日）に登録する**（CP-7）。未ビルドでも登録する。

```bash
EXPECTED_ARTIFACTS=(
  # プロジェクトごとの出力アセンブリ。TFM がプロジェクトで違う場合はパスも違う
  "$MODERNIZED/app/<Web>/bin/Release/net10.0/<Web>.dll"
  "$MODERNIZED/app/<Data>/bin/Release/net10.0/<Data>.dll"
  "$MODERNIZED/app/<Domain>/bin/Release/net10.0/<Domain>.dll"
  "$MODERNIZED/app/<Common>/bin/Release/netstandard2.0/<Common>.dll"   # 共有ライブラリは TFM が違うことがある
  "$MODERNIZED/app/<Iac>/bin/Release/net10.0/<Iac>.dll"                # IaC プロジェクトも登録する

  # コードだけでなく「生成されたはずのもの」も登録する
  "$MODERNIZED/app/<Data>/Migrations"                                  # EF Core Migrations

  # ネイティブ依存があるなら出力先にコピーされたことを検査する（→ MP-15）
  # "$MODERNIZED/app/<Web>/bin/Release/net10.0/runtimes/linux-arm64/native"
)

# 除外は理由とともに書く（後の読者が「漏れ」と誤解しないため）
# <path> → <理由（ADR-N / AP-N）>
```

**ネイティブ依存の同梱をここで押さえるのが効く。** 「動いた」ではなく「存在する」を機械で見る。
コピー漏れは実行時にしか出ず、しかも**その機能を使う経路を通らないと出ない**。

## 3. smoke ゲート — 起動確認

**段階的に実装してよいが、暫定版で止めてはならない。**

```bash
gate_smoke() {
  echo "=== Gate 2: Smoke Test ==="
  if skip_if_plan_unconfirmed; then return 0; fi

  # --- 本番の smoke: 起動して HTTP に応答すること ---
  local port=5099 pid=0 code=""
  ( cd "$MODERNIZED/app/<Web>" \
      && ASPNETCORE_URLS="http://127.0.0.1:$port" \
         ASPNETCORE_ENVIRONMENT=Development \
         dotnet run --no-build -c Release >/tmp/smoke.log 2>&1 ) &
  pid=$!
  for _ in $(seq 1 30); do
    code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port/" 2>/dev/null || true)"
    [ "$code" = "200" ] && break
    sleep 1
  done
  kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true

  if [ "$code" = "200" ]; then
    pass "GET / が 200 を返す"
  else
    fail "起動確認に失敗（最後の応答コード: ${code:-なし}）"
    tail -20 /tmp/smoke.log
  fi
  gate_result "smoke"
}
```

### ⚠️ 実測した失敗: 暫定 smoke を最後まで差し替えなかった

Step 1 の時点では実装ツリーがまだ起動できないため、**暫定の smoke**（実装ツリーの存在 /
`.sln` の存在 / 起点タグの存在）で始めた。コードには
「Step 5 完了後に HTTP GET / に差し替える」とコメントを残した。
**しかし最後まで差し替えられなかった。** 起動確認は統合テスト側（テストホスト）で
実質的に行われたので全ゲートは PASS のままであり、**差し替え忘れは誰にも検出されなかった。**

**帰結:** 暫定 smoke を置くなら、**差し替えの期限を work-plan の Step の完了条件に書く。**
コード内のコメントは機械検査されないので忘れる。
「integration がカバーしているから smoke は暫定でよい」は成立しない —
**smoke は integration より速く落ちることに価値がある。**

## 4. integration ゲート — テストホストで動線を通す

.NET では**アプリのテストホスト（`WebApplicationFactory` 相当）+ インメモリ DB** で
E2E 相当が組める。**Docker も実 DB も要らない**ので CI とローカルで同じものが走る。

```bash
#!/bin/bash
# 02-test/integration/run-integration.sh
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export PATH="$HOME/.dotnet:$PATH"

TEST_PROJECT="$SCRIPT_DIR/<Product>.IntegrationTests/<Product>.IntegrationTests.csproj"
[ -f "$TEST_PROJECT" ] || { echo "❌ テストプロジェクトが見つからない: $TEST_PROJECT"; exit 1; }

dotnet test "$TEST_PROJECT" --configuration Release --logger "console;verbosity=normal" 2>&1
EXIT_CODE=$?
[ $EXIT_CODE -eq 0 ] && echo "✅ 統合テスト全件 PASS" || echo "❌ 統合テストに失敗あり（exit=$EXIT_CODE）"
exit $EXIT_CODE
```

### テストホストで認証を通す

保護されたページの動線を通すには認証が必要になる。開発用の認証ミドルウェアを
**Cookie キーの存在だけで判定する実装**にしておくと、テストから Cookie を1つ付けるだけで通せる
（→ DP-7）。**本番構成に混入させないよう環境で分岐する。**

### 登録の仕方

```bash
GOLDEN_PATH_TESTS=(
  "02-test/integration/run-integration.sh"   # 実ユーザー動線（SC-1〜SC-N）
)
INTEGRATION_TESTS=(
  # 個別の検査スクリプトを足すならここ
)
```

`REQUIRE_GOLDEN_PATH=1` にすると**未登録が FAIL になる**。UI 描画型のアプリでは必須にする。
理由: build / smoke は「起動して例外が出ないこと」しか見ないため、
**「例外なし・HTTP 200・画面が空」というサイレント障害を検出できない。**

### 何をアサートするか（値レベルで見る）

**HTTP 200 とページ描画だけでは通ってしまう**観点が多い。実際に効いたアサーションの型:

| 型 | 例 | 捕まえる観点 |
|----|----|------------|
| 静的アセットが 200 | `GET /Content/Images/<file>` が 200 | MP-7 / MP-9 / MP-10 |
| 値が本文に出る | 書籍名と価格の文字列が含まれる | MP-17（`Include` 漏れ） |
| 書式が本文に出る | 通貨記号 `$` を含む | MP-12 |
| **未認証で 302** | 保護ルートが認証へリダイレクト | MP-1 |
| **匿名で 200** | `[AllowAnonymous]` の画面が開く | MP-1（**過剰に閉じる回帰も捕まえる**） |
| 不正入力で 500 でない | 検証失敗時に入力画面がエラー付きで再表示 | MP-4 |
| **更新が作成にならない** | 既存 1件が更新され件数が増えない | MP-5 |
| 現行の壊れ方を固定 | 「更新すると既定値に戻る」を期待値として固定 | 機能除外（HOLD-1）を承認した箇所 |
| ページング境界に重複なし | 1ページ目と2ページ目に同じ ID が出ない | MP-14 / MP-19 |
| 値が保存前後で不変 | 画像を変えずに情報更新 → 画像 URL が同一 | MP-21 |

**「現行の壊れ方を期待値として固定する」行が出てくるのは正常である**（→ DP-3）。
その行には**機能除外の承認 ID（ADR）を必ず添える**。添えないと次の保守者が「バグ」として直す。

## 5. nonfunc ゲート（opt-in）— セキュリティ

Phase 1 の ADR で「対象」と決めた場合だけ `RUN_NONFUNC=1` にする。
`02-test/nonfunc/sc-n<N>-<name>.sh` を1観点1スクリプトで置き、`MODERNIZED` を環境変数で渡す。

```bash
gate_nonfunc() {
  echo "=== Gate 4: Non-functional Test ==="
  if skip_if_plan_unconfirmed; then return 0; fi
  local scripts=(
    "02-test/nonfunc/sc-n1-<idp>-wiring.sh"      # 認証基盤の結線
    "02-test/nonfunc/sc-n2-no-secrets.sh"        # 設定にシークレットが入っていない
    "02-test/nonfunc/sc-n3-secure-headers.sh"    # セキュリティヘッダ
    "02-test/nonfunc/sc-n4-auth-filter.sh"       # 既定で認証必須（→ MP-1）
    "02-test/nonfunc/sc-n5-n6-validators.sh"     # アップロード検証（→ MP-2）
  )
  for script in "${scripts[@]}"; do
    [ -f "$script" ] || { fail "nonfunc スクリプトが見つからない: $script"; continue; }
    if MODERNIZED="$MODERNIZED" bash "$script"; then pass "$(basename "$script" .sh)"
    else fail "$(basename "$script" .sh)"; fi
  done
  gate_result "nonfunc"
}
```

### 脆弱性スキャン

```bash
dotnet list package --vulnerable --include-transitive
```

**`--include-transitive` が無いと直接依存だけを見るため偽陰性になる。**
実測では付けた瞬間に High 1件（推移的依存）が現れた。推移的依存の修正は `.csproj` に
`PackageReference` を直接書いて版を上書きし、**上書きした版が publish 出力に同梱されること**を確認する。

### ⚠️ 実測した失敗: 静的検査で止まった

アップロード検証（MP-2 / DP-6）の nonfunc スクリプトは、**実装コードの静的検査**で書いた:
属性クラスが存在するか / `IFormFile` を参照しているか / モデルに属性が付いているか /
allowlist に危険な拡張子が入っていないか。スクリプト末尾にはこう書いた —
**「runtime negative test（上限超過・禁止拡張子の実際の拒否）は E2E で確認する」。**

**その E2E は追加されなかった。** 統合テストは13件あるが、**上限超過ファイルや `.exe` を
実際に POST して拒否されることを見るテストは1件も無い。**
それでも nonfunc ゲートは PASS し続けた。

**MP-2 は「型を替えると検証がサイレント障害として全部通る」観点である。**
静的検査が言えるのは「属性が付いている」「`IFormFile` という文字列がある」だけで、
**「実際に拒否される」は言えない。** これは CP-13 が指す「検出器の能力が未証明」の状態である。

**帰結: セキュリティ観点は静的検査を入口にしてよいが、
runtime negative test を「後で」にすると入らない。** 同じ Step で入れる。

## 6. 否定テスト（CP-13）— 検出器を壊して EXIT≠0 を確認する

**「0件」は「無い」とも「検出できていない」とも読める。**
観点1件につき、**わざと違反を作って検出器が落ちること**を確認し、その手順を記録する。

### 手順の雛形

```bash
# 1. 検出器を実行して現状を記録する（正のテスト）
./00-analysis/detection/<scan>.sh > /tmp/before.txt; echo "exit=$?"

# 2. わざと違反を作る（実装ツリーに一時的な変更。コミットしない）
#    例: MP-9 → 参照パスの大文字を小文字に変える
#    例: MP-1 → グローバル認可フィルタの登録行をコメントアウトする
#    例: MP-2 → 検証属性の型判定を HttpPostedFileBase に戻す

# 3. 検出器が落ちることを確認する
./00-analysis/detection/<scan>.sh > /tmp/after.txt; echo "exit=$?"   # ← 0 でないこと

# 4. 変更を戻し、検出器が元に戻ることを確認する
git -C "$MODERNIZED" checkout -- <file>
```

**記録するのは「壊し方」と「観測した exit code」の2つである。** 記録がなければ
その検出器の能力は未証明のままであり、移行対応台帳の行を「対応済」にできない。

### 観点別の壊し方（実装しやすいものから）

| MP | 壊し方 | 期待する観測 |
|----|-------|------------|
| MP-1 | 全体認可フィルタの登録行を削除する | 未認証で保護ルートが 200 を返す → integration が FAIL |
| MP-2 | 検証属性の型判定を旧型に戻す | 上限超過ファイルの POST が受理される → negative test が FAIL |
| MP-3 | Area の `_ViewImports.cshtml` を削除する | Area の検証サマリが描画されない → integration が FAIL |
| MP-6 | ルート名から `Async` 除去の前提を戻す（URL を `*Async` に書き換える） | 該当ボタンが 404 → integration が FAIL |
| MP-7 | `UseStaticFiles` の `FileProvider` を外す | 静的アセットが 404 → integration が FAIL |
| MP-9 | 参照パスの1文字を実体と違う大小に変える | 検出器が不一致を1件報告する → exit≠0 |
| MP-12 | リクエストローカライゼーションの設定を外す | 通貨記号のアサートが落ちる → integration が FAIL |
| MP-16 | `ThenInclude` を入れ子 `Include` に戻す | 実行時例外 → integration が FAIL |
| MP-19 | ページングクエリから `OrderBy` を外す | ページ境界の重複検査が落ちる（**落ちないことがある** — 再現しない性質なので**検出器側は静的走査で担保する**） |
| MP-21 | 二重防御の片方を消す | 画像を変えない更新で URL が消える → integration が FAIL |

⚠️ **MP-19 のように「壊しても落ちないことがある」観点は、
実行時テストだけを検出手段にしてはならない。** 静的走査（`OrderBy` の有無）を併用する。

## 7. 禁止パターン（`FORBIDDEN_PATTERNS`）

コミット済みコードに残ってはならない文字列を機械検知する。**空のまま走らせない。**

```bash
FORBIDDEN_PATTERNS=(
  "NotImplementedException"          # 未実装の置き去り
  "TODO: *migrat"                    # 移行 TODO の置き去り
  "throw new NotSupportedException"  # 移行で潰した経路の置き去り（意図的なら STUB- を付ける）
  "AllowAnonymous.*// *(temp|一時)"  # 一時的に認可を外した痕跡
  "InvariantGlobalization>true"      # 安易な ICU 無効化（→ reference/compat-switches.md）
  "UseRelationalNulls"               # null セマンティクスの変更（既定から動かさない）
)

# 走査対象は実装ソースに限定する（テストコードには正当に現れる）
FORBIDDEN_SCAN_PATHS=(
  "app"
)
```

⚠️ **誤検知の注意**:
- `NotImplementedException` は**自動生成コードや意図的な抽象基底**に正当に現れる。
  そのときは `FORBIDDEN_SCAN_PATHS` を絞るか、`// STUB-<id>:` を付けて意図を明示する
- `mock` / `fake` / `stub` をパターンに入れるなら**テストディレクトリを除外する**。
  テストコードでは正当な語である
- **実測での学び**: 公開サンプル（AWS の Bob's Used Bookstore）での実測では `FORBIDDEN_PATTERNS` を**1件も設定しないまま完走した**
  （コメントアウトされた例が1行あるだけ）。ゲートは常に PASS だった。
  **空の禁止パターンは「違反なし」ではなく「検査なし」である。**

## 8. 複数リポジトリ構成

```bash
MODERNIZED_TREES=(
  "../<web>-modernized"
  "../<batch>-modernized"
)
DIAG_SCAN_PATHS=(
  "app"
  "src"
)
```

`repo-sync` ゲートは**全ツリーを検査する**。片方だけコミットした状態は FAIL になる。
`DIAG_SCAN_PATHS` は**全ツリーに共通で適用される**ため、ツリーごとにディレクトリ構成が違う場合は
和集合を書く（存在しないパスは無視される）。
