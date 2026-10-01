# .NET Framework → モダン .NET のランタイム世代差異

本ドキュメントは Playbook の `analysis-appendix.md` 観点表 C 節（MP-13〜MP-15）と
D 節（MP-16〜MP-21）の**根拠**である。観点表には「何を疑うか」と検出コマンドだけを置き、
一次情報と詳細は本ファイルに分離している（知見の量的規律）。

## 読み方（先に読む）

**一次情報の URL には取得日が付いている。** 一次情報は改訂される。取得日が古ければ
**再取得してから計画の前提に使う**（CP-3）。取得日を落とすと再検証不能な伝聞になる。

**「差異が無かった」項目も実値として載せている**（§5）。無いことを示すには一次情報を
網羅する必要があり、**再調査コストは「有る」より高い**。書かないと次の案件が同じ調査を繰り返す。

**⚠️ この節の差異は「Windows → Linux」ではなく「ランタイム世代」に由来するものが多い。**
OS 差として整理すると、**Windows 上で .NET Framework から .NET を上げるだけの案件で観点を落とす。**

---

## 1. 判定サマリ — 通説と実際

移行前に立てた仮説6件を一次情報で裏取りした結果。**6件すべてに誤りまたは陳腐化があった。** 3・4・5 は実在しないリスクであり、1・2・6 はリスクの方向は維持されたが根拠が誤っていた。

| # | 観点 | 通説（移行前の仮説） | 一次情報で確定した実際 | 判定 |
|---|------|-------------------|---------------------|------|
| 1 | 文字列比較の既定カルチャ | 既定が序数比較寄りに**変わる** | **既定は変わらない**（元からカルチャ依存）。変わるのは**実装が NLS → ICU になること**で、サイレント障害として結果が変わる | **CORRECTION** |
| 2 | 文字列のソート順 | **Windows=NLS / Linux=ICU** の OS 差 | .NET 5+ では**対象 Windows でも ICU が既定**。真の差は **.NET Framework（常に NLS）→ モダン .NET（既定 ICU）というランタイム世代差** | **CORRECTION** |
| 3 | `DateTime` とタイムゾーン | Linux では Windows 形式 ID が非互換で使えない | **.NET 6 以降は誤り。** Windows 形式・IANA 形式のどちらも解決できる。**コード変更は基本的に不要** | **CORRECTION** |
| 4 | 金額の丸め・表示 | `decimal` の丸めと書式が変わる | **変わらない。** .NET Core 3.0 の浮動小数点書式変更は `Double`/`Single` のみが対象で `Decimal` は非該当。**ただし別経路の実在リスクを発見**（§3） | **CORRECTION** |
| 5 | EF のクエリ変換 | 例外を出さず異なる結果を返す | **方向が逆。** EF Core 3.0 以降は変換不能な式に**例外を投げる**（黙ってクライアント評価していたのは EF6 / EF Core 2.2 以前）。**真の最優先リスクは既定値の変更**（§4） | **CORRECTION** |
| 6 | ネイティブ依存の画像処理 | 出力バイト列が変わる | Linux 動作は成立（静的リンク）。ただし**「バイト列が変わる」の根拠は誤り** — 明示されているのは SVG のレンダラ差のみ。**同時にバイト一致を保証する記述も存在しない**（記述の欠落）→ 結論の方向は維持 | **CORRECTION** |

**教訓（CP-3 の実例）:** 裏取りせずに計画の前提に使えば、**実在しないリスクに工数を割き、
実在するリスクを見落とす**。上表で「実在しないリスク」だったのは3・4・5であり、
その裏取りの過程で**当初の仮説に無かった実在リスク**（§3 のモデルバインド非対称、
§4 の遅延読み込み既定 OFF）が出てきた。

---

## 2. グローバリゼーション（NLS → ICU）

### 2-1. 何が変わるか

.NET Framework は Windows の **NLS** でカルチャ依存比較を実装する。モダン .NET は全プラットフォームで
**ICU** を使う（.NET 5 以降、対象 Windows でも既定 ICU）。**ICU と NLS はロジックが異なるため、
カルチャ依存比較 API の結果が .NET Framework と .NET 間で異なりうる。**

**既定の比較種別は変わらない。変わるのは実装である。** ここを取り違えると数え上げの対象を間違える。

