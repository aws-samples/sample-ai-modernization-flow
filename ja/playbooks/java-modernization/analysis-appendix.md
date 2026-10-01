# 分析観点 Appendix — Java モダナイゼーション

Method共通の分析手順（analysis-procedure.md）に対する、本ドメイン固有の観点集。

**下記「観点表」が移行対応台帳の網羅の基準の供給元である**（CP-11）。Phase 0b で該当する観点を選び、
Phase 2 で検出コマンドと否定テストを用意し、Phase 3 で検出器を回して件数を得る。
`install.sh` がこのファイルを `00-analysis/analysis-appendix.md` に設置する。
Phase 0b の 0b-1（環境差異テーブル）と Phase 1 の 1-1（changelog調査）の入力も兼ねる。

書き方は [docs/authoring-playbook.md](../../docs/authoring-playbook.md)「観点表の書き方」を参照。

## 観点表（網羅の基準の供給元）

**種類**: ② ビルドは成功し実行時か本番でだけ壊れる / ③ ビルドは失敗するが素直な修正が別の何かを壊す。
①（ビルドが直すべき場所を列挙する）は網羅の基準に採用しない — 下の「分析入力」に置く。

| ID | 観点 | 種類 | 検出コマンド | 参照 |
|----|------|------|------------|------|
| MP-1 | **設定・テンプレート内の `javax.*` 参照**は名前空間移行でコンパイラが指摘しない（Java コードの参照は①だが、XML/JSP/TLD/properties の文字列は指摘されずに残り、実行時に解決不能になる） | ② | `grep -rEl 'javax\.(servlet\|persistence\|validation\|mail\|annotation)' --include='*.xml' --include='*.jsp' --include='*.tld' --include='*.properties' .` | — |
| MP-2 | **セキュリティ既定値の変更でページが無症状で空になる**（OGNLアローリスト・パラメータバインド・CSRF は例外を出さず空を返す） | ② | `./verify.sh integration`（非空アサーション。テストパターンは baseline-themes.md） | DP-2, DP-3 |
| MP-3 | **サーバ側の書式・大小変換が JVM 既定ロケールで解決される**（`Locale` を渡さない整形・比較は環境で結果が変わる） | ② | `grep -rnE '(String\.format\|toLowerCase\(\)\|toUpperCase\(\)\|new SimpleDateFormat\(\|new DecimalFormat\()' --include='*.java' src/ \| grep -v Locale` | DP-4 |
| MP-4 | **サーブレットコンテナの EE レベルとアーティファクトの不一致**（例: Jetty 12 は EE8/9/10 でアーティファクトが分離。取り違えると起動時か初回リクエストで落ちる） | ② | `mvn -q dependency:tree \| grep -E 'jakarta\.\|javax\.'` をコンテナの EE レベルと突き合わせる | — |
| MP-5 | **CSS フレームワークのメジャー版差で削除されたクラスがサイレント障害として無効になる**（レイアウトが崩れても HTTP 200） | ② | `grep -rnE 'class="[^"]*\b(btn-default\|pull-left\|pull-right\|hidden)\b' --include='*.jsp' --include='*.html' .` | DP-4 |
| MP-6 | **テスト実行環境のロケールが固定されていない**と、テストの成否がマシン依存になる | ② | `grep -nE 'user\.language\|user\.country' pom.xml .mvn/jvm.config 2>/dev/null` （空なら未固定） | DP-4 |
| MP-7 | **フレームワークタグが生成する要素 ID の変化**で E2E セレクタがサイレント障害として外れる（要素が見つからないだけでテストが緑になる実装がある） | ② | `grep -rnE 'By\.id\(\|#[a-zA-Z0-9_]+' --include='*.java' src/test/` を移行前後の生成HTMLと突き合わせる | DP-4 |

**「正しいと言える観測」（CP-4）と「否定テスト」（CP-13）は
[verify-snippets.md](verify-snippets.md) に置く。** 検出手段がテストになる観点は
[baseline-themes.md](baseline-themes.md) を参照する。

## 分析入力（網羅の基準に採用しない）

ビルドが列挙する観点（①）と、移行先の決定材料。台帳の行は起こさない。

| 観点 | 種類 | 内容 | 確認方法 |
|------|------|------|---------|
| JDK バージョンとEOL | 決定材料 | 現行/目標のLTS状況（例: Oracle Java 21 の Premier Support は2028年9月まで） | 各ベンダーのサポートロードマップ |
| フレームワーク互換連鎖 | 決定材料 | 「Struts 7.x→Jakarta EE 10前提」「Spring Security 6.x→Spring 6.x必須」等の連鎖に矛盾がないか（CP-10） | 各公式ドキュメントの requirements |
| `javax` → `jakarta`（Java コード） | ① | Jakarta EE 9+ への移行影響。**コンパイラが全箇所を列挙する** | 事前に数えない。規模の目安が必要なら `grep -rl "javax.servlet" src/main/ \| wc -l` |
| フレームワーク固有APIの改名 | ① | 内部パッケージへの依存（例: `com.opensymphony.xwork2` → `org.apache.struts2`） | 同上。コンパイルエラーが正確な一覧を出す |
| ビルド・テスト環境 | 決定材料 | JAVA_HOME、Mavenパス | 実機確認（test-procedures.md に明記） |

## 環境差異テーブルに含めるべき項目（0b-1）

上記の観点表と分析入力から、**移行元・移行先の実値を持つもの**を
`01-plan/environment-diff-table.md` の「ドメイン固有の差異観点」に展開する
（JDK API の非互換、GC/JVMオプションの差異、コンテナの EE レベル、CSS フレームワークの版）。

## changelog調査で優先すべきもの（1-1）

- **公式マイグレーションガイドを最優先で網羅する**（CP-9）。多段メジャージャンプは
  バージョン境界ごとにガイドが複数存在する（例: Struts 2.5→6.0 と 6.x→7.x）
- Spring Framework / Spring Security（メジャー版でXML設定・API・デフォルトが大きく変わる）
- ログファサード（SLF4J 1.x→2.x はバインディング機構が変わる）
- 依存の重複・不整合（親pomのバージョンプロパティと個別指定の食い違い）

## 分析時の注意

- **破壊的変更の総数×影響ファイル数で移行コストを見積もる**（CP-10）。段階実施
  （バージョンを1段ずつ）か一括実施かの判断材料にする
- レガシープロトコル（XML-RPC、OAuth 1.0等）の削除候補は、利用実態と代替を確認して
  HOLD-1（機能除外フロー）でユーザー判断を仰ぐ
- 既存テスト資産（ユニット/E2E）の有無と実行可否をこの段階で確認する（baseline モードC（既存テストを流用）の判断）。
  E2Eがある場合、テスト基盤の移行（コンテナプラグイン・WebDriver・ヘッドレス化）を
  work-plan のStepとして計上する
- **新しく踏んだ観点は観点表へ戻す**（CP-11）。案件の記録で終わらせない
