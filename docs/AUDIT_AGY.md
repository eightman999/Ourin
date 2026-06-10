# Ourin (桜鈴) プロジェクト監査レポート

**監査日時**: 2026-06-10
**対象リポジトリ**: `/Users/eightman/Desktop/software_develop/Ourin`
**監査基準**: UKADOC、YAYA仕様、Crowリファレンス、SSP 2.8.27f 挙動

---

## A. SHIORI プロトコル

### 準拠度スコア: 8/10

### 実装済み（仕様準拠）
- **SHIORI/3.0 基本フォーマット**: リクエスト/レスポンスのパーサーとビルダ、ヘッダの展開。 → `Ourin/USL/ShioriLoader.swift`
- **GET/NOTIFY メソッド**: 基本的な情報要求と通知イベントの呼び出し機能。 → `Ourin/USL/ShioriLoader.swift`

### 実装済み（要修正）
- **Charset処理（Shift_JIS ↔ UTF-8変換）**: 現在の実装では `String(contentsOf: url, encoding: .shiftJIS)` による単純フォールバックに依存している箇所がある。Windows-31J（CP932）特有の波ダッシュ（〜）などの機種依存文字でパースエラーや文字化けが発生する可能性が高い。
  - 根拠: UKADOC SHIORI 3.0仕様におけるCharsetヘッダの振る舞い。
  - 修正案: `CFStringConvertEncodingToNSStringEncoding(CFStringConvertWindowsCodepageToNSStringEncoding(932))` 等を使用し、厳密なCP932/Windows-31Jマッピングを行う拡張Stringイニシャライザを実装する。
- **SecurityLevel ヘッダ**: パースはされているが、ローカル／外部のリクエスト判定として十分に機能していない（常に "local" 扱いされる、または未検証）。
  - 修正箇所: `Ourin/USL/ShioriLoader.swift`
  - 修正案: SSTP等外部由来のイベントに対するSecurityLevelの引き下げを厳格に適用する。

### 未実装（重要度: 中）
- **TEACH メソッド**: UKADOC規定の学習・ユーザー入力返却メソッドが未実装または不完全。
- **SHIORI 2.x 互換レイヤー**: 古いゴーストで必要な2.x形式のリクエスト・レスポンスのフォールバック処理。

### 互換性リスク
- **プラットフォーム非依存ヘッダ**: Sender等でSSPが送る特定の文字列に依存して動作を分岐する古いゴーストが存在するため、互換性オプションとしてSender名を偽装できる機能が望ましい。

---

## B. SSTP プロトコル

### 準拠度スコア: 8/10

### 実装済み（仕様準拠）
- **SEND/1.4, NOTIFY/1.1 等のメソッドパース**: `SSTPDispatcher.swift` による基本フォーマットとヘッダ展開の実装。 → `Ourin/SSTP/SSTPDispatcher.swift`
- **レスポンスコード生成**: 200 OK、400 Bad Request 等のステータスコード返却。 → `Ourin/SSTP/SSTPResponse.swift`

### 実装済み（要修正）
- **改行コードの許容範囲**: SSTP仕様上は `\r\n` 区切りだが、一部ツールは `\n` のみを送信してくる。SSPはこれを許容するが、厳格に `\r\n` のみで `components(separatedBy:)` するとパースが壊れる。
  - 根拠: デファクトツール群の送信フォーマットとSSPの寛容な挙動。
  - 修正案: `\r\n` と `\n` の両方をセパレータとして許容する正規表現や Scanner に切り替える。
- **ポートバインディングとSecurity**: 9801ポートを `0.0.0.0` にバインドしている場合、外部ネットワークからの不正なSSTP EXECUTEリクエストを受け付けるリスクがある。
  - 修正案: デフォルトを `127.0.0.1` バインドに限定し、設定で外部公開を許可する形式にする。

### 未実装（重要度: 低）
- **HTTPトランスポート**: SSTP over HTTP (HTTP/1.1 GET/POST への対応) が不足。

### 互換性リスク
- **文字コード自動判定**: リクエストにCharset指定がない場合のShift_JIS推測ロジックの精度。

---

## C. SakuraScript

### 準拠度スコア: 8.5/10

### 実装済み（仕様準拠）
- **スコープ制御 (\0, \1, \p)**、**サーフェス変更 (\s[])**、**ウェイト (\w, \_w)**、**改行 (\n)**。 → `Ourin/SakuraScript/SakuraScriptEngine.swift`
- **アニメーション (\![anim,*])**: SERIKOエンジンとの統合による実行。 → `Ourin/Animation/SerikoExecutor.swift`

### 実装済み（要修正）
- **選択肢 (\q) とアンカー (\_a)**: パース自体は実装されているが、マウスクリック時のイベントフック（OnChoiceSelect, OnAnchorSelect）に Reference を渡す際のエスケープ解除ルールがSSPと完全一致していない場合がある。
  - 根拠: UKADOC list_sakura_script.html
  - 修正案: `\q[title,id,arg1,arg2...]` の多重引数の正確な分離とカンマのエスケープ処理を見直す。
