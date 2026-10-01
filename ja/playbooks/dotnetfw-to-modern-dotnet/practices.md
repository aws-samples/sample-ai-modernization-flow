# 移行プラクティス集 — dotnetfw-to-modern-dotnet

<!-- KNOWLEDGE-REVIEWED: 2026-09-13 (9 entries, playbook newly created) -->

**.NET Framework（4.x 系）で稼働するアプリケーションをモダン .NET（.NET Framework 非依存の .NET）へ
移行する**案件に固有の知見を `DP-N` 形式で蓄積する。ドメイン・言語を問わない共通知見は
`method/practices-common.md` の `CP-N` を参照。

対象範囲の例: ASP.NET MVC 5（OWIN self-host / IIS）→ ASP.NET Core / `packages.config` と
`PackageReference` の混在の解消 / Windows 依存 API（`System.Web`・IIS 統合・レジストリ・
`Web.config` transform）の置き換え / Linux ターゲットへの移植 / コンテナ化。

**エージェントが既定で読むのは Summary 表だけである。** 本文は該当テーマに当たったときに開く。

一次情報つきの差異カタログは [reference/runtime-generation-differences.md](reference/runtime-generation-differences.md)、
検証の実装例と否定テストは [verify-snippets.md](verify-snippets.md) にある。**本文を複製しない。**

---

## Summary

| ID | 要点 | 効く場面 | 一行の理由 |
|----|------|---------|-----------|
| DP-1 | 移行先の .NET 版は**サポート段階と終了日**の一次情報で裏取りする | 0b（移行先決定） | .NET は毎年11月に版が切り替わり、自動分析の推奨と作業時点の最適が1〜2世代ずれる。「LTS」表記は**残存期間を表さない** |
| DP-2 | 長時間の分析実行（ATX）は Step 単位でコミットされ会話 ID で再開できる | 0a（分析実行） | 中断＝やり直しではない。まず staging ブランチのコミット状況を見る。成果物の完全性は自分で数える |
| DP-3 | MVC5 の `asp-*` は不発。有効化される前提で**箇所ごと・Area ごと**に判定する | 1-2 / 3（ビュー） | `_ViewImports.cshtml` は Core 専用かつ自フォルダとサブのみ有効（Area は別途）。「現行と同値」を成功基準にできない |
| DP-4 | 自動分析の**件数**と「必要な作業」は再測定する。**宣言の存在は使用の証拠にならない** | 2（計画） | 実測で30項目中6項目が誤り。死コードを「置き換えが必要」と読むと不要な依存導入をスコープに入れる |
| DP-5 | EF6 の入れ子 `Include` は EF Core で**コンパイルエラーにならず実行時エラー** | 3（Data 層） | `.Include(x => x.Nav.Select(...))` は `ThenInclude` へ。型が変わらないので静的解析で捕まらない |
| DP-6 | `HttpPostedFileBase` 前提の検証属性は `IFormFile` 化で**サイレント障害として無効になる** | 3（Web 層・セキュリティ） | `base.IsValid(object)` の既定実装が `true` を返す。サイズ上限と拡張子 allowlist が同時に消える |
| DP-7 | `IMiddleware` 実装は **DI 登録が必要**。Cookie 認証の一部プロパティは非推奨 | 3（Web 層） | 登録漏れは初回リクエストで例外。非推奨プロパティの設定は**起動時**に例外 |
| DP-8 | `wwwroot` 不使用なら `UseStaticFiles` に `FileProvider` を明示する | 3（Web 層） | 既定は `wwwroot/` を探す。旧来構成では**全静的ファイルが 404**（ビルドも起動も成功する） |
| DP-9 | OWIN の Active モードは**認可の副作用でリダイレクトが暗黙に起きる**。Core では `Challenge()` を明示 | 3（Web 層・認証） | ログイン導線がコード無しで成立していた。`[AllowAnonymous]` を付けると本番のログインが消える |

---

## DP-1: 移行先の .NET 版は「LTS かどうか」ではなくサポート段階と終了日で選ぶ

- **適用場面**: Phase 0b で移行先 TFM を決めるとき。自動分析（ATX/CCA 等）や LLM の推奨を
  入力に使うとき。
- **問題の形**: 自動分析が推奨する版は**作業時点より古い**。実測例では、CCA が出力全編で
  `net8.0`（LTS）を推奨し、より新しい LTS を「upcoming（今後リリース）」と記述していたが、
  その版は既に GA 済みだった。一次情報で確認すると、**推奨された版は約2か月後に EOL** で、
  すでにセキュリティ修正のみの Maintenance 段階に入っていた。
  **推奨に従えば「移行完了時点で移行先が EOL」になる。**
