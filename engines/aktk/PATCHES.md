# aktk POSIX / SHIOLINK 移植差分

固定対象: `kinokon/aktk` revision `64db7ffe61908ad4ac53dcfb76f98b829fdcd84a`。

`build.py` はSHA256検証済みアーカイブの `aktk/dllmain.cpp` から、上流のload/unload/request実処理を取り込みます。Win32のDllMainとUnicode変換helperは子process方式には不要なため取り込みません。以下の変更は一時コピーのengine側に適用し、各置換が固定sourceへ1か所だけ一致することを確認します。

- Windows HGLOBAL / GlobalAlloc / GlobalFreeをprocess内のmalloc/freeへ、BOOLをint32へ対応。
- SetCurrentDirectoryを子process内のchdirへ対応。本体processのcwdは変更しません。
- fopen_sをPOSIX fopenへ変更し、index.rbが無い場合のnull FILE参照を防ぎます。
- source評価と `_load` のmruby exceptionを検査し、不正辞書を成功ロードとみなしません。
- 上流unloadは `_unload` の戻り値からretを計算しても、最後に常時falseを返す実装でした。実際のretを返すよう修正し、mruby stateを解放します。独立process試験で `_unload=true` の正常終了0と、falseの終了4を確認しました。
- 上流requestは例外・型を検査せずRSTRING_PTRへ進む実装でした。Ruby例外または非String戻り値を500応答へ写像し、exceptionを解除して次の要求を実行可能にします。
- requestのGC arenaを保存し、応答をC++ stringへコピーした後に復元します。要求ごとの一時mruby objectを無限にarenaへ保持しません。
- 元requestが返すlengthには終端NULが含まれるため、SHIOLINKへ出す際に最後のC終端だけを除きます。スクリプト本文を変更しません。

`_load` / `_request` / `_unload` の呼出名・引数・Rubyの真偽値評価は維持します。上流Ruby辞書は存在しないため、互換性検証用の辞書は自作と明示しています。

2026-10-26、固定mruby 3.4.0の実SDKをビルドしてaktkへ静的リンク。本番ShiolinkAdapterとの独立Swift probeで2 lifecycleの日本語・絵文字・NOTIFY・例外処理・型不一致処理・その後の継続・保存・再load・子process回収・不正sourceのロード失敗を確認しました。アーカイブhash不一致の拒否も確認しました。