| API | 既定 | 世代間で変わるか |
|-----|------|---------------|
| `String.Compare` / `CompareTo` | **カルチャ依存** | ✅ **結果が変わりうる**（NLS→ICU） |
| `String.IndexOf(string)` / `LastIndexOf(string)` | **カルチャ依存** | ✅ 同上 |
| `String.StartsWith(string)` / `EndsWith(string)` | **カルチャ依存** | ✅ 同上 |
| `ToLower` / `ToUpper` / `TextInfo` / `CompareInfo` | カルチャ依存 | ✅ 同上 |
| `ToLowerInvariant` / `ToUpperInvariant` | **インバリアントカルチャ** | 現在のカルチャには依存しない（上の行と区別する） |
| `Array.Sort`（文字列配列）/ `List<T>.Sort()`（要素が文字列）/ `SortedDictionary` / `SortedList` / `SortedSet`（キーが文字列） | カルチャ依存 | ✅ **公式に Affected API として明記** |
| `String.Equals` | **序数（Ordinal）** | ❌ 変わらない |
| `String.Contains`（`char` / `string` とも） | **序数（Ordinal）** | ❌ 変わらない |
| `String.IndexOf(char)` / `StartsWith(char)` / `EndsWith(char)` | **序数** | ❌ 変わらない（`string` 引数版とは既定が違う。**この不整合は元から両世代に存在する**） |

**具体例（公式記載）**: ICU の既定（`CompareOptions.None`）は `StringSort` と同じ動作になり、
非英数字を英数字より前に並べる → **`"bill's"` が `"bills"` より前**にソートされる。

### 2-2. 静的解析は既定で無効である

`StringComparison` の省略を検出するアナライザは3つあるが、**いずれも .NET 10 時点で
既定では有効化されていない**（"Enabled by default in .NET 10: No"）。**opt-in が必要である。**

| ルール | 検出対象 |
|-------|---------|
| CA1307 | `StringComparison` の省略を**すべて**検出（既定に関わらず。ノイズが多い） |
| CA1309 | 序数 `StringComparison` の使用を推奨 |
| CA1310 | **「既定でカルチャ依存の比較を使うメソッド」だけ**を検出（専用ルール。ノイズが少ない） |

公式ドキュメントが推奨する有効化設定は `AnalysisMode=All` + 3ルールを `WarningsAsErrors` に追加。
**移行案件では CA1310 を主、CA1307 を補助として使うのが現実的である**（CA1310 が
「既定がカルチャ依存の API」だけを狙い撃ちするため、観点 MP-13 の対象と一致する）。

### 2-3. セキュリティ含意

`string.IndexOf(string)` の既定（カルチャ依存）比較では、**リテラルの `'<'` や `'&'` を含む文字列でも
`IndexOf` が `-1`（見つからない）を返す可能性がある。** サニタイズやフィルタを `IndexOf` で
実装している箇所は、移行で**検査をすり抜ける**方向に壊れうる。

---

## 3. モデルバインドのカルチャの非対称（ASP.NET Core）

**ASP.NET Core は route data / query string と form data でカルチャの扱いが異なる。**
これは MVC5 からの仕様変更であり、**設計上の意図的な非対称**である（URL をロケール間で共有可能にするため）。

| 供給源 | カルチャの扱い |
|-------|--------------|
| route value provider / query string value provider | **常に不変カルチャ**として解釈する |
| form data | **カルチャ依存の変換**を受ける |

**リスクの形:** 金額・数量をクエリ文字列で受け渡す箇所があると、**1円ずれ類の会計事故が
例外なしで起きる**。フォームで送った値とクエリで送った値の解釈が食い違う。

**さらに、既定カルチャの解決先が環境依存になる。** ローカライゼーションミドルウェアを
明示的に組み込まない限りリクエストカルチャの動的切替は行われず、
**プロセスの既定カルチャ**（不変カルチャ、または OS / コンテナの既定）が使われる。
どのプロバイダも決定できなければ `DefaultRequestCulture` が使われる。

**対処:** リクエストローカライゼーションを明示的に設定して**既定カルチャを固定する**。
「コンテナの既定に任せる」は移行先の環境変更でサイレント障害になる。

---

