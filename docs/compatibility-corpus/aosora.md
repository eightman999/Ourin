# Aosoraの任意導入と実ゴースト検証

確認日: 2026-10-25。従来ロードできなかったAosora製ゴースト2件で、macOS arm64上のロード・起動応答・終了・再ロードを確認しました。公開版Ourinへの同梱を意味しません。

## 導入方法と範囲

[Aosora上流](https://github.com/kanadelab/aosora-shiori/tree/b9f6641c58ca4bfdaa775960e4b666c7282339db)を固定し、利用者が別途用意したmacOSライブラリを読み込む経路を追加しました。`aosora.dll`というゴースト側の指定を認識し、`OURIN_AOSORA_ENGINE`で明示したライブラリへ接続します。元のWindows DLLやゴースト辞書は書き換えません。

上流の[利用条件](https://github.com/kanadelab/aosora-shiori/blob/b9f6641c58ca4bfdaa775960e4b666c7282339db/license.txt)には、配布DLLとソースコードで異なる条件が記載されています。ソースから作成したライブラリの再配布許諾は確認していないため、Ourinの通常ビルド・配布パッケージには含めません。以下は上流条件を確認したうえでの個人利用ビルド用です。

```sh
python3 engines/aosora/build.py --output build/engines/aosora
OURIN_AOSORA_ENGINE="$PWD/build/engines/aosora/libaosora.dylib" \
  /path/to/Ourin.app/Contents/MacOS/Ourin
```

上流ソースはビルド時だけ一時取得し、固定SHA-256と照合してからコンパイルします。生成先にはABI指定、依存元情報、利用条件のファイルを残します。Finderからの通常起動へ環境変数が引き継がれることは保証しません。

## 実配布物の結果

|作品|配布元・ダウンロード|確認できた範囲|残件|
|---|---|---|---|
|doll_at_the_bay_window|[作者release・NAR](https://github.com/tukinami/doll_at_the_bay_window/releases/tag/v1.0.0)|load → OnBoot → OnClose → unload → 再loadを2周。起動・終了のScript応答あり|OnAITalkは204、会話網羅・実画面・既存保存データ移行は未検証|
|mancala-board-ghost|[作者release](https://github.com/lost-nd-xxx/mancala-board-ghost/releases/tag/v1.0.1) · [NAR](https://github.com/lost-nd-xxx/mancala-board-ghost/releases/download/v1.0.1/mancala-board-ghost.nar)|load → OnBoot → OnClose → unload → 再loadを2周。起動・終了のScript応答あり|OnAITalkは204、マンカラの操作・対局・実画面は未検証|

2件ともネットワークを禁止した使い捨てコピーで実ライブラリを呼び出しました。検証後のダウンロード・展開データは削除済みです。初回コーパスの`unsupported`に対する追加結果として記録し、会話用の共通probeが204のため総合分類は`partial`とします。再ロード成功だけで保存データの内容互換を保証しません。

## ABIと失敗処理

POSIX側の`aosora_load`はCの`long`型のインスタンスIDを返し、失敗値は0です。この幅と所有権を明示したABIを追加しました。構文エラーなどの起動失敗は、ロード成功として扱いません。

`doll_at_the_bay_window`の追加検証では、HTTP 200でも`ErrorLevel: error`を返す起動失敗を検出しました。上流VMのroot frameでループ・例外処理の状態が未初期化だったため、クラス宣言後の関数が登録されない最小入力でも再現しました。固定ソースのビルド時に3フィールドを初期化し、元辞書を変えずに修正しています。検証probeもステータス番号だけでなくErrorLevelを確認します。

上流のプロセス共通状態を保護するため、同一プロセス内の二重ロードを拒否します。通常の分離実行では既存のSHIORI XPC経路を使います。アンロード時には保存処理を実行してからインスタンスを解放します。

取得元・アーカイブhash・イベント別結果・制限は[検証結果JSON](aosora-results.json)を参照してください。Intel実機、GUI全操作、外部SAORIは今回の成功範囲に含めません。


## 回帰検証

実エンジンの7回帰で、既存保存値19→37の変更と再読込、無効・欠落辞書の拒否、同一プロセスの二重ロード拒否、クラス宣言後の関数登録、200応答の内部エラー検出を確認しました。応答分類の2回帰ではerrorとwarningを区別しています。

Ourinの関連8 suite・118集計テスト/154実行が成功し、修正版ライブラリに差し替えた後もAosoraの3テスト/5実行を再実行して成功しました。in-process、実XPC、通常factory経由、保存再ロードを含みます。いずれも失敗0・SKIP 0です。
