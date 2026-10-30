# SHIORI対応・残件の続行第5部

2026-10-28。[前回](SHIORI_CONTINUATION_2026-10-28_PART4.md)／[全体表](ADVENT_2023_SHIORI_COMPATIBILITY_ja-jp.md)。利用者指定の実NAR「篠澤さん」への対応は[個別記録](HIRO_SHINOSAWA_COMPATIBILITY_ja-jp.md)を参照。

## 任意ローカルエンジンの追加確認

- **dktrtk**: UTF-8 sourceのmain/includeを検証し、CP932 sourceの黙った文字化けを明示拒否へ変更。実SHIORI要求と応答は `--wire-charset CP932` で変換する。旧x86 SDK・ARM64 SDK双方で日本語path、表/ソ、半角カナ、CP932拡張、NOTIFY、保存再loadを確認。表現不能なemoji要求/応答は拒否する。sourceのCP932対応とwireのCP932対応は区別する。
- **krht**: x86_64別成果物を追加。Rosetta上の実Intel process、Tcl patchlevel/machine、日本語pathへのruntime移動、会話、保存再load、不完全要求EOFでのunloadを確認。Intel実機は未確認。
- **shioridll-nim**: arm64/x86_64/Universal2別成果物を追加。本番Nativeローダーを両architectureでbuildし、実Rosetta実行とUniversal2両sliceで会話、foreign pthread、並行instance、NOTIFY、unload/reloadを確認。ARC/thread/TLS修正を維持する。実Factory/XPCのUniversal2接続も対象試験へ追加。

上記3suiteは `/tmp/ourin-shiori-phase5-20261028/xcode-runtime.log` でPASS。これは同じbatchのBalloon/Status UI失敗を含む全体成功の意味ではない。失敗を修正した再実行結果は後述する。各エンジンのREADME、依存lock、ライセンス境界を維持する。

## Ourin側の追加実装

**Statusの実UI状態**: choosing/minimizing/opening/balloonを追加。受信ghostが所有する実際に見えているwindowと選択肢を参照し、予約中の選択肢・非表示window・他ghostのwindowを含めない。input/communicate/teach/system dialogを区別し、共有color panelの所有者を移す。判定のためにwindowやVMを新規作成しない。

**共有バルーン**: folder/name/相対pathで選択し、既存hosting viewへ画像と設定を反映する。選択はghostごとのschema 1設定として相対pathで保存する。base移動、folder改名、削除済み・不正・未来schemaを扱う。UTF-8/BOM/旧Shift_JISのdescriptor名を検証する。推奨バルーン不一致の強い警告UIは未実装。

**実シェル描画・性能**: HiroのMAYUNA/顔表示で、範囲surface.append、DPI、scope間executor干渉、最終画像消去、周期アニメーションの無限反復を修正。依存画像キャッシュと合成結果の再利用、ピクセル合成の高速化を追加。元画像・辞書は保持する。仕様・計測は[個別記録](HIRO_SHINOSAWA_COMPATIBILITY_ja-jp.md)を参照。

**Satori IPC/終了監視**: 元Familyの条件付き選択診断がstdoutへ混ざり、wheel処理でJSON decode失敗とhelper recoveryを連発していた。Own helper境界で診断をstderrへ分離し、専用fdに応答だけを送る。stderrのEOF監視が残ってcoreを回し続ける問題も修正。元ghost書換えやSwift側の不正行読み飛ばしで回避しない。元Hiro wheel/tick42応答を同一helperで確認し、関連8件PASS。

## 証跡と制約

共有バルーン9件、Hiro4件、Status header/UI、SERIKO parser/executor、overlayの計82件/8suiteがPASS（`xcode-hiro2.log`、skip 0）。最初の共有選択のpath比較、root探索の停止、Status UI試験のwindow作成順を修正後に確認した。

顔/周期/性能の追加では、96件中95件PASS後、Retina依存だった画像fixtureを明示ピクセル寸法へ直して残る1件を単独PASS。Hiroの最終5件も単独PASSし、顔・静的衣装の同時保持を各段階で検証した。全体の並列完走とは区別する。ログ: `xcode-hiro-performance2.log`、`xcode-initial-pixels.log`、`xcode-hiro-diagnostic.log`。

ログ: `/tmp/ourin-shiori-phase5-20261028/`。dktrtk: `/tmp/ourin-dktrtk-cp932-20261028/`。Hiro: `/tmp/ourin-hiro-satori-20261028/`、`/tmp/ourin-hiro-dressup-20261028/`、`/tmp/ourin-hiro-20261028/`。

全suiteの並列完走、全third-party辞書、Intel実機、古いmacOSの実行、Windows固有APIは引き続き未検証。commit/pushは実行していない。