## 4. EF6 → EF Core

**危険の所在は「クライアント評価の意味論変更」ではなく既定値の変更である。**

### 4-1. 遅延読み込みの既定値（最重要）

| | EF6 | EF Core |
|---|---|---|
| 遅延読み込み | **既定 `true`**（`DbContextConfiguration.LazyLoadingEnabled`） | **既定で無効（オプトイン）** |
| 有効化の条件 | — | プロキシパッケージの追加導入 + `UseLazyLoadingProxies()` の明示呼び出し + ナビゲーションプロパティを `virtual` にする |

**リスクの形:** 移行時に `Include` を書き漏らすと、**N+1 にもならず例外も出ず、
`null` / 空コレクションが返る**（サイレントなデータ欠落）。画面は 200 で描画されるため、
**HTTP ステータスとページ描画のアサーションでは通ってしまう** → **値レベルのアサーションが必要**。

**開発時の補助:** 警告を例外に昇格させる設定（`ConfigureWarnings`）を開発環境で有効にする。

### 4-2. クライアント評価（方向が逆）

EF Core 3.0 以降、**トップレベル射影（最後の `Select()`）以外**の場所に翻訳不能な式があると
**ランタイム例外を投げる**。3.0 より前はクエリのどこでもクライアント評価をサポートしていた。

**したがって移行の症状は「黙って結果が変わる」ではなく「EF6 で動いていたクエリが例外で落ちる」。**
これは退行テストで検出できる（サイレントではない）。**移行時に静的検出は困難**で、
実行するまで分からない。

なお `String.Equals(String, StringComparison)` は**データベース側に相当する関数がなく変換不可**で、
クライアント評価にもならず例外になる。

### 4-3. `OrderBy` なしの行制限操作（警告のみ）

`First` / `FirstOrDefault` / `Single` / `Skip` / `Take` を `OrderBy`（および絞り込み）なしで使うと、
EF Core は**警告のみを出し例外にはしない**。実行は継続され、**DB のクエリプラン次第で返る行が変わりうる。**

| 警告イベント | 状態 |
|------------|------|
| `CoreEventId.FirstWithoutOrderByAndFilterWarning` | **Obsolete 扱い** |
| `CoreEventId.RowLimitingOperationWithoutOrderByWarning` | efcore-9.0 時点で現行 |

⚠️ **後継の警告イベント ID 名は世代で再編されている。** ログで警告を監視する設計にするときは、
**採用する版で実際に警告が出ることを観測してから**（CP-4）テストの前提にする。

**症状の性質:** SQL 実行計画やインデックスの変更で**例外を出さず異なる行**が返る。
**再現しないことがある**ため、ページング境界のテストで固定するのが確実である。

### 4-4. `Include` の展開方式

EF Core 3.0 以降、複数の `Include`（コレクションナビゲーション）は既定で**単一 SQL 文（JOIN）**に
統合される。EF6 は複数の SQL 文を生成する場合があった。

**結果セットは論理的に同一だが、デカルト積によりクライアント側取得行数が爆発しうる。**
分割クエリに戻す手段がある（`AsSplitQuery()`）。**無症状だが本番の負荷で顕在化する**。

### 4-5. `GroupBy`

EF Core 7.0 以降、**集計を伴わない `GroupBy`** は SQL の `GROUP BY` に変換できない場合、
**結果取得後にクライアント側でグルーピングを再構築する（例外を出さない）**。
集計（`Count()` 等）を伴う場合は SQL `GROUP BY` に変換される。

**結果の内容は同一だが取得行数と性能特性が変わる。** 大規模テーブルへの適用がないか確認する。

### 4-6. null 比較の3値論理

EF Core は `!=` 比較時に `OR [col] IS NULL` 等の補正項を**自動追加**し、C# の等価セマンティクスに
合わせる。`UseRelationalNulls(true)` で無効化すると **SQL の3値論理そのまま**になり結果が変わる。

**既定を変えない限り移行前後で結果は同一と考えられる**が、
EF6 側の補正仕様を裏付ける一次情報は取得できていない（§7 の限界を参照）。

### 4-7. スキーマ適用の主体（EF6 の初期化子に等価物が無い）

