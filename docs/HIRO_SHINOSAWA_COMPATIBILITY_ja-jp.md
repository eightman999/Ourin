# 「篠澤さん」互換性確認

対象: 利用者指定の `HiroShinosawa.nar`、SHA256 `eeff4e64cfc96dad292e090b4144c3c2251508f18907f9419e3c4c8e25f48bef`。2026-10-28に一時環境で検証。元NAR・辞書・シェルの書き換えによる回避はしない。

## Ourin側の修正

- `surface.append0-9,11-20` の範囲・除外指定を解析する。
- MAYUNAのbindgroup、addid、番号なしbindoption.groupのmustselectを処理し、標準着せ替えを合成する。表情変更後も選択中の服・髪を再適用する。
- PNGの印刷用DPIに左右されず、画像のピクセル寸法と明示的な@2x/@3x指定でシェルの大きさを決める。このNARでは頭・髪・ピンが350DPI、服が72DPIであり、従来はパーツ間の寸法が一致しなかった。
- SERIKO実行器とタイマーをscope別に分け、表情の最終フレームを明示消去まで保持する。周期アニメーションは一周後に待機へ戻し、待機中も時計を維持する。先頭が待ち時間0の周期画像は初期表示に反映する。
- NAR付属バルーンを共有balloonディレクトリへ通常インストールし、メニューから選択できる。UTF-8/BOM/旧Shift_JISの名前を読み、明示選択をゴーストごとに保存する。

## 描画負荷

ユーザーの重さ報告を受け、画像再読込・element再合成を64MiB/128枚上限のキャッシュへ変更。同じ描画入力をSwiftUIが再評価する場合も合成済み画像を再利用する。画像・PNA・Retina variantのmtime/size、scope、透過モード、element定義をキーに含めて変更を反映する。

CPU合成は層ごとの配列コピーを除去し、描画範囲外と透明画素を省略する。旧実装との744ケース229152バイト一致を確認。元Hiroの421×399・9層の同一バイナリ比較は、最適化ありで3.163→0.788ms、最適化なしで111.97→38.79ms。同じ入力の再利用は最適化ありで0.000157ms/回。これは単体描画計測で、アプリ操作全体のフレーム時間ではない。証跡: `/tmp/ourin-blend-perf-20261028/benchmark-optimized.log`。

実アプリの追加計測では、一度の10秒窓で約584% CPUを検出して停止した。sampleでSatoriAdapterの終了済みstderr監視が複数coreを占有していると確定。元Satoriの条件付き候補選択がstdoutへ `selecting` とCP932候補を出し、JSONL破損→helper再起動→EOF監視残留を繰り返していた。Ourin所有のhelper境界で通常stdoutをstderrへ分離し、応答だけを専用fdへ出す。Swift側もEOF/終了/再起動で監視を解除する。

修正後の実helperでwheel/tick42応答が同一PID・全JSON正常・正常終了。診断はstderrに届くことも確認した（`raw-ipc-fixed.json`）。XcodeのHiro5件＋stderr lifecycle3件はPASS（`xcode-satori-ipc.log`）。高負荷版は停止し、最終実アプリ負荷は別途再計測する。

InputMonitorのglobal mouse/scroll監視も、他アプリの操作をscope0のOnMouseMove/OnMouseWheelへ誤配送していた。global監視は入退場判定に限定し、通常mouseイベントはlocalのghost/balloon窓へ限定する。キーボード、ghost窓のドラッグ・クリック経路は保持する。

上記入力の回帰、当たり判定、Satoriのtimeout復旧を含む23件/3suiteがPASS（`xcode-input-runtime.log`）。専用stderr監視テスト、Hiroの実wheel/tick、入力配送判定を別々に確認した。

最終Release buildはカバレッジを明示無効化して成功（`build-release-final.log`）。一時インストール先から起動し、元OnBoot応答、共有「篠澤バルーン」の保存済み選択の復元、helper通信エラーなしを確認。起動後10秒のCPU時間差は0.15秒、平均約1.50%（`release-cpu-final.json`）。まばたき周期があるため、この短い窓の値を長時間平均や全操作の負荷保証とはしない。

最終GUIの自動取得はタイムアウトし、実画面の最終スクリーンショット・体感操作の再確認は未完。描画テスト・実プロセス応答・CPU計測を区別する。検証用起動スクリプトは `/tmp/ourin-hiro-20261028/篠澤さんを起動.command`。利用者の通常保存先へは設置していない。

## 元データと実エンジン

同梱Satoriの通常Factory経路で元CP932辞書を読み、初回・通常起動、会話、終了、別helperでの保存再読込を確認する。昼の「こんにちは。」は元辞書の正規応答。Windowsのsatori.dllをmacOSで直接実行する方式ではない。

標準着せ替えはanimation ID `2001/2101/2201/3110/4000`。元画像の421×399ピクセルで頭・髪・体・ピンを合成し、パーツを除いた画像との差分と表情変更後の再合成を確認する。

付属の `install.txt` にある `balloon.directory` はインストール先の指定。推奨バルーン指定とは解釈せず、右クリックのバルーンメニューで「篠澤バルーン」を選ぶ。

## 検証記録

衣装・DPI・共有バルーン・Status・SERIKO/overlayを含むXcodeの82件/8suiteがPASS（`xcode-hiro2.log`）。追加の描画・性能・hit test・キャッシュ・SERIKO検証は96件中95件PASS、Retina環境のfixtureが想定したPNGピクセル寸法と異なる1件を修正し、単独再実行PASS（`xcode-initial-pixels.log`）。全96件を一括成功とは扱わない。

Hiroの最終5件は `xcode-hiro-diagnostic.log` でPASS。着せ替えmustselect拒否後、顔表示後、まばたき完了後のすべてで静的5層・元画像ピクセルの保持・合成の非透明96514ピクセルを確認。scope1へ切り替えた間もscope0の顔を更新し、scope0の明示停止がscope1の同番号animationへ影響しないことを確認した。

元NARのSHA256一致、元165ファイルの全ハッシュ一致は `integrity.json` に記録。エンジン単体の証跡は `/tmp/ourin-hiro-satori-20261028/summary.json`、描画の証跡は `/tmp/ourin-hiro-dressup-20261028/`、Xcodeのログは `/tmp/ourin-shiori-phase5-20261028/`。

## 残る範囲

専用SAORIテストメニューから呼ぶ `fill_desktop.dll` の画面全体の色変更は未移植・未実行。通常の起動・会話とは区別する。全辞書分岐、長時間動作、Intel実機、古いmacOSでの確認は未完。利用者の既存ghost保存先は変更していない。
