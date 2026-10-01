# 分析観点 Appendix — .NET Framework → モダン .NET 移行

Method 共通の分析手順（`analysis-procedure.md`）に対する、本ドメイン固有の観点集。

**下記「観点表」が移行対応台帳の網羅の基準の供給元である**（CP-11）。Phase 0b で該当する観点を選び、
Phase 2 で検出コマンドと否定テストを用意し、Phase 3 で検出器を回して件数を得る。
`install.sh` がこのファイルを `00-analysis/analysis-appendix.md` に設置する。
Phase 0b の 0b-1（環境差異テーブル）と Phase 1 の 1-1（changelog 調査）の入力も兼ねる。

書き方は [docs/authoring-playbook.md](../../docs/authoring-playbook.md)「観点表の書き方」を参照。

**検出コマンドの `$SRC` は移行元ソースのルートに読み替える。** 実際の移行では走査対象を
環境変数で切り替えられる形にし、Phase 4 で実装ツリーに向けて再走査する。

---

## 観点表（網羅の基準の供給元）

**種類**: ② ビルドは成功し実行時か本番でだけ壊れる / ③ ビルドは失敗するが**素直な修正が別の何かを壊す**。
①（ビルドが直すべき場所を列挙する）は網羅の基準に引かない — 下の「分析入力」に置く。

### A. System.Web / ASP.NET MVC 5 → ASP.NET Core

