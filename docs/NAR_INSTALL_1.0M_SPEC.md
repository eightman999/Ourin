
# Ourin — **NAR Double‑Click Installer** 仕様書（NAR-INSTALL/1.0M, macOS, ToC付き）
**Status:** Draft  
**Updated:** 2025-07-28 20:07 UTC+09:00  
**Target:** macOS 10.15+（Catalina 以降）, Universal 2（arm64 / x86_64）

> 目的：拡張子 **`.nar`**（実体は ZIP アーカイブ）を**ダブルクリック**または**「このAppで開く」**で Ourin が受け取り、`install.txt` の語彙に従って **ghost / balloon / shell / plugin / package** を所定ディレクトリに安全に展開・登録するための規格。SSP の慣行（D&D/ダブルクリック）を踏襲しつつ、**UTF‑8 を既定**・**CP932 受理**・**Zip Slip防止**を必須とする。

---

## 目次
- [0. 用語・前提](#0-用語前提)
- [1. 適用範囲と非目標](#1-適用範囲と非目標)
- [2. 依存仕様と参考](#2-依存仕様と参考)
- [3. 受付と関連付け（UTI/Document Types）](#3-受付と関連付けutidocument-types)
- [4. 受け口（open handler）](#4-受け口open-handler)
- [5. アーカイブ検証と文字コード判定](#5-アーカイブ検証と文字コード判定)
- [6. install.txt の語彙（受理する要点）](#6-installtxt-の語彙受理する要点)
- [7. 展開ポリシー（安全な unzip と配置）](#7-展開ポリシー安全な-unzip-と配置)
- [8. 競合と更新（accept/delete/homeurl）](#8-競合と更新acceptdeletehomeurl)
- [9. ログ・失敗時の UX](#9-ログ失敗時の-ux)
- [10. セキュリティ（Zip Slip / 隔離属性）](#10-セキュリティzip-slip--隔離属性)
- [11. 互換性メモ（Windows/大小・改行差分）](#11-互換性メモwindows大小改行差分)
- [付録A. Info.plist 宣言例](#付録a-infoplist-宣言例)
- [付録B. 成功/失敗フロー](#付録b-成功失敗フロー)
- [付録C. サンプル構成](#付録c-サンプル構成)
- [変更履歴](#変更履歴)

---

## 0. 用語・前提
- **.nar**：Ukagaka 配布パッケージ。**実体は ZIP**。  
- **install.txt**：アーカイブ最上位に置かれる**インストール定義**（`type`/`directory`/`*.directory` ほか）。  
- **Ourin 標準設置先**：`~/Library/Application Support/Ourin/` 配下。  
- **文字コード**：**UTF‑8 既定**、**CP932 受理**（内部は UTF‑8 正規化）。

## 1. 適用範囲と非目標
- **対象**：Finder の**ダブルクリック**／「このAppで開く」／Ourin ウィンドウへの**D&D**でのインストール。  
- **非目標**：Windows のバイナリ互換再現や、Install UI の完全模倣。**プロトコル（install.txt の語彙）互換**を重視。

## 2. 依存仕様と参考
- **Apple UTI/Document Types**：`.nar` を **custom UTI** としてエクスポートし、**`public.zip-archive`** に準拠。`CFBundleDocumentTypes` で関連付け、App は **open handler** を実装する。  
- **NSApplicationDelegate**：`application(_:openFiles:)` / `application(_:open:)` で URL/パス受理。  
- **Ukadoc**：**install.txt / 配布 / ネットワーク更新**などの運用慣行に準拠（`updates2.dau`/`delete.txt`/ドラッグ&ドロップ/ダブルクリック）。

## 3. 受付と関連付け（UTI/Document Types）
- **UTExportedTypeDeclarations** に `jp.ourin.nar` を宣言し、`UTTypeConformsTo = public.zip-archive`、拡張子 `nar` を紐付ける。  
- **CFBundleDocumentTypes** に `LSItemContentTypes = jp.ourin.nar` を設定（Role は Viewer/Editor いずれでも可）。
- 競合した場合の優先度は **LSHandlerRank** で調整。

## 4. 受け口（open handler）
- App 起動時/起動中の**両方**で呼ばれるよう、`NSApplicationDelegate.application(_:openFiles:)`（複数）と `application(_:open:)`（URL）双方を実装。SwiftUI 構成でも AppKit デリゲートをブリッジ。

## 5. アーカイブ検証と文字コード判定
- MIME/UTType で **zip 互換**を確認し、先頭レコードもチェック。  
- `install.txt` は **UTF‑8 を優先**して読む。失敗時は **CP932** で再試行し、内部は UTF‑8 正規化。BOM・CRLF も受理。

## 6. install.txt の語彙（受理する要点）
- **必須**：`type,(ghost|balloon|shell|plugin|package)`／`directory,<設置名>`  
- **任意**：`accept,<識別名>`、`*.directory,<同梱名>`（例：`balloon.directory,MyBalloon`）、`*.source.directory` など。  
- **推奨**：`charset,UTF-8` を**先頭**に明記。

## 7. 展開ポリシー（安全な unzip と配置）
- 一時ディレクトリに**安全に解凍**→ `install.txt` を解釈 → **設置先**にコピー。  
- **除外**：`__MACOSX/`、`.DS_Store`、`Thumbs.db` は自動除外。  
- **ケース整合**：ファイル名の大小を**厳密に**扱い、重複衝突は警告。

## 8. 競合と更新（accept/delete/homeurl）
- 既存 `{directory}` がある場合：`accept` 一致なら上書き更新、相違なら別名提案。  
- `delete.txt` があれば不要資産を削除。更新配布は `homeurl` + `updates2.dau` に追従。

## 9. ログ・失敗時の UX
- 主要フェーズ（検証/解析/展開/事後処理）を `OSLog` に記録。  
- 代表エラー：`InstallTxtMissing`、`UnsupportedType`、`ZipSlipDetected`、`NameConflict`、`DecodeFailed(sjis)`。

## 10. セキュリティ（Zip Slip / 隔離属性）
- **Zip Slip**：展開前にパス正規化し、`..`/絶対パス/シンボリックリンクによる**ターゲット外書込み**を**拒否**。  
- ダウンロード由来の隔離属性は**ユーザ操作起点**（ダブルクリック/ドロップ）で正規フローと見做す。

## 11. 互換性メモ（Windows/大小・改行差分）
- Windows 既存配布は **Shift_JIS**／`\\` 区切りのまま入ってくることがある。Ourin は **入力受理**し、内部を UTF‑8/UNIX パスに正規化する。  
- 改行は CRLF/LF どちらも受理。

---

## 付録A. Info.plist 宣言例
```xml
<!-- Info.plist 抜粋：UTI と Document Types -->
<key>UTExportedTypeDeclarations</key>
<array>
  <dict>
    <key>UTTypeIdentifier</key><string>jp.ourin.nar</string>
    <key>UTTypeDescription</key><string>Ukagaka NAR</string>
    <key>UTTypeConformsTo</key>
    <array><string>public.zip-archive</string></array>
    <key>UTTypeTagSpecification</key>
    <dict>
      <key>public.filename-extension</key><array><string>nar</string></array>
      <key>public.mime-type</key><string>application/x-ukagaka-nar</string>
    </dict>
  </dict>
</array>

<key>CFBundleDocumentTypes</key>
<array>
  <dict>
    <key>CFBundleTypeName</key><string>Ukagaka NAR</string>
    <key>LSItemContentTypes</key>
    <array><string>jp.ourin.nar</string></array>
    <key>CFBundleTypeRole</key><string>Viewer</string>
  </dict>
</array>
```

## 付録B. 成功/失敗フロー
```
Finder(.nar) → Launch Services → Ourin(app open)
 → open handler
   → validate(zip) OK? → read install.txt → parse {type,directory,...}
   → resolve install path
   → safeExtract → copy/merge → post steps(readme/terms, switch)
   → success toast

NG:
  - no install.txt → error: InstallTxtMissing
  - unsupported type → error: UnsupportedType
  - zip slip → error: ZipSlipDetected
  - directory conflict → user prompt(rename/overwrite)
```

## 付録C. サンプル構成
```
OURIN_NAR_INSTALL_1_0M/
  NAR_INSTALL_1.0M_SPEC.md
  NAR_INSTALL_1.0M_PLAN.md
  sample/
    Sources/OurinNarInstallerSample/
      AppDelegate.swift
      SampleNarInstaller.swift
      InstallTxtParser.swift
      ZipUtil.swift
      Paths.swift
    Info.plist (example)
```

---

## 変更履歴
- 2025-07-28 20:07 UTC+09:00: 初版（NAR-INSTALL/1.0M）。
