
# OurinShioriMacBridge — Samples

最小の **SHIORI イベント橋渡し**スケルトン（Swift, AppKit）。  
- キー/マウス/スクロール監視
- ドラッグ＆ドロップ（Text/URL/File）
- 画面構成変化・Spaces 変更（M‑Add）
- 電源通知（IOKit）・ロケール変更・外観変更（M‑Add）

**Target:** macOS 10.15+

## ビルド
- Xcode 15+ で macOS AppKit アプリを新規作成し、`samples/OurinShioriMacBridge` のファイルを組み込む。
- IOKit Power Sources を使うために **Objective‑C ブリッジヘッダ**を追加（`Bridging-Header.h`）。

## 実行
イベント発火時に `ShioriDispatcher.sendNotify(...)` 相当が呼ばれます（本サンプルではコンソール出力）。
