# BOOTH 商品ページ文案（Ourin 0.1.0 Public Beta）

## 商品名
Ourin（桜鈴）— Mac で動く伺かベースウェア 0.1.0 Public Beta

## 価格案
- 0 円（無料配布）＋ 任意の支援（BOOST）

## 概要（冒頭 3 行）
Mac で「伺か」が動くベースウェアです。
SSP 向けのゴースト・シェル・バルーン・プラグインを、Wine などを使わずに macOS ネイティブで動かします。
Apple の Developer ID 署名・公証済み、Apple シリコン／Intel 両対応、アプリ内から自動アップデートできます。

## 特長
- **ネイティブ動作**: Wine／CrossOver を使わず、macOS のアプリとして動きます。
- **主要な栞（SHIORI）に対応**: YAYA、里々、KAGARI などをアプリに内蔵。
- **SSP 互換**: SakuraScript、SERIKO、SSTP、NAR インストール、PLUGIN、SAORI を SSP／UKADOC の仕様に合わせて実装。
- **プラグイン**: YAYA／KAGARI で作られた SSP 向けプラグインは、Mac 向けに自動で変換して動かします。
- **かんたん移行**: 専用インストーラーで、Wine 環境の SSP からゴーストとバルーンをコピーできます（元のデータは変更しません）。
- **自動アップデート**: 新しい版を 1 日 1 回確認し、署名を確かめてから入れ替えます。

## 同梱物
- Ourin Installer.app（インストーラー）
- Ourin.app（本体）
- はじめにお読みください.txt
- ライセンス

標準ゴースト「Sakura and Rinne」を同梱しています。エミリーなど他のゴーストは同梱していません。

## 動作環境
- macOS 13.0 (Ventura) 以降
- Apple シリコン／Intel

## ご注意
- ベータ版です。ゴーストのデータはバックアップを取ってからご利用ください。
- すべてのゴースト・プラグインの動作は保証できません。Windows 専用アプリと連携するプラグインは動きません。
- 対応状況: https://furinlab.com/ourin/compatibility/

## サポート
- 使い方: https://furinlab.com/ourin/guide/
- 不具合報告: https://github.com/eightman999/Ourin/issues

## 出品時のチェックリスト
- [ ] `scripts/release.sh` で署名・公証した成果物を作る
- [ ] `scripts/package-booth.sh` で `Ourin-<版>-booth.zip` を作る
- [ ] 別の Mac（または新規ユーザー）で zip を展開し、インストーラーが Gatekeeper の確認だけで開けることを確認
- [ ] GitHub Release（`Ourin-<版>.zip` と `.sha256` を含む）を公開し、旧版から自動アップデートできることを確認
- [ ] サムネイル（1:1）と、ゴーストが動いているスクリーンショットを 3〜5 枚用意
