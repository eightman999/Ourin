# phiori macOS SHIOLINK host

Tatakinov/phiori revision `618f29de2c718735ae3bfc6ccceb69ebfca311c7` の実Pythonモジュールを別processで実行する任意ローカルbuild。元Windows DLLを実行するものではない。固定archive SHA256は `UPSTREAM.json`。

```sh
python3 engines/phiori/build.py
```

既存Python 3.14.8 (`/opt/homebrew/bin/python3.14`) を検査し、stdlibだけで実行する。runtimeの自動インストール・アプリ同梱は行わない。別pathは `--python` で指定する。

`build/engines/phiori/upstream-sample` は元example.py/config/resource/wordsを保持する。利用ghostへは実phiori Python packageが必要。hostはghost/masterの外へ置く（上流が同ディレクトリの全*.pyを辞書として実行するため）。元descriptの `shiori,phiori.dll` を維持し、そのDLLと同じ場所へ `SHIOLINK.ourin.ini` を追加する。

```ini
[SHIOLINK]
module=phiori.dll
executable=/opt/homebrew/bin/python3.14
arguments=["-I","-u","/absolute/path/build/engines/phiori/phiori-shiolink.py"]
charmode=UTF-8
```

upstream frameworkの変更は、ownerghostname未受信で終了する際にtemp personaを正しく片付ける1行だけ。例外の出力をstderrへ送り、通信stdoutと分離する。Windows C wrapperの所有権問題を引き継がず、実Pythonのload/request/unloadを直接呼ぶ。

`PhioriEngineTests` は本番Factoryで元DLL名からhostを選択し、元exampleのOnBoot/OnClose/NOTIFY、自作callbackの日本語・絵文字、variable.datのcounter保存1→2を検証する。配布ghost全体、Windows DLL、追加native SAORIは未検証。

上流READMEはPython MIT/C DLL LGPL3、COPYING.txtはGPL3+を宣言している。3 noticesとREADMEを出力へ保存する。権利関係を解決した再配布物とは扱わない。
