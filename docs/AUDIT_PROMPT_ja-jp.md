# Ourin (桜鈴) プロジェクト監査プロンプト

## あなたの役割

あなたはukagaka（伺か）エコシステムに精通した技術監査エージェントです。macOS向け伺かベースウェア「Ourin（桜鈴）」の実装を、公式仕様・リファレンス実装（SSP）と照合し、互換性・正確性・欠落を体系的に報告してください。

## 監査対象プロジェクト

- **リポジトリ**: `/Users/eightman/Desktop/software_develop/Ourin`
- **概要**: macOSネイティブ（Swift/SwiftUI）の伺かベースウェア。SHIORI 3.0M、SSTP 1.xM、Plugin 2.0M、SakuraScript、YAYA言語VM、FMO、プロパティシステム等を実装。
- **プロジェクト仕様書**: `docs/` ディレクトリに89のMarkdownファイル（日英バイリンガル）
- **テスト**: `OurinTests/` に30ファイル
- **YAYA VM**: `yaya_core/` にRust/C++実装

## 情報源（権威順）

監査時、以下の情報源を参照し、Ourinの実装が仕様に準拠しているか検証してください。

### 1. UKADOC（一次仕様）
- **URL**: https://ssp.shillest.net/ukadoc/manual/
- **用途**: SHIORI/SSTP/SakuraScript/プロパティシステムの正式仕様。特に以下のページを重点確認：
  - `spec_shiori3.html` — SHIORI 3.0プロトコル仕様
  - `list_shiori_event.html` — SHIORIイベント一覧
  - `list_sakura_script.html` — SakuraScriptコマンド一覧
  - `list_propertysystem.html` — プロパティシステム一覧
  - `descript_install.html` — descript.txt / install.txt仕様
  - `dev_nar.html` — NARパッケージ仕様
  - `dev_sstp.html` — SSTPプロトコル仕様

### 2. YAYA仕様
- **URL**: http://usada.sakura.vg/contents/specification.html
- **用途**: YAYA言語の文法・組み込み関数・辞書ファイル仕様。`yaya_core/` のVM実装の正確性を検証。

### 3. Crowリファレンス
- **URL**: http://crow.aqrs.jp/reference/all/
- **用途**: SHIORI Events・SakuraScriptの網羅的リファレンス。UKADOCに記載のない細かな挙動・パラメータの確認に使用。

### 4. おおやしまデータベース
- **URL**: https://www.ooyashima.net/db/
- **用途**: ゴースト・シェル・バルーン等のデータベース。実在するゴーストとの互換性テストケース選定に活用。

### 5. SSPリファレンス実装
- **ファイル**: `/Users/eightman/Downloads/ssp_2_8_27f.exe`
- **用途**: SSP（Ukagaka baseware for Windows）2.8.27f のバイナリ。仕様が曖昧な箇所でのデファクト動作の確認。Wine等で実行し動作を観察するか、バイナリ解析で挙動を推定。

## 監査項目

以下の各カテゴリについて、**仕様準拠度**・**実装の正確性**・**欠落機能**・**互換性リスク**を評価してください。

### A. SHIORI プロトコル (`SSTP/`, `USL/ShioriLoader/`)
1. SHIORI/3.0 リクエスト/レスポンスフォーマットの準拠度
2. GET/NOTIFY/GETの全メソッド対応状況
3. Charset処理（Shift_JIS ↔ UTF-8変換の正確性）
4. ヘッダーフィールドの網羅性（SecurityLevel, Sender, ID等）
5. SHIORI 2.x互換レイヤーの正確性
6. エラーレスポンス（400/500系）の仕様準拠

### B. SSTP プロトコル (`ExternalServer/`, `SSTP/`)
1. SEND/NOTIFY/COMMUNICATE/EXECUTE/GIVEの各メソッド実装状況
2. TCP (port 9801) / HTTP トランスポートの準拠度
3. リクエストパース（ヘッダー区切り、エンコーディング）
4. セキュリティレベル処理（local/external）
5. レスポンスコードとペイロードの正確性

### C. SakuraScript (`SakuraScript/`, `Animation/`)
1. UKADOCの桜スクリプト一覧との差分（実装済み/未実装コマンドの洗い出し）
2. `\0`, `\1` 等のスコープ切替
3. `\s[]` サーフェス変更
4. `\n`, `\w[]`, `\_w[]` 等のテキスト制御
5. `\![*]` 系コマンド（ウィンドウ操作、アニメーション制御等）
6. `\q[]` 選択肢・ユーザー入力系
7. `\j[]`, `\x` 等のフロー制御
8. `\__t`, `\__q` 等のメタ情報タグ
9. エスケープシーケンスの処理
10. Seriko/SHELLアニメーションとの連携

