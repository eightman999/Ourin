# shiorigo / Gohst の macOS SHIOLINK 接続

記事にある [Narazaka/shiorigo](https://github.com/Narazaka/shiorigo) の実parser/builderと、記事からリンクされる実ゴースト [kurousada/gohst](https://github.com/kurousada/gohst) のイベント処理をmacOSで実行します。

```sh
python3 engines/shiorigo/build.py
```

Go 1.27.2を既存の `/opt/homebrew/bin/go` から使用します。別パスは `--go /absolute/path/to/go`。このスクリプトはGoをインストールせず、異なる版では停止します。Go版・実compiler hash・ソースhashを `BUILD.json` へ記録します。上流2アーカイブは `UPSTREAM.json` にrevisionとSHA256を固定しています。取得済みアーカイブには `--shiorigo-archive` と `--gohst-archive` を指定できます。

外部Go依存は固定したshiorigoだけです。上流の古いリポジトリにはgo.modが無いため、一時ビルドディレクトリへmodule宣言とローカルreplaceを作ります。`GOPROXY=off`、`GOSUMDB=off`、`GOWORK=off`、`GOENV=off`、`GOTOOLCHAIN=local`、`-mod=readonly` で追加のmodule取得やtoolchain更新を行いません。Cgoも使用しません。

Gohstの `internal/requesthandlers/requesthandlers.go` とshiorigoの `shiori.go` はバイト単位で保持します。Windows/cgo DLLエントリポイントとWin32ログ出力だけを新しいSHIOLINKホストへ置き換え、OnLoad/OnRequest/OnUnloadは実上流を呼び出します。桜スクリプト、ランダム会話の閾値・状態・分岐を変更しません。元の画像・NAR・Windows辞書は変更しません。

出力は `build/engines/shiorigo/gohst-shiolink`。試験用コピーの `ghost/master/descript.txt` に `shiori,SHIOLINK.dll` を指定し、同じ場所に次の `SHIOLINK.ourin.ini` を置きます。

```ini
[SHIOLINK]
executable=/absolute/path/to/build/engines/shiorigo/gohst-shiolink
arguments=[]
charmode=UTF-8
```

Gohstの上流OnUnloadには保存処理がありません。今回も保存拡張は追加しておらず、終了後の再起動では上流どおり会話counterが初期化されます。これはsave/reload互換の確認済みを意味しません。独自のGoゴーストで永続化が必要な場合は、そのゴーストのロード・終了処理として実装します。

`GoShioriEngineTests` は本番Factory / ShiolinkAdapterから実processを起動し、上流の日本語OnBoot/OnClose、version/name、NOTIFY、会話counterの初期区間、終了と子process回収、再起動を確認します。未ビルド時は明示的にskipします。出力パスを変えた場合は `OURIN_GO_SHIORI_EXECUTABLE` を指定できます。

コード側のGohst MIT全文、GoのBSD全文、shiorigoの上流MIT宣言を出力へ保存します。shiorigoの宣言は外部サイトのMIT本文へのリンクであり、全文の取得・再配布監査済みとは扱いません。Gohstのシェル画像には別著作者と別ライセンスがあるため、ビルド成果物へ含めません。アプリへの自動同梱も追加していません。