| | EF6 | EF Core |
|---|-----|---------|
| 適用の主体 | **フレームワーク**。`Database.SetInitializer` は**初回 DB アクセス時**に発火する（起動時ではない） | **誰かが明示的に呼ぶ**。`Migrate()` / `MigrateAsync()` / `dotnet ef database update` |
| プロバイダ依存 | なし（SQL Server / LocalDB のいずれでも同じ） | なし（ただし**呼び出す分岐が環境依存になりやすい**） |
| 適用されないとき | — | **アプリは起動しヘルスチェックも通り、DB に触る画面だけが HTTP 500** |

- **`EnsureCreated()` と `Migrate()` は併用できない。** `EnsureCreated()` は `__EFMigrationsHistory` を
  作らないため、**後から `Migrate()` へ切り替えられない**（既存スキーマをマイグレーション管理下に置けない）。
- 実測症状: テーブルが無い DB でアプリを起動すると、**Kestrel の起動・ヘルスチェック・認証ページは
  すべて成功し、DB 依存画面だけが HTTP 500** になる。**「起動する」ことは適用経路の証拠にならない**（→ MP-24）。
- **一次情報の状態**: 本節は移行ガイドの記述ではなく**実コードと実行結果で確認した**。
  §7 の一次情報一覧に対応する URL を持たない。

---

## 5. 一次情報で確認したら「差異が無かった」項目

**この節が本ファイルで最も再利用価値が高い。** 通説として語られるが、確認すると差異が無い。

### 5-1. タイムゾーン ID（コード変更は基本的に不要）

| 主張 | 実際 |
|------|------|
| 「Linux では Windows 形式 ID（`Tokyo Standard Time`）が使えない」 | **.NET 6 以降は誤り。** `TimeZoneInfo.FindSystemTimeZoneById` は Windows 形式 ID・IANA 形式 ID の**どちらを渡しても解決できる** |

**機構:** 直接 ID での解決が失敗すると、ICU の CLDR `windowsZones` マッピングに基づく
**代替 ID 解決**にフォールバックし、成功すれば等価な `TimeZoneInfo` を生成してキャッシュする。
Windows 側も .NET 6 以降 IANA 形式 ID をサポートする。

**変わらない点:** ID が見つからなければ**例外**（`TimeZoneNotFoundException`）である。
「黙って別の値を返す」挙動は文書化されていない。

**成立条件:** **ICU が利用可能な環境であること。** 変換 API（`TryConvertWindowsIdToIanaId` 等）は
**ICU を使う場合にのみサポートされる** → 不変モードや NLS モードでは失敗する。
**したがって「ICU を切る設定」（§`compat-switches.md`）を入れると、この節の結論が崩れる。**

**付随する変更:** .NET 8 以降 `FindSystemTimeZoneById` は**キャッシュ済みインスタンスを返す**
（新規オブジェクトを生成しない）。ID 解決ロジック自体の破壊的変更ではないが、
参照等価性に依存したコードには影響する。

### 5-2. `decimal` の丸めと書式（変わらない）

| 主張 | 実際 |
|------|------|
| 「`decimal` の丸め規則が変わる」 | **変わらない。** `Math.Round` / `Decimal.Round` の既定は両世代で `MidpointRounding.ToEven`。バージョン間の変更履歴の記載は無い |
| 「.NET Core 3.0 の浮動小数点書式変更が金額計算に影響する」 | **`Decimal` は非該当。** Affected API は `Double.ToString` / `Single.ToString` / `Double.Parse` / `Double.TryParse` / `Single.Parse` / `Single.TryParse` のみ |
| 「通貨記号・小数点記号の書式が世代で変わる」 | **グローバリゼーションの「Behavioral differences」一覧に通貨記号・小数点記号の書式は列挙されていない。** `Decimal.ToString()` が現在のカルチャの既定書式を使う点は MVC5 時代から不変 |

⚠️ **ただし「書式が変わらない」ことと「表示が変わらない」ことは別である。**
**カルチャそのものが変わる**（Windows のシステムロケール → コンテナの不変カルチャ）ため、
`ToString("C")` の出力は変わる。原因は書式規則の変更ではなく**既定カルチャの変更**である
（→ 観点 MP-12。対処はリクエストローカライゼーションでの明示固定）。