- **判断に使う3点**（「LTS か」だけでは不十分）:
  1. **サポート段階** — Maintenance はセキュリティ修正のみ。**新規の移行先に選んではならない**
  2. **終了日と移行完了見込みの差** — 移行期間 + その後の運用期間を覆えるか
  3. **リリースサイクル** — .NET は毎年11月に新版。偶数=LTS(3年) / 奇数=STS(2年)
- **手順**: 公式のサポートポリシー表を**都度取得**し、「サポート段階」と「終了日」を
  ADR に転記する（取得日つき）。**版名だけを記録しても、次の読者は残存期間を判断できない。**
- **なぜドメイン固有か**: .NET は**毎年版が切り替わる高頻度サイクル**を持ち、LTS でも3年で切れる。
  このため「学習データ時点で最新の LTS」と「作業時点で選ぶべき LTS」が容易に1〜2世代ずれる。
  より長寿な LTS を持つ他言語より鮮度劣化が速い。
- **アンチパターン**:
  - 自動分析の推奨 TFM をそのまま work-plan の前提にする → 移行完了時点で EOL になりうる
  - **「LTS だから安全」で判断する** → LTS/STS は**支援期間の長さ**を表すだけで**残存期間**を表さない
- **関連**: CP-3 / CP-10 / DP-4（同じ「自動分析を写す」失敗の別様式）

## DP-2: 長時間の分析実行は Step 単位でコミットされ、会話 ID で再開できる

- **適用場面**: Phase 0a で分析系の長時間ジョブ（ATX の CCA 等）を走らせるとき。中断が起きたとき。
- **実測で確認した2点**:
  1. **実行途中で Step 単位に git コミットが打たれる。** 強制停止した実測例では、停止時点で
     staging ブランチに**4コミット・104ファイル**が既にコミットされていた。作業ツリーはクリーンで
     git ロックの残骸もなく、**成果物は失われなかった**
  2. **ログ末尾に再開コマンドが提示される。** 会話 ID は staging ブランチ名の接尾辞と同一で、
     ログと artifacts がローカルに残る
- **手順**:
  1. **中断が起きたら、まず staging ブランチのコミット状況を見る**
     （`git log --oneline main..HEAD` / `git diff --name-only main..HEAD | wc -l`）
  2. **結果の退避を先に行い、その後にブランチを復帰する。** 生成物は staging ブランチに
     コミットされるため、先に `git checkout main` すると作業ツリーから消える
  3. 再開はログ末尾の提示コマンドをそのまま使う
  4. **再開の成否に関わらず、成果物の完全性は自分で機械検証する。**
     「ドメイン数 × 必須ファイル数」の充足を数える。**ツールの「完了」報告や
     再開セッションの即終了は、成果物が完全であることの証明にならない**
- **なぜドメイン固有か**: 厳密には分析ツール全般の性質である。本ドメインの実測で得た知見なので、
  ここに置いている。
- **アンチパターン**:
  - 中断＝やり直しと判断して最初から再実行する → 数百 agent min を無駄にする
  - staging ブランチを削除して片付ける → **off-limits 違反**。成果物とコミット履歴を失う。
    復帰は `git checkout main` のみで足りる
- **関連**: HOLD-6（実行中の長時間ジョブの停止）/ CP-4

## DP-3: MVC5 に残る `asp-*` 属性は不発である。移行で「有効になる」前提で箇所ごとに判定する

- **適用場面**: ASP.NET MVC 5 → ASP.NET Core の移行。特に対象が Core 版からの**バックポート**である場合、
  または過去に Core 化を試みた痕跡がある場合。
- **事実（一次確認済み）**:
  - `_ViewImports.cshtml` と `@addTagHelper` は **ASP.NET Core 専用の機構**であり、MVC5 の Razor
    エンジンは読まない。MVC5 のビュー共通 using は **`Views/Web.config`** で与えられる
  - `.csproj` の `<Content Include>` はコンパイル対象ではないので、**ファイルが存在して
    ビルドが通ることは「効いている」証拠にならない**
  - したがって MVC5 では `asp-for` / `asp-items` / `asp-action` / `asp-validation-summary` は
    **素の HTML 属性としてそのまま出力され、機能しない**