- **タイムアウト (\t, \*)**: `\t` によるタイムアウト時間の制御が、メインループのタイマーと正しく同期していない可能性がある。

### 未実装（重要度: 高）
- **ウィンドウ操作・特殊描画系 (\![set,alignment...], \![move,*,*])**: 未実装・あるいはスタブのオプションが多い。
- **インラインの制御構造 (\j, \x)**: イベントの中断やフローの完全リセット。

### 互換性リスク
- **ウェイトの精度**: Windows環境(SSP)のタイマーとmacOS環境のタイマー(CADisplayLink / GCD)のタイミング差異。音楽やアニメと同期させたスクリプトでズレが生じる可能性。

---

## D. SHIORIイベント

### 準拠度スコア: 7/10

### 実装済み（仕様準拠）
- **基本的なシステムイベント**: OnBoot, OnClose, OnFirstBoot, OnMinuteChange, OnSecondChange。 → `Ourin/SHIORIEvents/`

### 実装済み（要修正）
- **マウス・キーボードイベント**: OnMouseClick / OnMouseDoubleClick 等で、Reference1（X座標）やReference2（Y座標）の計算元が、ウィンドウのローカル座標かスクリーンのグローバル座標かという仕様差異。
  - 根拠: UKADOC list_shiori_event.html
  - 修正案: SSPに合わせて「キャラクター領域の左上を原点とするローカル座標」を算出・提供する。
- **OnWindowStateRestore**: macOSのウィンドウ復元モデルとWindowsの最小化/元に戻すの挙動差のマッピング。

### 未実装（重要度: 高）
- **ネットワーク・インストール系イベント**: OnNetworkDnsResolve, OnUpdateCheckComplete, OnNarInstallComplete 等の詳細な引数 (Reference0〜7) マッピング。

### 互換性リスク
- **Referenceの空要素パディング**: ゴーストによっては `Reference6` まで必要とするイベントで、要素が少ない時にSSPがカンマ区切りで空のReferenceを埋める仕様に依存しているものがある。

---

## E. プロパティシステム

### 準拠度スコア: 6/10

### 実装済み（要修正）
- **名前空間カバレッジ**: `sakura.*`, `kerot.*` などの基本プロパティの `\p[]` 参照は可能だが、OS依存のプロパティ（システムバージョン、解像度等）が固定値・スタブのままになっている。
  - 根拠: UKADOC list_propertysystem.html
  - 修正案: macOSの `NSProcessInfo` や `NSScreen` の値を Windows風の文字列（またはそれに準ずる値）に変換して提供する。

### 未実装（重要度: 中）
- **設定ファイルへの書き込み**: `\![set,property,名称,値]` を用いた読み書き可能なプロパティの動的変更と保存機能。

---

## F. YAYA言語VM

### 準拠度スコア: 9.5/10

### 実装済み（仕様準拠）
- **YAYA言語の基本文法・内部関数**: Rust/C++側での完全実装が確認されている。 → `yaya_core/`
- **SHIORI/3.0 インターフェース**: `YayaBackend` 経由でのメモリ・文字列のやり取り。

### 互換性リスク
- **大文字・小文字の区別（Case Sensitivity）**:
  Windowsのファイルシステム（NTFS）は大文字小文字を区別しないため、`dic, Mydic.txt` という指定で `mydic.txt` が読み込める。しかし、macOS（APFS/HFS+）は厳密に区別するため、古いゴーストでファイル名指定のCaseMismatchにより辞書読み込みエラーが多発する。
  - 解決案: `YayaBackend` の辞書読み込み部分（またはRustコア側）で、ファイルが存在しない場合はディレクトリ内の大文字小文字を無視した検索フォールバックを実装する。

---

## G. プラグインシステム

### 準拠度スコア: 8/10

### 実装済み（仕様準拠）
- **Plugin 2.0M 仕様**: `SaoriLoader.swift` 等で `LOADLIB` / `REQUESTLIB` / `UNLOADLIB` のライフサイクル。

### 実装済み（要修正）
- **SAORIのABI・アーキテクチャ互換性**: macOS環境ではWindows用DLL（.dll）を直接ロードすることは不可能。ネイティブdylib化されたSAORIのみがロード可能。
  - 修正案: macOS環境向けのSAORIは.dylibとして提供される必要がある。既存のWindows用ゴーストに同梱されたDLL呼び出しに対しては、安全にエラー・スキップする、あるいは汎用プロキシ（Wine/WebAssembly経由等）の仕組みを検討する。

---

## H. NARパッケージ

### 準拠度スコア: 8/10