**この区別を落とすと、丸め規則を調べて「差異なし」と結論し、通貨表示の破綻を見落とす。**

---

## 6. ネイティブ依存ライブラリ（画像処理を例に）

### 6-1. 一般化できる読み方

| 観点 | 読み方 |
|------|-------|
| 対象 RID の同梱 | パッケージが**どの RID のネイティブを同梱するか**を確認する。`linux-x64` はあっても `linux-musl-arm64` は無い、といった非対称が普通にある（→ **Alpine ベースイメージとアーキテクチャ選定を同時に決められない**） |
| 静的リンクか | 静的リンクビルドなら OS 側への本体インストールは不要。「コンテナに本体を入れる」対処は**不要どころか誤り**の場合がある |
| 付随ライブラリ | 静的リンクでも**フォント・文字コード系は OS 側に必要**なことがある。使っていない機能なら不要 → **機能の使用実態を先に確認する** |
| ターゲット表記 | ⚠️ **NuGet のターゲット表記が「互換性推定」（"was computed"）のみの場合、パッケージは明示的にその TFM をターゲットしていない。** 公式の対応表明が無いので**実機での動作確認が必須**（CP-4） |
| 出力の再現性 | **「同一入力で同一バイト列」を保証する記述が無いなら、保証は無いものとして設計する。** 「保証しない」と明示されていないことを「保証される」と読んではならない |
| アーキテクチャ間差異 | 上流（ネイティブ本体）に **aarch64 と x86_64 で出力が異なる**既知報告があるか確認する |

### 6-2. 実測した具体例（`Magick.NET-Q8-AnyCPU`。取得日 2026-09-03）

- **Linux ネイティブは静的リンクビルド**で同梱される → 標準的な glibc 系ディストリビューションで
  追加インストールなしに動作する設計。**コンテナ側に ImageMagick 本体を入れる必要はない**
  （メンテナが Issue で明言）
- **AnyCPU の対応:** windows(x64/arm64/x86) / **linux(x64/arm64)** / **linux-musl(x64 のみ)** /
  macOS(x64/arm64)。**musl では arm64 が未提供**
- **フォント**: Linux / macOS では `fontconfig` を OS 側に入れる必要がある（`fc-cache` の実行も要る場合がある）。
  → **テキスト描画 API を使っていないなら不要**。使用実態を先に確認する
- **OpenMP は AnyCPU 版に含まれない**（C++ 再頒布物が静的リンクされており OpenMP は静的リンクできないため）。
  OpenMP 対応は別パッケージ
- **一部フォーマット・機能は非互換ライセンス等の理由で Linux 版に含まれない**場合がある
- **SVG のビットマップ変換はレンダラ自体が異なる**（Windows: librsvg / Linux・macOS: ImageMagick 内蔵）
  → **プラットフォーム間で出力が異なる既知差異**（メンテナが公認）
- **NuGet のターゲットは `net8.0` と `netstandard2.0`。** より新しい TFM は「互換性推定」表示のみ
  → **実機確認が必須**
- **バイト一致の保証も否定も一次情報に無い**（記述の欠落を確認）→ **バイト一致比較を採らない**
- 上流 ImageMagick に **aarch64 と x86_64 で出力が異なる**報告がある（テキスト描画の事例。
  単純リサイズへの一般化はできないが、可能性の存在を示す）。リサイズ出力の非決定性は
  **OpenCL 利用時**の問題として指摘されている

**テスト設計への帰結:** バイト一致比較ではなく**知覚的差異の検証**を設計する（→ `baseline-themes.md`）。

---

## 7. 一次情報（URL + 取得日）

**すべて取得日 2026-09-03。** 改訂されている可能性があるので、計画の前提に使う前に再取得する。

### グローバリゼーション / 文字列

