# SSTP ホストモジュール概要

Ourin に実装されている SSTP 関連モジュールの役割をまとめます。実装は `docs/SSTP_1.xM_SPEC.md` を元にしており、macOS ネイティブ環境で動作します。

## 主なコンポーネント
- **UnifiedSstpListener / SstpTcpServer / SstpHttpServer**: TCP 9801 番ポートで待ち受けを行い（HTTP も同一ポートで多重化）、1 接続ごとに SSTP メッセージを処理します（実装: `Ourin/ExternalServer/`）。
- **HTTPBridge**: `/api/sstp/v1` への POST を受け取り、SSTP として解釈する簡易 HTTP ブリッジです。
- **SSTPParser**: ヘッダーや追加データを解析し `SSTPRequest` 構造体へ変換します。
- **SSTPDispatcher**: メソッドに応じて SHIORI などの処理へ振り分け、応答ヘッダーを組み立てます。
- **DirectSSTPXPC**: XPC 経由で SSTP を送受信するためのサービスです。`executeSSTP` メソッドで SSTP 文字列をやり取りします。
- **EncodingAdapter**: UTF‑8 を既定としつつ CP932 系のラベルも受け付ける文字コード変換ユーティリティです。
- **GhostRegistry**: ゴースト名からパスを解決する簡易レジストリです。
- **BridgeToSHIORI**: SHIORI パイプラインへ橋渡しするスタブ実装です。

各モジュールの詳細や仕様は `docs/SSTP_1.xM_SPEC.md` を参照してください。