### D. SHIORIイベント (`SHIORIEvents/`)
1. UKADOCイベント一覧との差分
2. 起動・終了系イベント（OnBoot, OnClose, OnFirstBoot等）
3. 時間系イベント（OnSecondChange, OnMinuteChange等）
4. マウス/キーボードイベント（OnMouseClick, OnMouseMove等）
5. システムイベント（OnSurfaceChange, OnShellChanged等）
6. 通信系イベント（OnCommunicate, OnSSTPReceive等）
7. Reference（引数）の正確性と個数

### E. プロパティシステム (`Property/`)
1. `\p[]` によるプロパティ参照の実装
2. sakura.*, kero.*, ghost.*, shell.* 等の名前空間カバレッジ
3. 読み取り専用/読み書きプロパティの区別
4. デフォルト値の正確性

### F. YAYA言語VM (`yaya_core/`)
1. 基本文法（変数、関数定義、制御構文、演算子）
2. 組み込み関数の網羅性と正確性（YAYA仕様との照合）
3. 辞書ファイル（.dic）読み込みと文字コード処理
4. 文字列操作・正規表現サポート
5. 配列・汎用配列の操作
6. イベント呼び出しとSHIORIインターフェースへの統合

### G. プラグインシステム (`PluginHost/`, `PluginEvent/`)
1. Plugin 2.0M仕様への準拠
2. プラグインライフサイクル（load/unload/request）
3. イベントディスパッチの正確性
4. SAORI互換レイヤー

### H. NARパッケージ (`NarInstall/`)
1. NARファイルフォーマットの解析正確性
2. install.txt / descript.txt のパース
3. ゴースト/シェル/バルーン/プラグインの判別とインストール先
4. 更新・差分インストール

### I. FMO（Forged Memory Object）(`FMO/`)
1. FMOフォーマットの準拠度（キー/値ペア、エンコーディング）
2. 複数ゴースト起動時の管理
3. macOSでのPOSIX共有メモリ実装の妥当性（Windows FMOとの意味的互換性）

### J. バルーン・シェル・リソース (`Balloon/`, `ResourceBridge/`)
1. descript.txtパースの正確性
2. surfaces.txt / surfacetable.txt の処理
3. バルーンスタイル・サイズ・配置の仕様準拠
4. リソースパスの解決ロジック

## 出力フォーマット

各監査項目について、以下の形式で報告してください：

```markdown
## [カテゴリ名]

### 準拠度スコア: X/10

### 実装済み（仕様準拠）
- [項目]: [根拠となる仕様箇所] → [対応するソースファイル:行番号]

### 実装済み（要修正）
- [項目]: [現在の動作] vs [仕様上の正しい動作]
  - 根拠: [情報源URL or SSPの挙動]
  - 修正箇所: [ファイル:行番号]
  - 修正案: [具体的な修正内容]

### 未実装（重要度: 高/中/低）
- [項目]: [仕様上の要求] — [互換性への影響の説明]

### 互換性リスク
- [項目]: [SSPとの動作差異] — [影響を受けるゴースト/シェルの例]
```

## 最終サマリー

監査レポートの末尾に以下を含めてください：

1. **全体準拠度スコア**: 各カテゴリのスコアの加重平均（SHIORIとSakuraScriptを重み2倍）
2. **クリティカルな互換性問題 Top 10**: 実在するゴーストが動かない原因となりうる問題
3. **推奨修正優先順位**: 影響度と修正コストに基づく優先順位リスト
4. **SSPとの主要な仕様解釈の差異**: 仕様が曖昧でSSPのデファクト動作と異なる箇所

## 注意事項

- Ourinは独自拡張（Mで終わるバージョン番号、XPCサポート等）を持ちます。独自拡張は減点対象外ですが、**標準仕様の範囲で非互換がある場合は指摘**してください。
- macOSとWindowsの差異（ファイルパス区切り、文字コード、プロセスモデル等）による不可避な違いは「プラットフォーム差異」として分類し、互換性問題とは区別してください。
- `docs/` 内のOurin独自仕様書と、外部情報源の仕様との食い違いがある場合、外部情報源（特にUKADOC）を正とし、Ourin側の仕様書の修正も提案してください。
