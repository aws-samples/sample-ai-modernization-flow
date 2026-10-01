# ILP32→LP64 移行時の構造体レイアウト変化（DP-7 の詳細）

本ドキュメントは Playbook の `practices.md` DP-7 の詳細版である。
`practices.md` 側には要点・チェック方法・アンチパターンのみを置き、
背景説明とコード例は本ファイルに分離している（知見の量的規律）。

## レイアウト変化の例

```c
// ILP32 (Solaris SPARC/x86)
struct event {
    int      id;       // 4 bytes, offset 0
    time_t   start;    // 4 bytes, offset 4   ← ILP32: time_t = 4 bytes
    int      duration; // 4 bytes, offset 8
};  // sizeof = 12

// LP64 (Linux x86_64)
struct event {
    int      id;       // 4 bytes, offset 0
    // padding 4 bytes (alignment to 8)
    time_t   start;    // 8 bytes, offset 8   ← LP64: time_t = 8 bytes
    int      duration; // 4 bytes, offset 16
    // padding 4 bytes
};  // sizeof = 24
```

## 危険なパターン

| パターン | 危険度 | 説明 |
|---------|--------|------|
| `fread(&struct, sizeof, ...)` でファイルから構造体を一括読み込み | **高** | 32bit 環境で書かれたファイルを 64bit 環境で読むとフィールドがずれる |
| `(char*)ptr + offset` でフィールドにアクセス（ハードコードオフセット） | **高** | オフセットが ILP32 前提だと LP64 で誤った位置を読む |
| XDR/RPC で構造体を丸ごとシリアライズ | **中** | ワイヤーフォーマットが固定 32bit ならデコードでずれる |
| 共有メモリを通じた構造体共有 | **高** | 32bit / 64bit プロセスの混在で破綻 |
| 構造体配列を `memcpy(dst, src, n * sizeof)` | **中** | stride (要素間隔) が変わる |

```c
// ❌ 危険: ハードコードオフセット（ILP32前提）
char *ptr = (char *)&record;
time_t *start = (time_t *)(ptr + 4);  // ILP32ではoffset 4だがLP64ではoffset 8

// ✅ 安全: フィールド名でアクセス
time_t start = record.start;          // コンパイラが正しいオフセットを計算

// ✅ 安全: offsetof マクロを使用
time_t *start = (time_t *)((char *)&record + offsetof(struct event, start));
```

## 安全な場合

- **フィールド名でアクセス** (`record.field`): コンパイラがオフセットを正しく計算する
- **同一バイナリ内で完結**: リコンパイルすれば構造体レイアウトは一貫する
- **XDR をフィールド単位で使用**: エンコーダ/デコーダが個別にシリアライズ

## XDR での time_t 互換対応パターン

32bit クライアントとの互換を保ちつつ、サーバ側で 64bit time_t を使う場合:

```c
// ワイヤー上は 32bit を維持（既存クライアント互換）
// メモリ上は 64bit time_t
bool_t xdr_time_t_compat(XDR *xdrs, time_t *tp) {
    int32_t wire_val;
    if (xdrs->x_op == XDR_ENCODE) {
        wire_val = (int32_t)*tp;
        return xdr_int32_t(xdrs, &wire_val);
    } else {
        if (!xdr_int32_t(xdrs, &wire_val)) return FALSE;
        *tp = (time_t)wire_val;
        return TRUE;
    }
}
```