### 実装済み（要修正）
- **パス区切り文字の差異**: ZIP/NARファイル内のパス区切り文字に `\` (バックスラッシュ) を使用しているアーカイブがある。macOS標準の解凍ライブラリはこれを単一のファイル名として認識してしまう場合がある。
  - 修正案: ZIPエントリの走査時に `\` を `/` に置換してから抽出・ディレクトリ構築を行う処理を `NarInstall/` に追加する。
- **install.txt 文字コード**: Shift_JIS エンコーディングによる読み込み。

---

## I. FMO（Forged Memory Object）

### 準拠度スコア: 7/10

### 実装済み（要修正）
- **共有メモリの実装方式**: Windowsでは `CreateFileMapping` による名前付き共有メモリ（`Sakura`, `SSP_FMO` 等）を利用するが、macOSでは `shm_open` による POSIX共有メモリ（`/ssp_fmo`, `/ninix` 等）を利用している。 → `Ourin/FMO/FmoManager.swift`
  - 互換性への影響: Windows仕様のFMOに依存するブラウザ拡張や外部ツール（SSTPクライアント等）はmacOS上では動作しない。
  - 修正案: macOSでの標準的なSSTPクライアント向けの仕様（独自のFMO名や、代替となるLocal Socket / XPC のインターフェース公開）を `docs/About_FMO_ja-jp.md` 等に明記し、デファクト化を図る。

---

## J. バルーン・シェル・リソース

### 準拠度スコア: 7.5/10

### 実装済み（要修正）
- **画像のCase Sensitivity問題**: 辞書ファイル同様、`surfaces.txt` 内の画像指定（`surface0000.png`）と実際のファイル（`surface0000.PNG`）の不一致がロードエラーを引き起こす。
- **リソース探索パス**: `descript.txt` でのエイリアス解決や相対パス探索の網羅性。

### 未実装（重要度: 低）
- **MAYA/SERIKO 複雑な描画モード**: 減色処理、特定色（純緑色 #00FF00等）の透過処理（アルファチャンネル無しのレガシー透過）。SSPでは左上ピクセルを透過色とする挙動などがある。

---

## 最終サマリー

### 1. 全体準拠度スコア
**8.1 / 10.0**
（SHIORI:8、SakuraScript:8.5 を重視して加重平均。YAYA VMの完成度が高く全体を引き上げているが、OS差異に起因する互換性課題が残る）

### 2. クリティカルな互換性問題 Top 10
1. **ファイルシステムの大文字小文字区別**: 辞書・画像ロード失敗の最大要因（macOS特有）。
2. **Shift_JIS / CP932 マッピングの不完全性**: 機種依存文字によるパースエラー。
3. **パス区切り文字 `\` の ZIP解凍エラー**: NARインストール時のディレクトリ階層崩壊。
4. **レガシー画像透過処理（クロマキー）の未対応**: アルファチャンネルを持たない古いゴーストの表示崩れ。
5. **SAORI/DLL 非互換**: Windows .dllのロード失敗とそれに伴うゴーストの機能不全。
6. **SSTP 改行コードの厳格性**: 外部ツールからの `\n` 区切りリクエストの拒否。
7. **ウェイトとタイマーの非同期**: アニメーションと音声の同期ズレ。
8. **OnMouseClick の座標系差異**: 着替え（Dressup）や当たり判定の誤動作。
9. **`\q` 選択肢引数のエスケープ解除不足**: 引数渡しに失敗しSHIORIエラーとなる。
10. **OS依存プロパティの未実装**: `sakura.os` などに依存するゴーストの分岐エラー。

### 3. 推奨修正優先順位
- **【優先度 高】（実装コスト小〜中・効果大）**
  1. ファイル名探索のCase Insensitive化フォールバック。
  2. NAR解凍時のバックスラッシュ正規化。
  3. SSTPパーサーの `\n`, `\r\n` 両対応化。
  4. CP932用カスタムString変換ロジックの導入。
- **【優先度 中】（実装コスト中〜大・重要）**
  5. 透過色（左上ピクセル取得・特定色マスク）のサポート。
  6. OnMouse系のローカル座標系への厳密な補正。
- **【優先度 低】（根本仕様に関わる・回避策あり）**
  7. SAORI .dll対応（WebAssembly化等の研究開発が必要なため一旦後回し）。

### 4. SSPとの主要な仕様解釈の差異
- **FMO共有メモリ**: SSPがWindows固有のFileMapping（`Sakura`）を用いるのに対し、OurinはPOSIX共有メモリ（`/ssp_fmo`等）を採用。
- **リクエスト処理の寛容さ**: SSPは仕様外のリクエストやヘッダフォーマット違反（例: `Charset` の記述揺れ、改行コード）に対して自動修正や無視を行うなど非常に寛容だが、Ourinは仕様に忠実な実装のため弾いてしまう（これが互換性問題に直結している）。
- Ourin独自拡張の仕様書とUKADOCの間に食い違いがある場合は、本レポートで指摘した通り**UKADOCおよびSSPのデファクト挙動を正**とし、適宜寛容なフォールバック処理を実装することが互換性向上の鍵となります。
