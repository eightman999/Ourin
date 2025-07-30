
# Ourin — YAYA Adapter SPEC 1.0M（完全版）
**Status:** Draft ✅ / Ready for implementation  
**Updated:** 2025-07-30 22:57 UTC+09:00 (JST)  
**Scope:** Ourin (macOS, Universal 2) で、ゴーストの *YAYA 辞書(.dic)* を **Windows DLL に依存せず**ネイティブ実行するための仕様。  
**Non‑goals:** Windowsの `yaya.dll` をそのまま読むこと（不可）。dll→dylib変換もしない。

---

## 目次
- 1. 目的と背景
- 2. 用語
- 3. 互換方針（SHIORI/3.0M）
- 4. 全体アーキテクチャ
- 5. USL（Universal SHIORI Loader）
- 6. YAYA Adapter I/F（プロセス／dylib）
- 7. SHIORI/3.0M ブリッジ仕様
- 8. .dic ロード／文字コード
- 9. インストールから初回表示まで（シーケンス）
- 10. エラー処理／タイムアウト／再起動
- 11. ロギング／計測
- 12. セキュリティ／権限
- 13. 配置（Bundle）／Universal 2
- 14. ライセンス表記
- 15. 既知差分と互換ルール
- 16. 付録（メッセージ例・フォーマット・テンプレコード）

---

## 1. 目的と背景
- 既存ゴーストは `descript.txt` の **`shiori`** に `yaya.dll` 等を指定する。Ourin は **dll をロードせず**、USL が **内蔵 YAYA 実行体**へ振替える（論理置換）。
- SHIORI の通信は **SHIORI/3.0** を基準とし、**互換（3.0M）**としてヘッダ・終端・ステータスを忠実に再現。

## 2. 用語
- **USL**: Universal SHIORI Loader。`shiori` 値を解釈、適切なアダプタに委譲。
- **YAYA Core**: YAYA ランタイム本体（**ヘルパー実行体**または **`libyaya.dylib`**）。
- **Adapter**: USLと各実行体を結ぶブリッジ。

## 3. 互換方針（SHIORI/3.0M）
- **語彙・挙動互換**：メソッド（GET/NOTIFY）、必須ヘッダ、**CRLF + 空行終端**、Status、Value の扱いを忠実に実装。
- **ID: capability** を起動時にやり取りし、拡張対応を明示。

## 4. 全体アーキテクチャ
```
Ourin.app
 └ Contents/
    ├ MacOS/Ourin                 # ベースウェア本体
    ├ Helpers/yaya_core           # ★推奨：YAYA 実行体（Universal 2）
    ├ Frameworks/libyaya.dylib    # 代替：共有ライブラリ
    └ Resources/...
```
- **USL** は `descript.txt` の `shiori` を横取り解釈し、**YAYA Adapter** を選択。
- **YAYA Adapter** は **プロセス**（Helpers）または **dylib** 形態で YAYA に接続。

## 5. USL（Universal SHIORI Loader）
### 5.1 役割
- `shiori` 値から **エンジン種別を推定**（`yaya.dll` 系 → YAYA Adapter）。
- **複数ゴースト**に対して **インスタンス分離**（プロセス推奨）。
- SHIORI/3.0M の **入出力整形**（CRLF/空行・ヘッダ・Value）を担う。

### 5.2 設定とマッピング
- デフォルトは **論理置換**（`descript.txt` は書き換えない）。オプションで `shiori, ourin-usl` へ書換可能（バックアップ保存）。

## 6. YAYA Adapter I/F（プロセス／dylib）
### 6.1 形態
- **推奨：ヘルパー実行体**（`Helpers/yaya_core`）。クラッシュ隔離／差し替え容易。
- **代替：dylib 直ロード**（`libyaya.dylib`）。低レイテンシ。クラッシュ巻き添えリスク。

### 6.2 IPC プロトコル（行単位 JSON）
- 文字コードは **UTF‑8 固定**。1行＝1メッセージ。
- Ourin → Adapter：
```json
{"cmd":"load","ghost_root":"/path/to/ghost/master","dic":["a.dic","b.dic"],"encoding":"utf-8","env":{"LANG":"ja_JP.UTF-8"}}
{"cmd":"request","method":"GET","id":"OnBoot","headers":{"Charset":"UTF-8","Sender":"Ourin"},"ref":[]}
{"cmd":"unload"}
```
- Adapter → Ourin：
```json
{"ok":true,"status":200,"headers":{"Charset":"UTF-8"},"value":"\0\s[0]Hello from YAYA\e"}
{"ok":false,"status":500,"error":"load failed: ... "}
```

