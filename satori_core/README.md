# satori_core

Ourin用のSATORI helperです。固定した`ukatech/satoriya-shiori`をプロセス内へ静的リンクし、Swift側とはUTF-8 JSON Lines、SATORIとはCP932 SHIORI wireで通信します。

## Build

```bash
./build.sh
```

生成物は`build/satori_core`です。macOS 11以降向けの`arm64/x86_64` Universal 2としてビルドします。CMake 3.20以上とnlohmann/json 3.11以上が必要です。iconvはmacOSのシステムライブラリを使用します。

## Commands

- `ping`: helper疎通確認
- `load`: ghost rootをロードし、SHIORI probeまで成功した場合のみ成功
- `request`: `method`、`id`、`headers`、`ref`をSATORIへ送信
- `unload`: SATORIの終了処理とsavedata保存を完了

stdoutはJSON Lines専用、上流の診断出力はstderrです。1 helper processを1ゴーストへ割り当てます。

上流情報とローカル変更は[UPSTREAM.md](UPSTREAM.md)と[PATCHES.md](PATCHES.md)を参照してください。
