# MiyoJS・SanaJK・Sana・phiori エンジンプラグイン

上流の実エンジンと実行環境をまとめた、ローカル導入用のSHIORIプラグインです。利用者のMacにNode.js・Ruby・PythonやHomebrewを要求しません。アプリへの自動同梱、プラグインの外部公開は行いません。

```sh
python3 engines/miyojs/build.py
python3 engines/package-script-engines.py --destination build/engines/script-plugins
python3 engines/miyojs/verify_plugins.py build/engines/script-plugins
```

`miyojs/`・`sanajk/`・`sana/`・`phiori/`はそれぞれ独立した出力です。各ディレクトリにlauncher、実エンジン、必要なruntime・ライブラリを含みます。`script-engines-manifest.json`をOurinのプラグインpackagerへ渡します。ビルド側のNode/Ruby/Pythonを選ぶには`--node`・`--ruby`・`--python`を指定できます。

## 固定入力

- MiyoJS 2.0.3: [上流](https://github.com/Narazaka/miyojs)、revisionとnpm artifactのSHA256は`UPSTREAM.json`。
- SanaJK 1.0.6、SHIOLINKJS 3.1.3: npmの全依存を`package-lock.json`のversion/integrityで固定。MiyoJSは実際に要求する旧ShioriJK/SHIOLINKJSを別途保持します。
- MiyoJSの`safeLoad` APIに合わせ、js-yamlは3.14.2へ固定。エンジン本体のYAML処理を別実装へ置換しません。
- Sana 0.0.4・shiolink 0.0.2・shioruby 0.0.3・ostruct 0.6.3: `RUBY_GEMS.json`に取得URLとSHA256。インストールhookを実行せず、純Rubyの実パッケージを展開します。
- phiori: 既存`engines/phiori/UPSTREAM.json`と同じ実moduleを使用します。元配布の`phiori/builtins`とPython辞書を保持します。

`npm ci --ignore-scripts`はビルド時だけに実行します。エンドユーザー起動時のnpm/gem取得はありません。npmのライセンス本文・README、Node配布の依存通知、Ruby/Pythonの通知を成果物へ保持します。phioriの上流ライセンス表記の不一致は既存READMEの通り未解決で、manifestは`unconfirmed`です。ローカル導入を確認したことは、全コンポーネントの再配布審査を終えたことを意味しません。

## 接続と元データの保持

launcherは`bin/<id>`、transportはSHIOLINK UTF-8です。元`SHIOLINK.INI`のWindows commandlineをデータとして読み、辞書ディレクトリまたは起動scriptだけを選びます。Windowsの実行ファイルやshell commandを実行しません。引用符付きの空白・日本語パス、backslashを扱い、実体がghostのload先から外へ出るscriptを拒否します。追加の引数はshellを介さず渡します。

MiyoJSは`miyo.yaml`または`node_modules/miyojs`、SanaJKは`node_modules/sanajk`、Sanaは`main.rb`等の既知マーカーかcommand hintで識別します。SanaJK/Sanaのscript名は元設定から読み、設定がない場合だけ`main.js/index.js`、`main.rb/index.rb`を順に使用します。元descriptor、辞書、Windows INIを書き換えません。

MiyoJSの旧上流entryはpipeのchunkを完結した行として扱うため、Ourinの`host.js`が完全な行を直列に上流SHIOLINK parserへ渡します。実MiyoJS・旧SHIOLINK parser・辞書の処理は保持します。未定義イベントに400を返す挙動も上流仕様のままです。fixtureのNOTIFYイベントは明示した空値により204を返します。

Rubyは同梱stdlib/gemだけをLOAD_PATHに設定し、Pythonは同梱stdlibと`PYTHONNOUSERSITE=1`を使います。Homebrew Pythonの起動stubは使わず、実Python.app executableを移して再exec先の外部参照を除去します。Mach-Oの非system dylibをプラグイン内へコピーし、loader相対参照へ変更、ローカル署名します。各`runtime/RUNTIME.json`に元実行ファイルと成果物のSHA256を記録します。

## 確認済み範囲と制限

2026-10-29のstageは全4種とも**arm64**です。Node 26.8.1のMiyoJS/SanaJKは**macOS 13.5以降**、Ruby 4.0.7のSanaとPython 3.14.8のphioriは**macOS 26.0以降**のruntimeを使います。実Mach-Oからarchitectureと最低OSを取得してmanifestへ書きます。Intel・古いmacOS向けのruntimeはこの成果物に含みません。

4エンジンそれぞれ2回の別process起動、Unicode、日本語・emoji応答、NOTIFY、保存・再loadがPASS。MiyoJS/SanaJK/Sanaは元Windows形式の設定から引用符付き日本語entryを選択し、MiyoJSは3バイトずつ分割したUTF-8要求も確認しました。PATHを`/usr/bin:/bin`に限定し、実dyldのruntimeパスがログへ出ることを確認した上で、Homebrewからのdylibロードがないことを検証します。`OURIN_VERIFY_DYLD=1`はこの試験用診断です。

phioriの初回起動ではmacOSの署名検証に約25秒待つケースを観測しました。manifestの`launchTimeout=60`は初期ロードの期限にだけ適用し、通常要求の期限と区別します。warm後の実応答は上記試験で確認しています。

Swiftの本番factory/adapter試験は`MiyoJSEngineTests`、プラグイン導入を経由する共通試験はroot側のsuiteを使用します。Sana/SanaJKのfixtureは`fixtures/sana/main.rb`・`fixtures/sanajk/main.js`。phioriは`build/engines/phiori/upstream-sample`のコピーに`fixtures/phiori/probe.py`を追加します。fixtureと第三者配布ゴーストの確認は別です。任意の外部import・Windows API・全配布ゴーストの互換性は未確認です。
