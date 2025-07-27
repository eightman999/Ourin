# Ourin WEB/1.0M Samples
最小サンプル（Info.plist 断片、Swift URL ハンドラ）。

## 1) URL/UTI の Info.plist 断片
- `Info_ukagaka_link_and_nar.plist` の各キーを既存の Info.plist に統合してください。
  - `CFBundleURLTypes` に `x-ukagaka-link` を登録。
  - `UTExportedTypeDeclarations` に `com.ourin.nar`（`public.zip-archive` 準拠）を宣言。
  - `CFBundleDocumentTypes` の `LSItemContentTypes` に `com.ourin.nar` を指定。

## 2) Swift URL ハンドラ
- `AppDelegate.swift` をプロジェクトに追加し、ターゲットの App Delegate として組み込みます。
- 起動時に **kAEGetURL** ハンドラを登録し、`x-ukagaka-link:` を解析して標準出力にログします。
- 実運用では、`type=event` → **OnXUkagakaLinkOpen**（SHIORI/3.0M）を発行、
  `type=install/homeurl` → **https ダウンロード→NAR 展開/更新** を実装してください。

## ビルド要件
- macOS 10.15+ / Xcode 14+ / Swift 5.7+
