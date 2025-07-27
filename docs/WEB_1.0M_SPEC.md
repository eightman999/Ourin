# WEB/1.0M — Ourin（桜鈴）向け macOS ネイティブ差分仕様（Draft）
**Status:** Draft  
**Updated:** 2025-07-27  
**Scope:** UKADOC「Web関連」 — `x-ukagaka-link` スキーム と `application/x-nar` MIME の **語彙・挙動互換**を維持しつつ、macOS の URL スキーム／UTType／ドキュメントタイプに適合させる。  
**非目標:** Windows レジストリ等の再現、Windows 向け挙動の完全模倣（語彙・挙動互換に留める）。

---

## 目次
- [1. 目的と方針](#1-目的と方針)
- [2. 用語](#2-用語)
- [3. `x-ukagaka-link` スキーム（互換）](#3-x-ukagaka-link-スキーム互換)
- [4. `application/x-nar` MIME（互換）](#4-applicationx-nar-mime互換)
- [5. macOS への落とし込み](#5-macos-への落とし込み)
  - [5.1 URL スキーム登録（CFBundleURLTypes）](#51-url-スキーム登録cfbundleurltypes)
  - [5.2 URL 受理（kAEGetURL / NSAppleEventManager）](#52-url-受理kaegeturl--nsappleeventmanager)
  - [5.3 `.nar` の UTI/ドキュメントタイプ](#53-nar-の-utiドキュメントタイプ)
- [6. セキュリティ/UX 推奨事項](#6-セキュリティux-推奨事項)
- [7. SHIORI/3.0M へのブリッジ](#7-shiori30m-へのブリッジ)
- [8. テスト観点](#8-テスト観点)
- [9. 参考](#9-参考)

---

## 1. 目的と方針
- **UKADOC の語彙と挙動**を踏襲：`x-ukagaka-link` の `type=event/install/homeurl`、`UTF-8` 固定＋**URL エンコード済み**、`application/x-nar` 推奨（`application/zip` も受理）等。  
- **macOS ネイティブ**：URL スキームは **CFBundleURLTypes**、受理は **kAEGetURL**（NSAppleEventManager）。`.nar` は **UTType** を宣言し Finder/ブラウザから開けるようにする。

## 2. 用語
- **WEB/1.0M**: 本仕様の macOS 差分識別。  
- **ホスト**: Ourin（桜鈴）などベースウェア。  
- **UTType**: Uniform Type Identifier。`public.zip-archive` などのシステム定義型に準拠。

## 3. `x-ukagaka-link` スキーム（互換）
- 書式（いずれも **UTF‑8＋URL エンコード**済みの文字列）：  
  - `x-ukagaka-link:type=event&ghost=(ゴースト名)&info=(追加情報)` — 開くと **OnXUkagakaLinkOpen** を発生。  
    （ゴースト名は `descript.txt` の `name` または `sakura.name` と同一。）  
  - `x-ukagaka-link:type=install&url=(エンコード済URL)` — 指定 URL の **NAR をインストール**。  
  - `x-ukagaka-link:type=homeurl&url=(エンコード済URL)` — 指定 URL を **更新先 URL として認識**し、ネットワーク更新後にインストール。

## 4. `application/x-nar` MIME（互換）
- **NAR 用に `application/x-nar` を推奨**。ただし **`application/zip` も受理**（実体は Zip のため）。

## 5. macOS への落とし込み

### 5.1 URL スキーム登録（CFBundleURLTypes）
- アプリの **Info.plist** に `CFBundleURLTypes` を宣言し、`x-ukagaka-link` を登録。  
- 例はサンプル `Info_ukagaka_link_and_nar.plist` を参照。

### 5.2 URL 受理（kAEGetURL / NSAppleEventManager）
- macOS では、カスタム URL は **kAEGetURL** AppleEvent で届く。  
- 起動時に **NSAppleEventManager** へハンドラを登録し、URL を解析（`type`/`ghost`/`info`/`url`）して処理する。  
- Swift の最小例はサンプル `AppDelegate.swift` を参照。

### 5.3 `.nar` の UTI/ドキュメントタイプ
- **UTExportedTypeDeclarations** で `com.ourin.nar` を宣言：  
  - `UTTypeConformsTo`: `public.zip-archive`  
  - `public.filename-extension`: `nar`  
  - `public.mime-type`: `application/x-nar`, `application/zip`  
- **CFBundleDocumentTypes** の `LSItemContentTypes` に `com.ourin.nar` を指定（Finder ダブルクリック/ブラウザ「開く」対応）。

## 6. セキュリティ/UX 推奨事項
- `install/homeurl` の **ダウンロード元は https:// のみ許可**（既定）。  
- サイズ上限・拡張子チェック・ハッシュ検証・ドメイン許可リストを推奨。  
- インストール前に **確認ダイアログ**、ゴースト名衝突時は **ユーザ選択**。  
- ログに **元 URL と結果** を記録。

## 7. SHIORI/3.0M へのブリッジ
- `type=event` を受けたら、対象ゴーストに **`GET SHIORI/3.0` / `ID: OnXUkagakaLinkOpen`** を配送：  
  - `SecurityLevel: external`（固定）  
  - `Reference0: info（URLデコード済み）`

## 8. テスト観点
- `type=event`：日本語名/長文/絵文字、対象ゴースト不在時の処理。  
- `type=install/homeurl`：HTTP 3xx、TLS エラー、巨大ファイル、`application/zip` でも受理。  
- `.nar` の関連付け：Finder ダブルクリック／ブラウザからの「開く」。

## 9. 参考
- UKADOC Web関連 — `x-ukagaka-link` / `application/x-nar`  
- SHIORI Event（`OnXUkagakaLinkOpen`：`SecurityLevel=external`、`Reference0=info`）  
- Apple: **CFBundleURLTypes**（URL スキーム登録）/ **Defining a custom URL scheme**（手順）  
- Apple: **NSAppleEventManager**（AppleEvent ハンドラ）/ **kAEGetURL**（GetURL イベント）  
- Apple: **Uniform Type Identifiers**（UTType 定義）/ **System-declared UTIs**（`public.zip-archive`）

