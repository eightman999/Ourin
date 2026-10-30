# 掲載SHIORIへの対応・続行記録

確認日: 2026-10-26。既存のSHIOLINK／Native接続に対する追加実装。全16種類の移植・全配布ゴーストの互換性完了ではない。[全種類の状況](ADVENT_2023_SHIORI_COMPATIBILITY_ja-jp.md)。

## 変更

- **KAGARI**: 固定Lanes 3.17.2をUniversal 2へ静的リンクし、MIT本文を同梱。LuaSocket MIMEも同梱し、ゴースト内へ追加 `.so` を配置しない通常アプリ構成で動作させた。Lanesの新しい `internal_allocator` を省略する古いLua wrapperでNULL参照が起こるため、native側で従来のallocatorを既定値とした。worker stateへ作成元ghostの仮想cwdとnative preloadを継承する。host processのcwdは変更しない。
- **初回描画**: 従来は画像ロード成功後に初めてsurfaces.txtを解析していた。element定義だけのsurfaceはその画像をロードできず、キャラクターを表示できなかった。画像読込時のローカル定義snapshotで初回合成するよう変更し、animation cacheへの背景threadからの書込を増やしていない。配布シェルは変更していない。
- **言語通知**: 日本語macOSでReference0が「日本語」となり、`Japanese` を辞書キーとするゴーストの終了トークがエラーになった。OnLanguageChangeの言語名を表示localeによらない英語名に統一。起動時のNOTIFYと4つのReference列は保持する。
- **cshiori**: 固定上流の実SHIOLINKサンプルをmacOS向けにコンパイルする導線を追加。getline衝突と上流サンプルの借用文字列をfreeするクラッシュをentrypoint側で修正。CP932のイベント本文を保持。[手順と制限](../engines/cshiori/README.md)。
- **shioridll-nim**: 固定上流を公式Nim 2.2.4で実コンパイル。POSIX公開境界だけmalloc/free／cintへ揃える。refc版はXPCの別thread要求でクラッシュしたためARC＋threadsを明示指定し、別foreign thread回帰を追加。上流basicイベントは未変更。[手順と制限](../engines/shioridll-nim/README.md)。

## 実ゴースト「もす」

原本NARのSHA256は `a663e0a32de13dd28b8b18e7a806f31a764d8e5ead7754f4901dc3838a764688`。一時展開だけを使用し、元NARと辞書ソースを変更しない。

`engines/kagari/verify_kagari_mosu.py` の既定をbundled-onlyへ変更した。従来の追加native依存配置は明示的な `--stage-legacy-dependencies` の診断モードに限定。初期化通知OnInitialize／OnLanguageChangeを実アプリに合わせてからGETイベントを送る。SHIORI 200でValueがあってもErrorLevel／ErrorDescriptionがある応答は成功と数えない。

- 最小辞書、最小辞書の別process再load、load失敗判定: PASS。
- 実辞書の起動・ダブルクリック会話・メニューの30秒→1分変更・終了: PASS。
- `kagari_save.lua`生成、別process再load後に1分設定を保持、終了本文「またね！」: PASS。
- 元NARの実行前後SHA256一致、追加ghost native moduleなし: PASS。
- 実アプリ: 起動トーク「こんにちは！」とキャラクターを画面取得。キャラクターへ実ダブルクリックし、OnMouseDoubleClick送信、`Ouch!`応答とSakuraScript text再生をログ確認。Ourinメニューから正常終了しsavedataを確認。

証拠: `/tmp/ourin-shiori-20261026/mosu-bundled/summary.json`、`gui-app-r2.log`、`gui-base/ghost/mosu/ghost/master/kagari_save.lua`。GUIで触ったのは一時コピー。

## 自動検証

- Xcodeアプリbuild: **BUILD SUCCEEDED**。
- cshiori、KAGARI、SHIOLINK、言語通知、初回element画像、surface blend: 33固有test PASS。初回まとめ試験のNim 2件は失敗し、原因修正後にNim suiteを再実行した。
- Nim: 上流basicの本番factory／XPC、日本語・絵文字往復、NOTIFY、load先、unload/reload、各要求を新規foreign threadで呼ぶ3件 PASS。
- 同梱Luaモジュール: 10項目 PASS。実Lanes worker／Linda、MIME、相対IO、複数Lua root／KAGARI instance、child spawn cwd、Native SAORI fixture等。
- Windows／Intel実機、全配布ゴースト、全16エンジンは未検証。

ログ: `/tmp/ourin-shiori-20261026/`。Xcodeは `xcode-final-tests.log`（Nim修正前の失敗を保持）、`nim-xpc-final.log`（修正後）。

## 残件

「もす」の追加SAORI `choice` のmacOS版は未導入でload警告が残る。LanesのLuaJIT検出に対するghostの未宣言global `jit` 警告も残るが、検証したライフサイクルのErrorLevel応答はない。HTTP／SSLやネットワークを使うサンプル会話、クリップボード書込は今回試していない。

cshioriとNimは任意でビルドする開発用サンプルで、Ourinへ自動同梱しない。Nim導線はarm64のみ。shioridll上流のMIT宣言・参照先は保存したが、参照先サイトが到達不能で全文取得は未完了。配布準備完了とはしない。

Windows依存のaktk／dktrtk／D.N.Proxy／emo-rs／Kanahebi／krht／phioriなどの個別移植、RosalindのmacOS runtime、Go系実配布ゴーストは引き続き残る。commit／push／公開は行っていない。