| 内容 | URL |
|------|-----|
| 文字列比較のベストプラクティス（各 API の既定） | https://learn.microsoft.com/en-us/dotnet/standard/base-types/best-practices-strings |
| .NET と .NET Framework の差（対象 API の列挙） | https://learn.microsoft.com/en-us/dotnet/standard/base-types/string-comparison-net-5-plus#differences-between-net-and-net-framework |
| ICU グローバリゼーション（既定化の対象 OS / ソート順の差 / Linux での ICU 版指定） | https://learn.microsoft.com/en-us/dotnet/standard/globalization-localization/globalization-icu |
| ICU 既定化の破壊的変更カタログ（Affected APIs に `Array.Sort` 等） | https://learn.microsoft.com/en-us/dotnet/core/compatibility/globalization/5.0/icu-globalization-api |
| グローバリゼーションのランタイム設定（`UseNls` / `Invariant`） | https://learn.microsoft.com/en-us/dotnet/core/runtime-config/globalization |
| 不変モードの仕様（常に序数になる） | https://github.com/dotnet/runtime/blob/main/docs/design/features/globalization-invariant-mode.md |
| CA1307 / CA1309 / CA1310（既定無効） | https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1307 ・ https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1309 ・ https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1310 |
| .NET 10 の破壊的変更一覧（Globalization は環境変数改名のみ） | https://learn.microsoft.com/en-us/dotnet/core/compatibility/10.0 |

### ASP.NET Core

| 内容 | URL |
|------|-----|
| モデルバインドのグローバリゼーション挙動（route/query は不変、form はカルチャ依存） | https://learn.microsoft.com/en-us/aspnet/core/mvc/models/model-binding#globalization-behavior-of-model-binding-route-data-and-query-strings |
| リクエストカルチャの決定（ミドルウェア未設定時の既定） | https://learn.microsoft.com/en-us/aspnet/core/fundamentals/localization/select-language-culture |

### EF6 → EF Core

| 内容 | URL |
|------|-----|
| EF6 → EF Core 移行ガイド | https://learn.microsoft.com/en-us/ef/efcore-and-ef6/porting/ |
| EF6 と EF Core の挙動差 | https://learn.microsoft.com/en-us/ef/efcore-and-ef6/porting/port-behavior |
| 移行の詳細ケース | https://learn.microsoft.com/en-us/ef/efcore-and-ef6/porting/port-detailed-cases |
| EF Core 3.x の新機能（LINQ 全面改修 / クライアント評価の制限） | https://learn.microsoft.com/en-us/ef/core/what-is-new/ef-core-3.0/ |
| EF Core 3.x の破壊的変更（単一クエリ化を含む） | https://learn.microsoft.com/en-us/ef/core/what-is-new/ef-core-3.0/breaking-changes |
| クライアント評価 vs サーバー評価 | https://learn.microsoft.com/en-us/ef/core/querying/client-eval |
| 遅延読み込み（EF Core・オプトイン） | https://learn.microsoft.com/en-us/ef/core/querying/related-data/lazy |
| `LazyLoadingEnabled`（EF6・既定 true） | https://learn.microsoft.com/en-us/dotnet/api/system.data.entity.infrastructure.dbcontextconfiguration.lazyloadingenabled?view=entity-framework-6.2.0 |
| null 比較のセマンティクス | https://learn.microsoft.com/en-us/ef/core/querying/null-comparisons |
| 複雑なクエリ演算子（`GroupBy` の変換規則） | https://learn.microsoft.com/en-us/ef/core/querying/complex-query-operators |
| データベース関数（`string.Equals(StringComparison)` は変換不可） | https://learn.microsoft.com/en-us/ef/core/querying/database-functions |
| トランザクション（`SaveChanges` の既定） | https://learn.microsoft.com/en-us/ef/core/saving/transactions |
| `FirstWithoutOrderByAndFilterWarning`（Obsolete） | https://learn.microsoft.com/en-us/dotnet/api/microsoft.entityframeworkcore.diagnostics.coreeventid.firstwithoutorderbyandfilterwarning?view=efcore-8.0 |
| `RowLimitingOperationWithoutOrderByWarning`（現行） | https://learn.microsoft.com/en-us/dotnet/api/microsoft.entityframeworkcore.diagnostics.coreeventid.rowlimitingoperationwithoutorderbywarning?view=efcore-9.0 |

### タイムゾーン / 数値