- **手順**:
  1. `grep -rho 'asp-[a-zA-Z-]*=' --include='*.cshtml' $SRC | sort | uniq -c` で全出現を分類ごとに数える。
     ⚠️ **文字クラスを `[a-z-]` に狭めると `asp-route-returnUrl` のような camelCase 属性名が切れる**
  2. `Views/Web.config` を開き、Tag Helper 機構が**有効化されていないこと**を確認する
     （`_ViewImports.cshtml` の存在だけで判定しない）
  3. **`_ViewImports.cshtml` の所在をフォルダ単位で数え、Area ごとに有無を確認する。**
     `_ViewImports.cshtml` は**自フォルダとそのサブフォルダにしか適用されず、
     `Areas/<Area>/Views/` は `Views/` のサブフォルダではない**
     → 「有効化すれば全ビューで回復する」と考えると **Area 配下を回復側に誤分類する**
  4. 各出現を**「有効化したら挙動が変わるか」で分類する**。回復する箇所は移行後に
     **現行と挙動が異なる**ため、成功基準を「現行と同値」にできない → **ADR を書いて判定規則を先に固定する**
  5. **回復すると初めて到達する経路を探す。** 属性が不発なら評価されないので、
     null モデルでの再レンダリングなどが現行では露見しない
- **落とし穴**: `<form>` に `action` を書かず hidden field も `name` を持たない箇所は、
  **現在 URL への POST でルート値に救われて動いている**ことがある。移行時に `asp-action` を
  明示追加して「整えると」束縛が消えて壊れる。**この種の箇所は「現状維持」と決め、
  禁止事項として明文化する。**
- **移行後の注意**: 移行後は `asp-*` が**正当な記述**になるため、走査のヒット数で移行漏れを
  判定できない。判定は「Tag Helper が有効化されているか」で行う。
- **関連**: MP-3 / MP-4 / MP-5 / DP-6（同じ「型や機構の変化がサイレント障害になる」系）

## DP-4: 自動分析の件数と「必要な作業」は再測定する。特に「使われている前提」を疑う

- **適用場面**: 自動分析（ATX/CCA 等）の technical-debt / remediation-plan を work-plan や
  移行対応台帳の入力に使うとき。**DP-1（版数の鮮度）とは別の失敗様式である。**
- **観測された誤り率**: 突き合わせた **30項目のうち6項目**で記述と実測がずれた。型は2つ。
  1. **件数のずれ**（4件）: いずれも**過小**であり、そのまま工数に反映すると足りなくなる。
     ビュー数のずれは「部分ビュー・レイアウトを数えるか」の**定義差**でもある
     → **数え方が書かれていない件数は、定義を決めて自分で数え直す**
  2. **「必要な作業」の誤り**（2件。より危険）:
     - バンドル機構を「**バンドラーツールへの置き換えが必要**」としていたが、描画呼び出しが **0件**で
       **登録されるが描画されない死コード**だった。写していれば**不要な依存導入をスコープに入れていた**
     - 入れ子 `Include` を **1例のみ**提示していたが実際は **8箇所**。例示を件数と読むと
       作業量を8分の1に見積もる
- **なぜこうなるか**: **自動分析は「依存が宣言されているか」を見て「使われている」と推論する。**
  宣言と使用は別の事実であり、前者だけで後者は決まらない。またビルドルート
  （`.csproj` / `.sln`）から辿れないファイル（デプロイスクリプト・SQL・静的アセット）は
  **系統的に視野の外に落ちる**。
- **手順**:
  1. **分析結果の数値を文書に転記しない。** 再測定スクリプトを書き、その出力を正とする
  2. スクリプトは「**分析結果と一致するか**」ではなく「**対比表に記録した実測値と一致するか**」を
     検査する。分析が誤っている項目は**誤ったままが正しい状態**である
  3. 「置き換えが必要」系の主張は、**置き換え対象の使用箇所を数えてから**受け入れる。
     0件なら作業は「除去」であり、代替の選定は不要（機能喪失にも当たらない）
  4. 分析の誤りを**対比表の別節に分離して書く**。同じ表に混ぜると後続の読者が
     どちらを採用すべきか判断できない
- **副産物**: 同じ経路で**自分たちの台帳の根拠文の誤り**も見つかる（結論は正しいが根拠が誤っている行）。
- **関連**: CP-3 / MP-22 / DP-1

## DP-5: EF6 の入れ子 `Include` は EF Core でコンパイルエラーにならず実行時エラーになる

- **適用場面**: EF6 → EF Core の移行（Data 層）。
- **問題**: EF6 では `Include(x => x.Orders.Select(o => o.Items))` という入れ子構文が使える。
  EF Core ではこの構文を**コンパイラは検出せず、実行時に `InvalidOperationException`** を投げる。
