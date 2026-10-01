# 分析観点 Appendix — C / Solaris x86 → Amazon Linux

Method共通の分析手順（analysis-procedure.md）に対する、本ドメイン固有の観点集。

**下記「観点表」が移行対応台帳の網羅の基準の供給元である**（CP-11）。Phase 0b で該当する観点を選び、
Phase 2 で検出コマンドと否定テストを用意し、Phase 3 で検出器を回して件数を得る。
`install.sh` がこのファイルを `00-analysis/analysis-appendix.md` に設置する。
Phase 0b の 0b-1（横断の環境差異テーブル）・Phase 1 の 1-1（changelog調査）の入力も兼ねる。

書き方は [docs/authoring-playbook.md](../../docs/authoring-playbook.md)「観点表の書き方」を参照。

## 観点表（網羅の基準の供給元）

**種類**: ② ビルドは成功し実行時か本番でだけ壊れる / ③ ビルドは失敗するが素直な修正が別の何かを壊す。
①（コンパイラ・リンカが直すべき場所を列挙する）は網羅の基準に採用しない — 下の「分析入力」に置く。

| ID | 観点 | 種類 | 検出コマンド | 参照 |
|----|------|------|------------|------|
| MP-1 | **機能マクロの値を移行元からそのまま持ち込むと無症状で誤動作する**（`config.h` 等の `*_HAVE_*` / `*_USE_*` はコンパイルも通り、値が誤っていてもエラーなく別の分岐を選ぶ） | ② | `grep -rnE '^#define[[:space:]]+[A-Z_]*(HAVE\|USE)_' --include='config.h' --include='*.h' .` で全量を出し、**1件ずつ man で裏取りする**（コピー元OSの値を流用しない） | DP-8 |
| MP-2 | **ILP32 → LP64 のポインタ↔整数キャストは警告どまりでビルドが通る**（`long` / `time_t` のサイズ変化も同様） | ② | ビルドに `-Wpointer-to-int-cast -Wint-to-pointer-cast -Wconversion` を付け、警告件数を数える（ツールチェーン警告が検出器である） | DP-3, DP-7, reference/longrun_server_migration_considerations.md §3 |
| MP-3 | **`time_t` 32bit 前提のハードコード（Y2038）** — 年の上限値や、シリアライズでの `xdr_long` 経由の切り詰め | ② | `grep -rnE '\b(xdr_long\|2038\|0x7[Ff]{7}[Ff])\b' .` | DP-5, DP-6, reference/longrun_server_migration_considerations.md §4 |
| MP-4 | **ワイヤーフォーマット／永続化データに `time_t`・`long`・ポインタ由来の値が含まれる**と、LP64 化でレイアウトが変わり**旧データがサイレント障害として読めなくなる**（HOLD-2 の対象） | ② | 構造体をそのまま `write`/`send` している箇所を出す: `grep -rnE '(write\|fwrite\|send\|sendto)[[:space:]]*\([^,]*,[[:space:]]*&' .` | reference/ilp32-to-lp64-struct-layout.md |
| MP-5 | **SMF → systemd はビルドに現れない**（サービス定義が移行されないまま「ビルドは成功」する） | ② | `grep -rlE 'service_bundle\|svcadm\|svccfg\|/lib/svc/' .`（該当があるのに systemd unit が無ければ未対応） | reference/solaris_linux_differences.md §2.9 |

**「正しいと言える観測」（CP-4）と「否定テスト」（CP-13）は
[verify-snippets.md](verify-snippets.md) に置く。** 検出手段がテストになる観点は
[baseline-themes.md](baseline-themes.md) を参照する。

## 分析入力（網羅の基準に採用しない）

コンパイラ・リンカが列挙する観点（①）と、移行先の決定材料。台帳の行は起こさない。

| 観点 | 種類 | 内容 | 確認方法 |
|------|------|------|---------|
| libc ABI差異 | ① | Solaris libc → glibc で欠落する関数（strlcpy, getpassphrase, cftime, gethrtime, closefrom 等）→ compat層要否 | リンクエラーが正確な一覧を出す。compat層を作るかは決定材料 |
| リンクライブラリの置換 | ① | `-lsocket -lnsl` 削除、`-ltirpc` 追加（`-I/usr/include/tirpc`）、`-pthread` | リンカが未定義参照として列挙する。reference/solaris_linux_differences.md §1.10 |
| コンパイラ差 | ① | Sun Studio → gcc/clang: `-fcommon`（GCC 10+）、implicit-function-declaration（GCC 14+）| それぞれ該当バージョン以降ではエラーになる。事前に数えない |
| Solaris固有API | ① | door/kstat/port_create/gethrtime 等 | **ATX指摘を鵜呑みにせず実コードで裏取りする**（CP-3）: `grep -rnE '\b(door_create\|kstat_open\|port_create\|gethrtime)\b' .`。マルチプラットフォーム対応ソフトウェアはOS固有API依存が予想より少ない |

## 環境差異テーブルに含めるべき項目（0b-1）

上記の観点表と分析入力から、**移行元・移行先の実値を持つもの**を
`01-plan/environment-diff-table.md` の「ドメイン固有の差異観点」に展開する
（主要マクロ値、libc の関数有無、データモデル、サービス管理の方式）。

## changelog調査で優先すべきライブラリ（1-1）

- libtirpc（ヘッダパス変更、AUTH_DES削除、deprecated API: registerrpc/pmap_set）
- OpenSSL 1.x → 3.x（該当プロダクトのみ。振る舞い変更が多い）
- Motif / X11系（GUIプロダクトのみ。2.1→2.3はソース互換）
- PAM（Solaris PAM → Linux-PAM: conversation関数のポインタ解釈差異）

## 分析時の注意

- ATX指摘のSolaris固有APIは**必ず実コードでgrep裏取り**する（CP-3）。
  具体的な内容は自プロジェクトの lessons-learned.md を確認する
- **新しく踏んだ観点は観点表へ戻す**（CP-11）。案件の記録で終わらせない