| ID | 観点 | 種類 | 検出コマンド | 参照 |
|----|------|------|------------|------|
| MP-1 | **「既定で認証必須」がグローバルフィルタ1行に依存している。** 旧 FW 専用型を使う登録処理は**ファイルごと削除すればビルドが通り**、消えるのは認可という横断的関心事である。認可の欠落は「動く」ため最もサイレント障害になりやすい。**逆方向の欠落もある**: ログインコントローラへ `[AllowAnonymous]` を新規付与すると 401 が起きなくなり、旧 OWIN が認可の副作用として与えていたログイン導線が消える（→ DP-9） | ③ | `grep -rn 'filters\.Add\|GlobalFilters\|RegisterGlobalFilters' --include='*.cs' $SRC` で全体認証の登録を取る。`AllowAnonymous` は**件数ではなくファイル集合の差分**で見る（数が合っても中身が入れ替わる。実測で「例外クラス数は同じ」を根拠に取り落とした）: `comm -13 <(grep -rl AllowAnonymous $SRC \| sed "s\|$SRC/\|\|" \| sort) <(grep -rl AllowAnonymous $MODERNIZED \| sed "s\|$MODERNIZED/\|\|" \| sort)`。**差分に認証・ログイン関連が現れたら `Challenge()` / `SignInAsync()` の実在を要求する** | **DP-9**, `verify-snippets.md` §nonfunc |
| MP-2 | **`HttpPostedFileBase` 前提のカスタム検証属性は、型を `IFormFile` に替えた瞬間にサイレント障害として全部無効になる。** `if (!(value is HttpPostedFileBase f)) return base.IsValid(value);` の `base.IsValid(object)` の既定実装は **`true` を返す** → ファイルサイズ上限と拡張子 allowlist が同時に消える | ③ | `grep -rn 'is HttpPostedFileBase\|as HttpPostedFileBase' --include='*.cs' $SRC` — さらに `ValidationAttribute` 派生クラスを列挙して `IsValid` 内の型判定を全件目視する: `grep -rln ': ValidationAttribute' --include='*.cs' $SRC` | **DP-6**, `verify-snippets.md` §negative-test |
| MP-3 | **MVC5 のビューに残る `asp-*` 属性は不発（素の HTML 属性）であり、移行で有効化されて壊れていた機能が動き出す。** 「現行と同値」を成功基準に置くと**壊れたままの再現が正解になる** → 箇所ごとに期待動作を定める（回復 / 未回復 / 現状維持 / 無影響）。`_ViewImports.cshtml` は**自フォルダとサブフォルダにしか効かない**（Area 配下には別途必要）。**対象は `asp-*` に限らない** — MVC5 で `MapMvcAttributeRoutes()` を呼んでいなければ `[Route]` も不活性で、移行後に有効化されてルートが変わる。**移行元で不活性だった宣言的機構**を一般に洗う | ③ | `grep -rho 'asp-[a-zA-Z-]*=' --include='*.cshtml' $SRC \| sort \| uniq -c` で全トークンを分類ごとに列挙し、`find $SRC -name '_ViewImports.cshtml'` の**配置ディレクトリと突合**する（Area ごとに存在するか）。属性ルーティングは `grep -rn '\[Route(' --include='*.cs' $SRC` と `grep -rn 'MapMvcAttributeRoutes' $SRC` を取り、**後者が0件なら前者は全部不活性**と判定する。<br>⚠️ **`[a-z-]` と書くと `asp-route-returnUrl` のような camelCase のルートパラメータを取りこぼす**（実測で1件の偽陰性。`[a-zA-Z-]` が正しい） | **DP-3**, ADR 相当の判断が必要 |
| MP-4 | **Tag Helper の有効化によって初めて到達可能になる経路がある。** `if (!ModelState.IsValid) return View();`（引数なし）はモデルを渡さず再レンダリングする。不発のうちは属性が評価されないので無害だが、**有効化後は `Model` が null で `NullReferenceException`** になる。正常系の E2E では原理的に到達しない。**参照データを持つビューでは同じ経路で `SelectList` 等が欠落する**（例外にならず**ドロップダウンが空**になるだけ） | ③ | `grep -rn 'return View();' --include='*.cs' $SRC` を取り、各アクションの再レンダリング先ビューが `Model\.` を参照しているかを突合する: `grep -rn 'Model\.' --include='*.cshtml' $SRC`。`ViewBag`/`SelectList` を組む処理が再レンダリング前に再実行されるかも同時に見る | MP-3 と対で見る |
| MP-5 | **`<form>` が `action` を持たず「現在 URL へ POST する」ことで hidden field の欠落を救っている箇所がある。** `asp-action` を親切に明示すると route 値が失われて壊れる（**善意の整理が壊す典型**）。ASP.NET Core の form tag helper は現在のルート値から action を生成するため一見動くが、明示指定すると失われる | ③ | `grep -rn '<form' --include='*.cshtml' $SRC \| grep -v 'action='` で action 無しの form を列挙し、同ファイル内の `asp-for` つき hidden（`name=` が付かず POST されない）を突合する: `grep -rn 'type="hidden".*asp-for' --include='*.cshtml' $SRC` | MP-3 の C-3（現状維持）区分 |
| MP-6 | **`MvcOptions.SuppressAsyncSuffixInActionNames` が既定 `true` のため、アクション名の `Async` 接尾辞がルート名から自動除去される。** 文字列で直書きした URL は 404 になるが**一覧画面は正常に描画されボタンだけが死ぬ**ので smoke で捕まらない。`Url.Action` ではないためコンパイル時にも検出されない | ② | `grep -rnE '(formaction\|href\|action)=.*[A-Za-z]Async[/}"]' --include='*.cshtml' $SRC` と、`grep -rnE 'public async Task<[A-Za-z]+> [A-Za-z]+Async\(' --include='*.cs' $SRC` を突合する。<br>⚠️ **`="[^"]*Async` と書くと0件になる**（実測）。URL は `formaction="@($"/Admin/.../ApproveAsync/{id}")"` のように **Razor 補間の内側に `"` を含む**ため、`[^"]*` が補間の開き引用符で止まる | — |
| MP-7 | **`wwwroot` を使わない旧来構成では `UseStaticFiles()` の既定が全静的ファイルを 404 にする。** 既定は `wwwroot/` を探すため、`Content/` `Scripts/` に資産を置く MVC5 構成をそのまま移すと**ビルドは通り全画像・CSS が消える** | ② | `test -d $SRC/wwwroot \|\| grep -rn 'UseStaticFiles()' --include='*.cs' $SRC`（`wwwroot` 不在かつ引数なし呼び出しなら該当）。`FileProvider` に `PhysicalFileProvider(ContentRootPath)` を渡す必要がある | **DP-8** |
| MP-8 | **`IMiddleware` として実装したミドルウェアは DI 登録が必要である。** 規約ベース（`Invoke` を持つ素のクラス）は登録不要だが、`IMiddleware` 実装は `AddTransient<T>()` を忘れると起動後の初回リクエストで例外になる（例外型は DI コンテナにより異なる。Microsoft.Extensions.DependencyInjection では `InvalidOperationException`、Autofac では `ComponentNotRegisteredException`） | ② | **走査先は実装ツリー側である**（移行元には `IMiddleware` が存在しないので0件が正しい。**移行元に当てて0件を見て「該当なし」と結論しない**）。`grep -rln ': IMiddleware' --include='*.cs' $MODERNIZED` の各型が `AddTransient\|AddScoped\|AddSingleton` に現れるかを突合する | **DP-7** |
| MP-26 | **`.csproj` の `Content Include` / `None Include` で暗黙に含まれていた単発の静的ファイル（`favicon.ico` 等）が、沈黙して移行後ツリーから消える。** ディレクトリ単位で資産を移す作業では拾われず、ビルドエラーも実行時例外も出ない | ② | 移行元 csproj の静的ファイル参照を全列挙し、配信ルート（`wwwroot` または `FileProvider` のルート）配下の実ファイルと突合する: `grep -rhoE '<(Content\|None) Include="[^"]*\.(ico\|png\|jpg\|gif\|svg\|css\|js\|txt\|xml)"' --include='*.csproj' $SRC`。実体側は `git ls-files` で照合する（MP-9 と同じ理由で FS に問い合わせない） | MP-7, MP-9 |