- **対処**:
  ```csharp
  // EF6
  .Include(x => x.OrderItems.Select(i => i.Book))
  // EF Core
  .Include(x => x.OrderItems).ThenInclude(i => i.Book)
  ```
  移行時に `grep -rnE 'Include\([a-z]+ *=> *[a-z]+\.[A-Za-z]+\.Select\('` で全数を洗い出す。
- **合わせて見るもの**: 遅延読み込みが EF Core では既定無効になるため、**`Include` 漏れが
  例外ではなく `null` / 空コレクションとしてサイレント障害になる**。E2E では関連データが実際に画面に出ることを
  **値レベルでアサートする**（HTTP 200 とページ描画では通ってしまう）。
- **なぜドメイン固有か**: EF6 → EF Core のパスを踏む案件で必ず遭遇する。
  **型システムが変わるのではなく API が変わるため静的解析で捕まらない。**
- **関連**: MP-16 / MP-17 / reference §4-1, §4-2

## DP-6: `HttpPostedFileBase` のカスタム検証属性は `IFormFile` 化でサイレント障害として無効になる

- **適用場面**: ASP.NET MVC 5 → ASP.NET Core でファイルアップロードを扱う箇所。**セキュリティ影響あり。**
- **問題**: `ValidationAttribute` を継承し `HttpPostedFileBase` にキャストして判定する属性は、
  `IFormFile` への変更後に **`base.IsValid(value)` の既定実装（`return true`）が呼ばれ、
  検証が常時 PASS になる**。ビルドエラーも実行時例外も出ない。
  結果として**サイズ上限と拡張子 allowlist が同時に消える**。
- **対処**:
  ```csharp
  // 修正前（IFormFile 化後は常時 true を返す）
  public override bool IsValid(object? value) {
      if (!(value is HttpPostedFileBase file)) return base.IsValid(value); // ← ここで true
      return file.ContentLength <= maxFileSize;
  }
  // 修正後
  public override bool IsValid(object? value) {
      if (value == null) return true;
      if (value is IFormFile file) return file.Length <= maxFileSize;
      return true;   // ← 型が想定外なら通す設計にするなら、その意図をコメントで残す
  }
  ```
- **検証**: 移行後に **runtime negative test**（上限超過ファイル・禁止拡張子の POST が拒否されること）を
  確認する。**正常系のアップロード成功だけでは防御の有無を判別できない。**
  ⚠️ **静的検査（属性が付いているか / `IFormFile` を参照しているか）だけで済ませない。**
  静的検査は「属性が付いている」ことしか言えず、「実際に拒否される」ことを言えない
  （実測でここが漏れた。→ `verify-snippets.md` の該当節）
- **なぜドメイン固有か**: `HttpPostedFileBase` → `IFormFile` は .NET Framework → ASP.NET Core 移行の
  **定型ステップ**である。定型だからこそ機械的に置換され、属性側のキャストが取り残される。
- **関連**: MP-2（③の典型例）/ `verify-snippets.md` §negative-test

## DP-7: `IMiddleware` 実装は DI 登録が必要。Cookie 認証の非推奨プロパティは起動時に落ちる

- **適用場面**: ASP.NET Core への移行でカスタムミドルウェアや Cookie 認証を書くとき。
- **問題**:
  - `IMiddleware`（`InvokeAsync(HttpContext, RequestDelegate)` の実装）を `UseMiddleware<T>()` で
    登録する場合、**`T` は DI コンテナに登録されている必要がある**。登録なしでリクエストを受けると
    実行時に解決失敗の例外が出る（規約ベースの素のクラスは登録不要なので、**書き方によって
    要否が変わる**のが罠）
  - `CookieAuthenticationOptions` の一部プロパティは非推奨で、設定すると**起動時**に
    オプション検証の例外が出る（`Cookie.Expiration` → `ExpireTimeSpan`）
- **対処**:
  ```csharp
  builder.Services.AddTransient<LocalAuthenticationMiddleware>();   // IMiddleware 実装なら必須
  options.ExpireTimeSpan = TimeSpan.FromDays(1);                    // Cookie.Expiration は非推奨
  ```
- **付随して効くこと**: ローカル開発用の認証ミドルウェア（Cookie の有無でユーザーを自動サインイン）は
  **統合テストのテストホストでも再現できる**。Cookie キーの存在で判定する実装
  （`context.Request.Cookies.ContainsKey(name)`）にすると、値の復号に関わらず認証が通るため
  E2E から認証を通しやすい。**本番構成に混入させないこと**（環境で分岐する）。