| 内容 | URL |
|------|-----|
| `FindSystemTimeZoneById`（.NET 6 以降の IANA 対応・例外） | https://learn.microsoft.com/en-us/dotnet/api/system.timezoneinfo.findsystemtimezonebyid |
| `TryConvertWindowsIdToIanaId` / `TryConvertIanaIdToWindowsId`（ICU 必須） | https://learn.microsoft.com/en-us/dotnet/api/system.timezoneinfo.tryconvertwindowsidtoianaid ・ https://learn.microsoft.com/en-us/dotnet/api/system.timezoneinfo.tryconvertianaidtowindowsid |
| 代替 ID 解決の実装（`TryGetTimeZone` / `GetAlternativeId`） | https://raw.githubusercontent.com/dotnet/runtime/main/src/libraries/System.Private.CoreLib/src/System/TimeZoneInfo.cs |
| `TimeZoneInfo` の取得方法 | https://learn.microsoft.com/en-us/dotnet/standard/datetime/instantiate-time-zone-info |
| .NET 8: `FindSystemTimeZoneById` がキャッシュを返す | https://learn.microsoft.com/en-us/dotnet/core/compatibility/core-libraries/8.0/timezoneinfo-object |
| .NET Core 3.0 の浮動小数点書式変更（`Double`/`Single` のみ） | https://learn.microsoft.com/en-us/dotnet/core/compatibility/3.0#core-net-libraries |
| `Math.Round` の既定 | https://learn.microsoft.com/en-us/dotnet/api/system.math.round |
| `Decimal.Round` の既定 | https://learn.microsoft.com/en-us/dotnet/api/system.decimal.round |
| `Decimal.ToString()` のカルチャ依存性 | https://learn.microsoft.com/en-us/dotnet/api/system.decimal.tostring |

### ネイティブ依存（画像処理の実例）

| 内容 | URL |
|------|-----|
| 対応 RID の一覧 / OpenMP 非使用 | https://github.com/dlemstra/Magick.NET |
| クロスプラットフォーム（静的リンク / `fontconfig` / 非対応フォーマット） | https://github.com/dlemstra/Magick.NET/blob/main/docs/CrossPlatform.md |
| NuGet のターゲット TFM（「互換性推定」の見分け方） | https://www.nuget.org/packages/Magick.NET-Q8-AnyCPU |
| SVG のレンダラ差（Windows: librsvg / Linux: 内蔵） | https://github.com/dlemstra/Magick.NET/issues/493 |
| コンテナに本体を入れる必要はない | https://github.com/dlemstra/Magick.NET/issues/464 |
| aarch64 と x86_64 で出力が異なる既知報告 | https://github.com/ImageMagick/ImageMagick/issues/6151 |
| リサイズ出力の非決定性（OpenCL） | https://github.com/ImageMagick/ImageMagick/discussions/3047 |

---

## 8. この文書の限界（把握している未確定事項）

**書いていないことを「無い」と読まないための節である。**

- **EF6 側の一次情報が不足している項目がある。** 移行先（EF Core）の挙動は確度高く確認できたが、
  移行元（EF6）の対応する挙動を裏付ける公式ドキュメントまで取得していない:
  `First`/`Single`/`Skip`/`Take` の既定順序保証の有無 / `GroupBy` の変換規則 /
  null 比較の3値論理補正 / `string.Compare` の正規関数マッピング / `SaveChanges` の既定トランザクション。
  **「EF6 ではこうだった」の記述は EF Core 側の記述からの推定を含む**
- **`First` 系の `OrderBy` なし使用に対する警告イベント ID は世代で再編されている。**
  採用する版で実際に警告が出るかは未確認。**観測してから前提にする**（CP-4）
- **EF Core 4〜9 の各版の破壊的変更を個別に全確認していない。** 核心（3.0 のクライアント評価変更）と
  最新差分のみを深掘りした。**この間に別の「サイレントな結果変化」がある可能性は否定できない**
- **変更追跡（change tracking）の領域は本文書の対象外である。** `Attach`/`Add` 時のグラフ追跡挙動差
  （キー生成済みエンティティの状態遷移）はクエリではなく変更追跡の問題であり、別観点として調査が必要
- **「EF Core で DB 側ソートする限り .NET 側の ICU は無関係」を直接述べた一次情報は取得できなかった。**
  一般原則（サーバー側評価優先・翻訳不能は例外）は確認済みだが、**インメモリソート箇所の
  洗い出しは実装時の実測に依存する**（→ 観点 MP-14）
- **`.NET 10` の破壊的変更一覧は公式に "work in progress" と断り書きがある。** 完全な一覧ではない
