# krht POSIX / SHIOLINK 移植記録

対象: `kinokon/krht` revision `bdfba1fb72e05342b35adbdd9c354c181e6f6729`。

`build.py` は検証したアーカイブの `krht/dllmain.cpp` からload/unload/requestの実処理を取り出します。Win32 DLL entryと文字コード変換helperは子プロセス方式に不要なため取り込みません。上流の `_request` / `_unload` 呼出しと文字列 `true` によるロード・終了判定を維持します。

- HGLOBAL/GlobalAlloc/GlobalFreeを、子プロセス内のmalloc/free互換へ対応。BOOLをint32、lengthをC longに対応します。
- SetCurrentDirectoryを子プロセス内のchdirへ置換。Ourin本体のcwdは変更しません。
- Tcl_FindExecutable/Tcl_Initで実Tcl runtimeを初期化します。macOSと同じthread内でinterpreterを作成・要求・削除し、threadをまたいで使用しません。
- index.tclのsourceとロードcallbackのTcl評価失敗を検査します。元コードはエラーを無視していたため、不正sourceを有効なロードとみなしません。
- Tcl_EvalObjvへ渡すTcl_Objのreferenceを取得し、評価後に解放します。元の要求電文や辞書の返却本文は変更しません。
- 通常requestのTcl評価失敗は500応答へ写像します。
- 元requestの出力lengthはNUL終端を含みます。SHIOLINKの電文出力では最後のC終端だけを除き、応答本文は変更しません。

上流にTcl辞書例は存在しません。自作辞書は上流が実際に行う `_request(directory)` 初期化契約に従っています。その事実を第三者ゴースト互換の証明と扱いません。上流のライセンスも未確認なので、このコード取得・移植は任意のローカルビルドのみです。

2026-10-26、Tcl 9.1.0をリンクした実子プロセスを本番ShiolinkAdapterへ接続し、日本語OnBoot、絵文字echo、NOTIFY、Tclのcounter保存・再load（2 lifecycle）、子プロセス回収、不正sourceのロード失敗を確認しました。

2026-10-28: 固定Tcl sourceの静的buildと隣接script directoryを標準にし、Homebrew/macOS26専用依存を解消。hostのRAII cleanupで正常終了・途中EOF・異常終了経路にも実_unload/Finalizeを適用し、入力行も1 MiBへ制限しました。辞書の変更はありません。

2026-10-28 architecture追加: `--arch arm64/x86_64` をTcl configureのhost/build、CFLAGS/LDFLAGS、およびC++ hostへ適用します。既存のdefaultはPythonの実行architectureです。source build後のMach-O sliceを検査し、既存Tclを使う場合もrequested sliceの存在を確認します。BUILD.jsonへarchitectureとcompiler/SDKを記録します。実interpreterのload/request/unload処理は変更していません。自作検証辞書に実Tclのarchitecture/patchlevelを返すOnArchitectureを追加しました。arm64 nativeとx86_64 Rosettaで移動runtime・会話・保存再load・途中EOF cleanupを実行し、Intel実機や古いOSの未検証範囲はREADMEへ区別しています。
