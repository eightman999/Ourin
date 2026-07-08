# 動画レンダラ設計書（STUB_COMPLETION_PLAN Phase 2-4）

作成日: 2026-07-08（deep-reasoner設計、コード実測に基づく）

## 結論（推奨方式）

**AVKit `AVPlayerView` を独立した borderless `NSWindow`（サーフェスウィンドウとは別窓）に載せる方式**を採用する。
サーフェス画像へ合成せず、SSPと同じく「シークバー付き独立ウィンドウ」として表示する。既存のSwiftUIサーフェススタックには一切手を入れない。
エントリポイントはorphanの `playVideo` ではなく、実仕様である `\![sound,play,<動画>,--options]` のディスパッチ分岐（`GhostManager.swift:1811` 付近）に動画拡張子判定を追加する。

## 実測事実

- `playVideo`（`GhostManager+Display.swift:265`）は**呼び出し元ゼロのorphan**。通知先 `.OnVideoPlayEx` は `EventID.swift:409` / `EventReferenceSpec.swift:153` に存在。
- 動画再生の正仕様は `\![sound,play,...]`（`docs/SAKURASCRIPT_FULL_1.0M_PATCHED_ja-jp.md:1907-1912`）。オプション `--volume` `--balance` `--rate` `--window=false/true` `--sound-only=false/true`（同 `:1966-1978`）。
- 現状 `applySoundOptions`（`GhostManager+Display.swift:206-226`）は `--volume` のみ対応。
- サーフェスは透過borderless窓＋`NSHostingView`（SwiftUI `CharacterView`）構成で、レイヤーホスティング非採用。`AVPlayerLayer` の直挿し（案B）はヒットテスト・エフェクトと干渉するため不採用。
- パス解決の注意: 仕様は `ghost/master` 直下解決だが既存 `resolveSoundPath`（`:131`）は `sound/` 固定。動画側は master 基準で解決する（既存サウンド側の乖離はスコープ外、勝手に変えない）。

## 方式比較（要約）

| 方式 | 判定 | 理由 |
|---|---|---|
| A. AVPlayerView 別窓 | ◎ 採用 | 干渉ゼロ・シークバー標準提供・`--window` 仕様に直結 |
| B. AVPlayerLayer をサーフェス窓に合成 | × | NSHostingView と競合、仕様上も不要（動画は独立窓） |
| C. AVSampleBufferDisplayLayer/SpriteKit 自前 | × | オーバーエンジニアリング |

## 実装ステップ（完了条件つき）

1. **`Ourin/Ghost/VideoPlayerWindow.swift`（新規）** — `AVPlayer`+`AVPlayerView` 内包の `NSWindowController`。API: `play(url:loop:soundOnly:showWindow:volume:rate:)` / `pause()` / `resume()` / `stop()`。filename→player辞書で複数管理。`AVPlayerItemDidPlayToEndTime` でloop seek(.zero) / 完了処理。`--sound-only` 時は窓を出さない。
   - 完了条件: オプション解析・パス解決の単体テスト＋ローカルmp4で窓再生・停止・ループ動作。
2. **`GhostManager+Display.swift`** — `playVideo` を実配線に置換（引数拡張可、orphanなので破壊なし）。`isVideoFile(_:)`（mp4/mov/m4v等）追加。masterパス基準。`applySoundOptions` に `--window`/`--sound-only`/`--rate`/`--balance` 追加。
   - 完了条件: `git grep playVideo` で呼び出し元が実在、実映像が出る。
3. **`GhostManager.swift:1811-1848`** — sound分岐で動画拡張子なら `playVideo` へ。`stop`/`pause`/`resume`/`option`/`wait` も動画セッションへフォワード。`wait` に動画残時間を合算。
   - 完了条件: `\![sound,play,test.mp4,--window=true]` 窓再生 / `\![sound,stop]` 停止 / `--sound-only=true` 窓なし音声。
4. **クリーンアップ配線** — ゴースト切替/終了（`GhostManager.swift:728-730`、`stopAllSounds`）で全動画窓クローズ・AVPlayer解放。
   - 完了条件: ゴースト再読込・終了で動画窓が残らない。
5. **テスト** — オプションパーサ・拡張子判定・パス解決の単体テスト（AVPlayer実再生は実機確認へ）。
6. **実機確認** — 動画同梱ゴーストで窓表示・シークバー・ループ・停止・`--sound-only`・z順（ゴースト窓 `.floatingWindow` との重なり）を目視。スクリーンショット確認をもって完了。

## リスク・未確認事項

- 工数目安: 実装1〜1.5日＋検証0.5日。
- z順: 動画窓のwindow level（ゴースト `.floatingWindow`、バルーンは popUpMenu）をどこに置くか要検討。
- 同時再生数の上限（例: 3）を設けるか検討。
- AVFoundation非対応フォーマット（MPEG-1/AVI/WMV等の旧SSP資産）は `.OnVideoPlayEx` 通知＋ログへフォールバックし無音失敗を避ける。対応拡張子ホワイトリストは実装時に確定（未確認）。
- `--sound-only` はload時限定（仕様 `:1978`）。play時に来た場合は厳密互換なら無視（SSP実挙動との突合は未実施）。
- `\![movie]` 系のon-surface合成コマンドはSSP仕様に存在しない。アルファ動画をキャラに重ねる要件が出た場合のみ方式B/C再検討。