### B. Windows → Linux（OS 差異）

| ID | 観点 | 種類 | 検出コマンド | 参照 |
|----|------|------|------------|------|
| MP-9 | **静的アセット参照のパスの大文字小文字不一致。** Windows は大文字小文字を区別しないため現行環境では露見せず、**Linux で初めて 404** になる。例外もエラーも出ず「画像が出ない」だけで、`onerror` のフォールバック先自身も 404 になり代替画像も出ない。API 名の grep では原理的に検出できない | ② | **参照パスと実ファイル名の厳密な文字列比較**。⚠️ **`test -e` で実在判定してはならない** — 作業ホスト（macOS）の FS が大文字小文字を区別せず**検出器自身が同じ問題の影響を受ける**（CP-12）。`git ls-files` の出力と `grep -F -x` で比較する: <br>`grep -rhoE '/(Content\|images\|Images\|Scripts\|css\|lib)/[A-Za-z0-9_./-]+\.(jpg\|png\|gif\|svg\|css\|js\|ico)' --include='*.cshtml' $SRC` の各参照を `git ls-files` の一覧と厳密比較する | ADR 相当（参照側/実体側どちらを直すか）, CP-12 |
| MP-10 | **コード内の「書き込み先の物理パス」と「返却する URL」が別管理になっている箇所。** `Path.Combine(root, "images", ...)` で保存し `/Content/images/...` を返す、といった綴りの不一致は**保存は成功し例外も出ず、表示時だけ 404** になる。ストレージ実装がモード切替（ローカル / S3）を持つ場合、**片方のモードでしか露見しない** | ② | `grep -rn 'Path\.Combine' --include='*.cs' $SRC` で組まれる物理パスと、同クラスが返す URL 文字列を1件ずつ突合する。実体ディレクトリ名は `git ls-files` で確認する（MP-9 と同じ理由で FS に問い合わせない） | MP-9 |
| MP-11 | **Windows パス区切りと `.\` プレフィックスがコード・IaC・デプロイスクリプトに残る。** アプリ本体だけを直して IaC 側を見落とすと、コンテナ起動時やビルド時に初めて失敗する | ② | `grep -rnE '\\\\\|"\.\\\\\|\.\\\\' --include='*.cs' --include='*.ps1' --include='*.json' $SRC`（IaC ディレクトリを走査対象に含めることを忘れない） | — |
| MP-12 | **通貨・数値・日付の書式が Invariant カルチャで解決され、通貨記号が `¤` になる。** `Web.config` の `<globalization>` に相当する設定は移行先に無く、**明示的にリクエストローカライゼーションを設定しない限り**書式が変わる。例外は出ない | ② | `grep -rnE 'ToString\("[CcNnDdFfPp]' --include='*.cs' --include='*.cshtml' $SRC` と `grep -rn '<globalization' $SRC`（後者が0件なら移行元も既定依存＝要明示） | `reference/runtime-generation-differences.md` §5-2, §3 |

### C. ランタイム世代の差異（NLS → ICU / .NET Framework → モダン .NET）

**この節の差異は OS の違いではなくランタイム世代の違いに由来する。**
.NET Framework は常に Windows の NLS を使い、モダン .NET は全プラットフォームで既定 ICU を使う。
「Windows vs Linux」と誤って整理すると、Windows 上で .NET 10 に上げるだけの案件で観点を落とす。

| ID | 観点 | 種類 | 検出コマンド | 参照 |
|----|------|------|------------|------|
| MP-13 | **カルチャ依存比較の実装が NLS → ICU に変わり、「同じカルチャ依存のまま結果が変わる」。** 変わるのは**既定の比較種別**ではなく**カルチャ依存比較の実装**である。対象は `String.Compare` / `CompareTo` / `IndexOf(string)` / `LastIndexOf(string)` / `StartsWith(string)` / `EndsWith(string)` / `ToLower` / `ToUpper` / `TextInfo` / `CompareInfo` / `Array.Sort`。**`Equals` と `Contains` は元から Ordinal で変わらない**（ここを取り違えると数え上げの対象を間違える） | ② | まず静的解析を **opt-in で有効化する**（CA1307 / CA1309 / CA1310 は **.NET 10 時点でも既定で無効**）。`.editorconfig` か `.csproj` で `AnalysisMode=All` + 3ルールを `WarningsAsErrors` に入れ、ビルド警告を機械リストとして取る。補助: `grep -rnE '\.(Compare\|CompareTo\|IndexOf\|LastIndexOf\|StartsWith\|EndsWith)\("' --include='*.cs' $SRC \| grep -v StringComparison` | `reference/runtime-generation-differences.md` §2, `reference/compat-switches.md` |
| MP-14 | **インメモリソートの並び順が ICU 化で変わり、ページング境界でレコードの重複・欠落が起きる。** サーバ側 `ORDER BY` に翻訳される箇所（DB の collation が効く）と `ToList()`/`AsEnumerable()` 後にインメモリで並べる箇所（ICU が効く）は**影響が違うので区別して数える** | ② | `grep -rnE '\.(ToList\|AsEnumerable)\(\)' --include='*.cs' $SRC` の後続に `OrderBy` があるものを抽出する。DB 側 collation も併せて記録する（移行前後で変えていないことの確認） | MP-19, `reference/runtime-generation-differences.md` §2-1, `baseline-themes.md` |
| MP-15 | **ネイティブ依存ライブラリの出力バイト列は公式に無保証である。** 「同じ入力・設定でバイト一致する」と明記した一次情報は存在しない（無保証であること自体が明記されていない場合も、**保証があるとは読めない**）。バイト一致比較を前提にしたテストは移行後に不成立になりうる。あわせて**対象アーキテクチャ（arm64 / x64）でネイティブが同梱されているか**をパッケージ単位で確認する | ② | `grep -rn 'PackageReference' --include='*.csproj' $SRC` でネイティブ依存を持つパッケージを列挙し、各パッケージの `runtimes/` に対象 RID（`linux-arm64` 等）が含まれるかを確認する: `find ~/.nuget/packages/<pkg> -type d -name 'linux-*'` | `reference/runtime-generation-differences.md` §6（知覚的差異で検証する）, `baseline-themes.md` |

### D. EF6 → EF Core

| ID | 観点 | 種類 | 検出コマンド | 参照 |
|----|------|------|------------|------|
| MP-16 | **EF6 の入れ子 `Include` は EF Core でコンパイルエラーにならず実行時例外になる。** `Include(x => x.Collection.Select(y => y.Nav))` は `ThenInclude` を要求する。**コンパイラは検出しない** | ② | `grep -rnE 'Include\([a-z]+ *=> *[a-z]+\.[A-Za-z]+\.Select\(' --include='*.cs' $SRC` | **DP-5**, `reference/runtime-generation-differences.md` §4-2 |
| MP-17 | **遅延読み込みが既定 ON（EF6）→ オプトイン（EF Core）に変わり、`Include` 漏れが例外なく `null` / 空コレクションになる。** 画面は 200 で描画されるため HTTP ステータスとページ描画のアサーションでは通ってしまう。**値レベルのアサーションが必要** | ② | ナビゲーションプロパティの参照箇所を全列挙する（`*.cshtml` の `Model\.[A-Z][A-Za-z]*\.[A-Z]` 形式の連鎖参照 + サービス層の同型）。開発時は `ConfigureWarnings` で警告を例外に昇格させる手も併用する | `reference/runtime-generation-differences.md` §4-1, `baseline-themes.md`, MP-16 |
| MP-18 | **EF6 の DB 初期化子（`DropCreateDatabaseIfModelChanges` 等）に等価物が無く、素直な代替が既存データを破壊する。** EF Core ではモデル表現が変わるため「モデル変更を検知して作り直す」挙動を素朴に実装すると**本番データを消す**。永続化データに触るので HOLD-2 相当の判断が必要で、**E2E では検証できない**（検証しようとすると DB を壊す）。**旧 API の grep が0件になっても検出としては不足である** — EF Core 側の適用（`Migrate()` / `dotnet ef database update`）は誰かが呼ばなければ実行されないので、旧 API を消した時点では**適用経路そのものが無い状態**になる（→ MP-24） | ②③ | `grep -rnE 'DropCreateDatabase\|IDatabaseInitializer\|Database\.SetInitializer\|CreateDatabaseIfNotExists' --include='*.cs' --include='*.config' $SRC`。**代替側の経路は MP-24 で見る** | ADR 相当（Migrations への移行）, MP-24, `reference/runtime-generation-differences.md` §4-7 |
| MP-19 | **`OrderBy` なしの `First` / `Single` / `Skip` / `Take` は EF Core で安定順序が保証されない。** 例外ではなく警告のみで、**実行計画次第で結果が変わるため再現しないことがある** | ② | `grep -rnE '\.(First\|FirstOrDefault\|Single\|SingleOrDefault\|Skip\|Take)\(' --include='*.cs' $SRC` を取り、同一クエリ式に `OrderBy` があるかを突合する | MP-14, `reference/runtime-generation-differences.md` §4-3 |
| MP-20 | **DI スコープの置き換えを誤ると DbContext がリポジトリ間で共有されず Unit of Work が壊れる。** 旧 FW 専用のリクエストスコープ（`InstancePerRequest()` 等）はビルドエラーになるので**気づく**が、**何に置き換えるかで沈黙する障害が生まれる**: 例外は出ず、主エンティティの作成だけ成功して付随する更新がコミットされない | ③ | `grep -rn 'InstancePerRequest\|Autofac\.Integration\.\(Mvc\|Owin\|WebApi\)' --include='*.cs' $SRC`。**置換後は「1リクエスト=1 DbContext=1 SaveChanges で全変更が保存される」ことを動線でアサートする**（主エンティティの作成だけを見ると通る） | `verify-snippets.md` §integration（該当 DP なし） |
| MP-21 | **追跡 / detached の変化で「今は不発の分岐」が効き始める。** 二重防御のどちらが実際に効いているかを理解せずに片方を「死んでいるから」と消すと、サイレント障害になる（例: 値が空なら上書きしない `IsModified = false` のガードと、呼び出し側の `if (x != null)` の二重化） | ③ | `grep -rn 'IsModified\|Entry(.*)\.Property\|SetValues\|AsNoTracking' --include='*.cs' $SRC` を列挙し、**各ガードが現行で発火するか**を追跡クエリかどうかまで遡って判定する。「不発だから削除」の前に発火条件を書き出す | CP-8（因果の実証） |

### E. メタ観点（分析結果そのものを疑う）

| ID | 観点 | 種類 | 検出コマンド | 参照 |
|----|------|------|------------|------|
| MP-22 | **自動分析（ATX/CCA 等）が「置き換えが必要」と報告した項目が、実際には死コードであることがある。** **宣言の存在は使用の証拠にならない。** 実測では、バンドル機構が「等価な代替がなく HOLD 候補」と報告されたが**描画呼び出しが0件の死コード**で、写していれば不要なバンドラー導入をスコープに入れていた。件数も再測定が必要である（30項目中6項目が誤り） | ② | **宣言側と使用側を別のコマンドで数える。** 例: `grep -rn 'System\.Web\.Optimization\|BundleTable' --include='*.cs' $SRC`（宣言）と `grep -rn '@Styles\.Render\|@Scripts\.Render' --include='*.cshtml' $SRC`（描画）。**後者が0件なら死コードである** | CP-3, **DP-4** |

### F. デプロイ経路・設定注入・実行基盤

**節A〜E はアプリのソースを走査するが、本節は IaC・コンテナ・設定注入経路を走査する。**
`cdk synth` / `terraform plan` は**テンプレートの構文**を検査するがアプリとの整合は見ず、
ローカル検証は本番の起動経路（コンテナ・タスク定義・IaC が注入する設定）を通らない。
**経路の「欠落」は、存在するものを数える grep では出てこない。**
本節の観点は**宣言ではなく合成後出力（`cdk synth` / `terraform plan` の出力）を判定の基準にする。**

| ID | 観点 | 種類 | 検出コマンド | 参照 |
|----|------|------|------------|------|
| MP-23 | **コンテナイメージ・ビルド成果物・IaC の CPU アーキテクチャ指定が一致していない。** 4箇所（`RuntimeIdentifier` / ベースイメージ / **イメージのビルドプラットフォーム** / IaC の CPU 指定）が別々に管理されるため、**ビルドも `synth` も通る**。実行時に `exec format error` で起動失敗するか、エミュレーションで起動して**全機能が異常に遅い**。開発機（arm64）とデプロイ先（x64）が違う構成で特に起きる。**4点目が最も抜けやすい**: CDK の `ContainerImage.FromAsset` はビルド先アーキテクチャを `AssetImageProps.Platform`（`Amazon.CDK.AWS.Ecr.Assets.Platform_.LINUX_AMD64`）で別に持ち、未指定ならビルドホストの既定になる。タスク定義側は `X86_64` を宣言できるので、**`cpuArchitecture` の grep はヒットし「整合している」ように見える** | ② | **4点突合する。** `grep -rn 'RuntimeIdentifier\|PlatformTarget' --include='*.csproj' $MODERNIZED` / `grep -rniE 'FROM \|--platform' $MODERNIZED`（Dockerfile）/ `grep -rn 'FromAsset\|AssetImageProps\|Platform_' $MODERNIZED`（イメージのビルド指定）/ IaC の CPU 指定 `grep -rniE 'cpuArchitecture\|architecture' $MODERNIZED`。**合成後出力で断定する**: `cdk synth && grep -o '"platform":[^,]*' cdk.out/*.assets.json` が `"linux/amd64"` を返すこと。**走査先は実装ツリー側である**（移行元に該当構成は無いので0件が正しい）。<br>⚠️ **QEMU ユーザーモードエミュレーション上では `dotnet publish` が SIGSEGV（exit 139）で落ちる**（.NET SDK の JIT との既知の相互作用）。ローカルでのクロスアーキ実ビルド検証は成立しないので、宣言と合成後出力で確認する | MP-15（ネイティブ依存の RID）, MP-11 |
| MP-24 | **本番相当環境でスキーマ適用とシード投入を行う経路が、移行後に存在しない。** 旧 FW は EF6 の初期化子や `App_Start` で暗黙に作成していたため、移行先で**適用を明示的に書かないと経路そのものが消える**。アプリは正常起動して HTTP 200 を返しながら**全画面が空**になる。ローカルは開発用の初期化やテストデータで動くので、**デプロイ先で初めて露見する** | ② | **経路の存在を見る。マイグレーション定義の存在は経路の証拠にならない。** `grep -rn 'Migrate()\|MigrateAsync\|EnsureCreated()' --include='*.cs' $MODERNIZED` が0件なら適用経路が無い。**ヒットしても、それを囲む `if` の条件が本番設定で真になるかを1件ずつ判定する**（検証専用の環境変数分岐の中でしか走らない形が実測で起きた）。IaC 側の投入手段（Custom Resource / RunTask / initContainer）も列挙する。**再現は全テーブルを DROP した状態からの起動で行う**（起動とヘルスチェックは成功し、DB 依存画面だけが 500 になる）。<br>⚠️ **手動適用に倒す場合、DB がプライベートサブネットにあると接続手段（bastion / SSM ポートフォワード）自体が IaC に無い**ことが多い | MP-18（初期化子に等価物が無い）, HOLD-2 相当 |
| MP-25 | **IaC が注入する設定キーの表記とアプリが読むキーは別々に書かれるため、静かに食い違う。** .NET の環境変数コンフィグプロバイダは階層の区切りに **`__`（二重アンダースコア）**を要求する（`Services__Database` → `Services:Database`）。IaC 側に `Services/Database` や `Services:Database` と書いても**デプロイは成功し、アプリは値を見つけられず既定値やローカルモードへ静かにフォールバックする**（例外なし・起動成功）。公開サンプルを ECS にデプロイした実測では、AWS サービス（S3 / Rekognition / RDS / CloudWatch）が一切有効化されず、常時ローカルモードだった | ② | **合成後出力を基準に突合する**（IaC のソースだけを見ると生成後の実キーを見落とす）。`cdk synth` のテンプレート（または `terraform plan`）の環境変数ブロックからキーを全列挙し、`__`→`:` を適用してからアプリ側の読み取りキーと突合する: `grep -rnE 'Configuration\[\|GetSection\(' --include='*.cs' $MODERNIZED` | MP-11 |

**「正しいと言える観測」（CP-4）と「否定テスト」（CP-13）は
[verify-snippets.md](verify-snippets.md) に置く。** 検出手段がテストになる観点は
[baseline-themes.md](baseline-themes.md) を参照する。

### 観点の収束の目安（実測）

公開サンプル（AWS の Bob's Used Bookstore。ASP.NET MVC 5 + EF6 + OWIN / .NET Framework 4.8 → .NET 10 on Linux、約 8,400 行）での実測:

- 台帳 41 行のうち**約 24 行は①**（ビルドが数秒で同じ一覧を出す）
- **TFM を切り替えてビルドを通した時点で未対応は 41 → 9 に落ちた**
- **残った 9 行は全部②③**（ビルドが沈黙する / 誤誘導する項目）だった

**②③が10件前後に収束するのが目安である。** 数十件になったら①が混ざっていないか疑う。
逆に数件しか出ないなら、検出コマンドが動いていない可能性を**否定テストで確かめる**（CP-13）。

### 検出コマンドの実測（正のテスト。2026-09-13）

上記と同じ公開サンプルの移行元ソースに全コマンドを当てた結果。**「書いたが動かない検出コマンド」を
排除するために必ず実行する**（否定テストの手順は `verify-snippets.md`）。

| ID | 実測 | 台帳の独立記録との一致 |
|----|------|---------------------|
| MP-1 | 登録 4行 / `[AllowAnonymous]` 5ファイル | ✅ 一致（例外クラスは5） |
| MP-2 | `is HttpPostedFileBase` 2件 / `ValidationAttribute` 派生 2件 | ✅ 一致 |
| MP-3 | **46 トークン**（`asp-for` 22 / `asp-validation-summary` 5 / `asp-action` 5 / `asp-validation-for` 4 / `asp-items` 4 / `asp-controller` 4 / `asp-route-id` 1 / `asp-route-returnUrl` 1）/ `_ViewImports.cshtml` 1件（**Area 配下に不在**） | ✅ 一致（46） |
| MP-4 | `return View();` 5件 | — |
| MP-5 | `action` 無し `<form>` 10件 / `name` 無し hidden 2件 | — |
| MP-6 | URL 4件 / `*Async` アクション 24件 | ✅ 一致（4 URL） |
| MP-7 | `wwwroot` 不在 | ✅ |
| MP-9 | `/Content/Images/` と `/Content/images/` が**同一ソースに併存** | ✅ 一致（大小不一致あり） |
| MP-12 | `ToString("C"/...)` 14件 / `<globalization>` **0件** | ✅ |
| MP-16 | 入れ子 `Include` **8件** | ✅ 一致（8） |
| MP-18 | 初期化子 2件 | ✅ |
| MP-20 | `InstancePerRequest` / `Autofac.Integration.*` 3件 | ✅ |
| MP-22 | 宣言 3件 / **描画呼び出し 0件 → 死コード** | ✅ 一致（死コード判定） |

**この正のテストで検出コマンドの誤りが2件見つかった**（本表の作成時に修正済み）:

1. **MP-3**: `asp-[a-z-]*=` は `asp-route-returnUrl` を取りこぼし **45 件**を返した（正解 46）。
   camelCase のルートパラメータを想定していなかった
2. **MP-6**: `="[^"]*Async` は **0 件**を返した。URL が Razor 補間の内側に `"` を含むため、
   文字クラスが補間の開き引用符で止まっていた。**「0件」を「該当なし」と読めば観点が丸ごと消えていた**

**②の観点は移行元に当てて0件になることがある**（MP-8 のように移行先の構造にしか現れないもの）。
**0件を見たら「該当なし」ではなく「走査先が正しいか」を先に疑う。**

---

## 分析入力（網羅の基準に引かない）

ビルド・アナライザが列挙する観点（①）と、移行先の決定材料。**台帳の行は起こさない。**
規模の目安が必要なときだけ数える（正確な一覧はビルドが出す）。

| 観点 | 種類 | 内容 | 確認方法 |
|------|------|------|---------|
| モダン .NET の版と EOL | 決定材料 | 目標 TFM の**サポート段階と終了日**。「LTS」表記だけを見ない（自動分析が推奨した版が数か月後に EOL だった実例がある） | Microsoft の .NET サポートポリシー（一次情報）。CP-10 |
| プロジェクトファイル形式 | ① | legacy csproj → SDK 形式。`packages.config` → `PackageReference`。`HintPath` 直参照、`AssemblyInfo.cs` の二重定義 | 変換後のビルドが正確な一覧を出す。目安: `grep -rl 'packages.config\|HintPath' --include='*.csproj' $SRC \| wc -l` |
| `System.Web` 系名前空間の除去 | ① | `System.Web` / `System.Web.Mvc` / `Microsoft.Owin` / `ConfigurationManager` / `HttpContext.Current` / `Global.asax` / `System.Drawing`（GDI+） | **コンパイルエラーが全箇所を列挙する。** 事前に数えない |
| EF6 名前空間・Fluent API の改名 | ① | `System.Data.Entity` → `Microsoft.EntityFrameworkCore`、`DbModelBuilder` → `ModelBuilder` | 同上 |
| Razor 旧ヘルパの置換 | ① | `@Html.Partial` → `PartialAsync`、`@Html.BeginForm` → `<form asp-action>` | アナライザ警告とビルドで出る。**ただし `asp-*` の不発は①ではなく MP-3（③）である** |
| 設定ファイルの移行 | ① | `Web.config` / `App.config` → `appsettings.json` + `IConfiguration`（+ シークレットストア） | 設定が欠けると**起動時に失敗する**ため沈黙しない。ただし**注入経路**は MP-11（パス）と MP-25（キーの表記）で見る |
| コンテナ・IaC の前提 | ① | Windows コンテナ → Linux コンテナ、ベースイメージ、`OperatingSystemFamily`、IaC プロジェクトの TFM | IaC のビルド・`synth` が出す。ただし**パス区切りは MP-11**、**アーキテクチャの一致・設定注入・適用経路は節F**（ネイティブ依存の RID は MP-15） |
| 移行元のツールチェーン警告 | 決定材料 | ⚠️ **作業ホストが macOS / Linux の場合、.NET Framework 向けの Upgrade Assistant / API Portability Analyzer は実行できない。** 台帳の供給源4本のうち1本が**最初から使えない**ことを前提に計画する（代替: 構造分析 + 変更ログ精査 + コード起点走査で補強する） | 着手時に作業ホストで実行可否を実測する。不能なら代替担保を work-plan に明記する |
| 既存テスト資産 | 決定材料 | テストプロジェクトの有無と実行可否（baseline モードの判断） | `find $SRC -name '*.csproj' \| xargs grep -l 'Microsoft.NET.Test.Sdk\|xunit\|NUnit\|MSTest'` |

---

## 環境差異テーブルに含めるべき項目（0b-1）

上記の観点表と分析入力から、**移行元・移行先の実値を持つもの**を
`01-plan/environment-diff-table.md` の「ドメイン固有の差異観点」に展開する。

| 差異観点 | 移行元の実値 | 移行先の実値 | ⚠️ 検出ツール自体が同じ差異の影響を受けるか |
|---------|------------|------------|----------------------------------------|
| カルチャ依存比較の実装 | NLS（.NET Framework は常に NLS） | ICU（既定） | — |
| 既定カルチャ | Windows のシステムロケール | **Invariant**（明示指定しない限り） | — |
| ファイルシステムの大文字小文字 | 区別しない | **区別する** | ✅ **受ける。** 作業ホストが macOS なら検出器も区別しないため `test -e` は偽陰性になる（CP-12） |
| パス区切り | `\` | `/` | — |
| 遅延読み込み | 既定 ON（EF6） | オプトイン（EF Core） | — |
| タイムゾーン ID | Windows 形式 | **モダン .NET では Windows 形式・IANA 形式のどちらも解決できる**（ICU 利用可能な環境）。「Linux では Windows ID が使えない」は**古い前提** | — |
| `decimal` の丸め | `MidpointRounding.ToEven` | **同じ**（変更されていない）。ラウンドトリップ書式化の変更は `Double`/`Single` のみ | — |
| ネイティブ依存の対象 RID | win-x64 | linux-x64 / linux-arm64（**パッケージごとに同梱状況が違う**） | — |

**根拠と一次情報の URL は [reference/runtime-generation-differences.md](reference/runtime-generation-differences.md) にある**（取得日つき。§5 が「差異が無かった」項目）。

**「差異があるはず」で表を埋めてはならない。** 上の2行（タイムゾーン・`decimal`）は
**一次情報で確認したら差異が無かった**項目である。差異が無いことも実値として書く
（書かないと次の案件が同じ調査を繰り返す）。

---

## changelog 調査で優先すべきもの（1-1）

- **互換スイッチの一覧を先に引く**（[reference/compat-switches.md](reference/compat-switches.md)）。
  **互換のためのスイッチが用意されていることは、その振る舞いが変わった証拠である。**
  「何が変わったか」を網羅的に探すより「何を戻せるようにしたか」を見るほうが速い
- **依存ライブラリは「版が上がる」ものと「別実装に置き換わる」ものを区別する。**
  後者は changelog では追えないので公式移行ガイド（CP-9）と実行時検証（CP-4）に依存する。
  .NET Framework → モダン .NET で必ず後者になるカテゴリ: MVC5 / Razor 旧ヘルパ / EF6 /
  OWIN 認証 / DI コンテナの FW 統合パッケージ / バンドル機構
- **.NET Framework 向けの polyfill パッケージは削除対象である**（`System.Memory` /
  `System.ValueTuple` / `System.Text.Json` / `Microsoft.Bcl.*` /
  `System.Runtime.CompilerServices.Unsafe` / `Microsoft.Extensions.*.Abstractions` 等）。
  モダン .NET では BCL に含まれ、**明示参照を残すと版が競合しうる**
- **公式の破壊的変更一覧を版の境界ごとに網羅する**（CP-9）。.NET Framework 4.x から
  モダン .NET への移行は多段ジャンプであり、Globalization / EF Core / ASP.NET Core の
  カテゴリを別々に読む
- **EF Core のクエリ変換**: EF Core 3.0 で変換不能な式は**クライアント評価されずランタイム例外になった**
  （EF6 / EF Core 2.2 以前は黙ってクライアント評価していた）。**方向を取り違えないこと** —
  「例外を出さず結果が変わる」ではなく「EF6 で動いていたクエリが例外で落ちる」である
- **Globalization**: ICU 既定化（.NET 5）と、その後の版での挙動の揺れ。`InvariantGlobalization` を
  有効にすると `Compare` / `IndexOf` が**指定に関わらず常に序数**になる点に注意
- **ASP.NET Core の既定値**: `SuppressAsyncSuffixInActionNames`、静的ファイルのルート、
  Cookie / 認証系プロパティの非推奨化
- **ネイティブ依存パッケージ**: 対象 RID の同梱状況とプラットフォーム間の出力差異

---

## 分析時の注意

- **自動分析の主張は仮説である**（CP-3）。件数と「必要な作業」の両方を実コードで再測定する。
  特に**「使われている前提」を疑う**（MP-22）
- **①を網羅の基準に引かない。** 該当ゼロの行が台帳を薄め「網羅した」という誤った感覚を生む
- **検出コマンドが無い観点は、作業をしていても永久に0件のまま浮かび上がってこない。**
  ②③には必ず検出コマンドを付ける
- **検出器には否定テストを付ける**（CP-13）。壊して EXIT≠0 を確認するまで検出能力は未証明である
- **新しく踏んだ観点は本ファイルへ戻す**（CP-11）。案件の記録で終わらせない