- **関連**: MP-8 / `verify-snippets.md` §integration（テストホストでの認証）

## DP-8: `wwwroot` 不使用の構成では `UseStaticFiles` に `FileProvider` を明示する

- **適用場面**: MVC 5 の旧来構成（`Content/` `Scripts/` をプロジェクトルートに置く）を
  ASP.NET Core へ移すとき。
- **問題**: MVC 5 では IIS がプロジェクトルートから静的ファイルを直接配信していた。
  ASP.NET Core の `UseStaticFiles()` は**既定で `wwwroot/` を探す**ため、`wwwroot/` がない構成では
  **静的ファイルが一切配信されない（404）**。**ビルドも起動も成功する。**
- **対処**（ファイルを物理移動しない選択肢）:
  ```csharp
  using Microsoft.Extensions.FileProviders;

  app.UseStaticFiles(new StaticFileOptions
  {
      FileProvider = new PhysicalFileProvider(app.Environment.ContentRootPath),
      RequestPath = ""
  });
  ```
  これで `/Content/Images/` → `{ContentRoot}/Content/Images/` が配信される。
  **ファイルを書き込む側も揃える**: `env.WebRootPath`（既定は `ContentRoot/wwwroot`）ではなく
  `env.ContentRootPath` を参照する。**片方だけ直すと「保存は成功し表示だけ 404」になる**（→ MP-10）。
- **選択肢の比較**: `wwwroot/` へ物理移動するほうがフレームワークの規約に沿うが、
  **参照パスの一括書き換えが必要**で、大文字小文字の不一致（MP-9）と同時に踏むと切り分けが難しくなる。
  移行の第一段では `FileProvider` 明示で通し、**規約への寄せは別 Step に分ける**のが安全である。
- **関連**: MP-7 / MP-9 / MP-10

## DP-9: OWIN の Active モード認証は暗黙にリダイレクトする。Core では `Challenge()` を明示する

- **適用場面**: OWIN の外部認証（OIDC / Cognito / Azure AD 等）を ASP.NET Core へ移行する案件。
- **問題**: OWIN の認証ミドルウェアは既定が **Active モード**で、未認証リクエストを自動的に認証
  プロバイダへリダイレクトする。**グローバル認可フィルタが 401 を出し、ミドルウェアがそれを拾って
  リダイレクトする**ため、**ログイン導線を実装したコードが存在しないことがある**。
  ASP.NET Core は Passive 相当が既定で、**`Challenge()` を明示的に呼ばなければリダイレクトは起きない**。
- **最悪の形**: 移行作業者が「ログインページは未認証でも見えるべきだ」と考えて `[AllowAnonymous]` を
  ログインコントローラに追加する。**一見正しく、ビルドも通り、ローカル簡易認証モードでは動作する。**
  しかし本番モードでは 401 が起きなくなるため**ログインが原理的に不可能**になる（実測でこれを踏んだ）。
- **対処**:
  ```csharp
  // 本番（外部 IdP）モードの Login アクション
  return Challenge(
      new AuthenticationProperties { RedirectUri = returnUrl ?? "/" },
      OpenIdConnectDefaults.AuthenticationScheme);
  ```
- **同じ理由で漏れるもの**: `IAuthenticationSignOutHandler` を実装していないハンドラーに対する
  `SignOutAsync()` は **`InvalidOperationException`** になる。OWIN の
  `AuthenticationManager.SignOut()` には対応する制約が無いため、素直な移植で踏む。
  `grep -rn 'SignOutAsync(' --include='*.cs' $MODERNIZED` の各呼び出しについて、スキームに対応する
  ハンドラーが当該インターフェースを実装しているか突合する。
- **検証**: **生のステータスコードと `Location` ヘッダを見る**（IdP のディスカバリ URL へ向いているか）。
  リダイレクトを自動追跡すると「意図した 302」と「無音の失敗による 302」を区別できない。
- **なぜドメイン固有か**: OWIN → ASP.NET Core に固有の**既定モードの差**である。型もメソッド名も
  置き換わるのでビルドは通り、消えるのは「暗黙のリダイレクト」という挙動だけになる。
- **関連**: MP-1（`AllowAnonymous` のファイル集合差分）/ MP-25（本番の設定が注入されないと
  同じ画面が別の理由で壊れる）

<!-- ENTRIES END -->