## 7. SHIORI/3.0M ブリッジ仕様
- **メソッド**：`GET` は Value 必須、`NOTIFY` は Value 無視。
- **ヘッダ**（例）：`Charset`,`Sender`,`SenderType`,`SecurityLevel`,`ID`,`BaseID`,`Reference0..n`。
- **終端**：ヘッダ群 → 空行 → Value（`GET` のみ）。改行は **CRLF**。
- **ステータス**：200/204/400/500 等。

## 8. .dic ロード／文字コード
- **探索順**：
  1) `~/Library/Application Support/Ourin/Ghosts/<name>/ghost/master/*.dic`
  2) インストール先の `ghost/master/*.dic`
  3) バンドル同梱テンプレ `Resources/Ghosts/<name>/ghost/master/*.dic`
- **文字コード**：既定 **UTF‑8**。妥当でなければ **CP932（Windows‑31J）**で再試行。設定で固定可能。

## 9. インストールから初回表示まで（シーケンス）
1) **Ourin を配置（署名・公証済み）**  
2) **初回起動ウィザード**：ゴーストフォルダ/NARを選択→展開→`ghost/master` 構成を検証。  
3) **USL** が `descript.txt` を読んで `shiori` を解析 → **YAYA Adapter** に決定。  
4) **YAYA Adapter** を起動：`load` で `.dic` 群を読み込む（UTF‑8→CP932の順）。  
5) **SHIORI/3.0M**：`OnBoot` を `GET` 送信 → `Value`（SakuraScript）を受領。  
6) **レンダラ**：SakuraScript を描画（`\0/\1/\n/\w/\e` など最小集合から）。  
7) **表示**：シェル＆バルーンに初期セリフを表示。

```
User → Ourin → USL → YAYA Adapter → (YAYA) → USL → Ourin Renderer → Balloon
```

## 10. エラー処理／タイムアウト／再起動
- 既定タイムアウト **5s**。超過はキャンセルし UI に通知。
- `load` 失敗：文字コード/パス/辞書破損をメッセージで提示（ログ採取）。
- 連続クラッシュは **バックオフ**（指数的）。

## 11. ロギング／計測
- 構造化ログ：`ts, req_id, id, method, latency_ms, status`。
- トレース：必要に応じ **tama 互換ログ**を出力。

## 12. セキュリティ／権限
- 外部起動やURLは OS API（NSWorkspace）へ委譲。
- SSTP は既定 **localhost** のみ開放。

## 13. 配置（Bundle）／Universal 2
- **Helpers/** または **Frameworks/** に内蔵実行体を配置。
- 全バイナリは **Universal 2（arm64 + x86_64）**。

## 14. ライセンス表記
- **YAYA**: BSD‑3‑Clause（LICENSE を同梱／About 画面にクレジット）。

## 15. 既知差分と互換ルール
- **Windows専用 SAORI** は対象外（将来はネイティブ置換/ブリッジ）。
- **TabletMode 等**は mac に概念がないため未対応。

## 16. 付録（メッセージ例・テンプレコード）
### 16.1 Ourin→Adapter（Swift：標準入出力JSON）
```swift
struct YayaMessage: Codable { let cmd: String; let method: String?; let id: String?; let headers: [String:String]?; let ref: [String]? }
let proc = Process()
proc.executableURL = Bundle.main.url(forAuxiliaryExecutable: "yaya_core")
let inPipe = Pipe(), outPipe = Pipe()
proc.standardInput = inPipe; proc.standardOutput = outPipe
try proc.run()
let load = YayaMessage(cmd: "load", method: nil, id: nil, headers: ["Charset":"UTF-8"], ref: nil)
let data = try JSONEncoder().encode(load)
inPipe.fileHandleForWriting.write(data + "\n".data(using: .utf8)!)
```
### 16.2 SHIORI 受発信（CRLF 終端）
```swift
func buildGET(id: String, refs: [String]) -> Data {
  var headers = [
    "ID": id, "Charset": "UTF-8", "Sender": "Ourin"
  ]
  for (i, r) in refs.enumerated() { headers["Reference\(i)"] = r }
  let head = headers.map { "\($0): \($1)\r\n" }.joined() + "\r\n"
  return Data(head.utf8)
}
```
