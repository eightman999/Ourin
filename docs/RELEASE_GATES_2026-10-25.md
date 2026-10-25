# Ourin リリースゲート / Release Gates (2026-10-25)

Public Beta / v0.1.0 に向けた P0 リリースブロッカー (#96, #97, #98, #99) と
E2E リリース試験 (#102) の決定事項・手順・残作業をまとめた文書。

---

## 1. 最低対応 macOS: **13.0 (Ventura)** (#97)

### 決定

サポートする最小 macOS は **macOS 13.0** で統一する。

### 根拠 (API availability からの導出)

- ユーザー向け正本である `README.md` が当初から **macOS 13.0 (Ventura) 以上**
  を明記している (#97 の既定方針「README を正本とする」に一致)。
- コード上 macOS 13 API はフォールバック付きだが**主要 UX がそれに依存**:
  - `MenuBarExtra` (macOS 13+) — メニューバー常駐・右クリックメニューの中核
    (`Ourin/OurinApp.swift`)。macOS 11/12 では `if #available` でスキップされ、
    メニュー自体が**無言で消える**。
  - `NavigationSplitView` (macOS 13+) — DevTools の本体 UI
    (`Ourin/DevTools/DevToolsView.swift`)。旧 OS では `navigationViewCompat`
    へ縮退するが、検証されていない縮退経路をリリース品質とはみなせない。
- macOS 11/12 用の `#available` 分岐はコンパイル互換のための保険であり、
  「対応 OS」ではない。11.0 を公称すると未検証の縮退機能をユーザーに
  約束することになる。
- README 上の開発要件 Xcode 16.4 も macOS 13 SDK 以降を前提とする。

### 揃えた箇所 (すべて 13.0)

| 箇所 | 変更前 | 変更後 |
|---|---|---|
| `Ourin/Resources/Info.plist` `LSMinimumSystemVersion` | 11.0 | **13.0** |
| pbxproj `MACOSX_DEPLOYMENT_TARGET` — Ourin (Debug/Release) | 11.0 | **13.0** |
| 同上 — OurinShioriXPCService (Debug/Release) | 11.0 | **13.0** |
| 同上 — OurinTests / OurinUITests (Debug/Release) | 15.5 | **13.0** |

テストバンドルも 13.0 に揃えたのは「最低 OS 上でテストを回せる」ためであり、
ユーザーへの影響はない (テストバンドルは配布物に含まれない)。

### 範囲外・要親判断

- `satori_core/CMakeLists.txt` / `satori_core/build.sh`:
  `CMAKE_OSX_DEPLOYMENT_TARGET=11.0`。**helper がアプリより低い最低 OS を
  持つこと自体は問題ない** (13.0 上で動く) が、表記揃えとして 13.0 への
  引き上げを推奨 (本workerの所有範囲外)。
- `yaya_core/CMakeLists.txt`: deployment target 未指定 (= ビルドした SDK
  デフォルト)。同様に `13.0` 明示を推奨。
- `Installer/Package.swift`: `platforms: [.macOS(.v12)]`。インストーラーは
  旧環境からの移行ツールでもあり、**12 のまま維持が妥当な可能性**がある。
  製品判断として親へ委ねる (案: 移行用途を意図するなら v12 維持 + README
  に「移行ツールは 12+」と明記)。
- 実機 macOS 13 での起動確認: 未実施。#102 の E2E シナリオに組み込むこと。
- README 文言は変更不要 (既に 13.0+)。リリースノート/ダウンロードページは
  公開時に 13.0+ と記載すること。

---

## 2. バージョン / リリースメタデータ方針 (#99)

### バージョニング規則

- **現在**: `CFBundleShortVersionString = 0.0.1.21`, `CFBundleVersion = 21`
  (開発期の旧式 4 成分 `X.Y.Z.B`。末尾成分 = ビルド番号)。
  ※ 本タスクでは 1.0 への引き上げは行わない。
- **今後のリリース**: `CFBundleShortVersionString` は `1.0.0` などの
  ピリオド区切りの3整数とする。これは
  [Appleの公開仕様](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleshortversionstring)
  に合わせた規則であり、Beta/RC の接尾辞や `+metadata` は含めない。
  現在の旧4成分は通常の開発検査だけで許容し、`--release` では不合格にする。
- **`CFBundleVersion`**: 全リリースを通じて単調増加する整数。
  現状 21。リリースごとに +1 (または CI run number を使う運用も可)。
- **Git tag**: `v1.0.0-beta.1`、`v1.0.0-rc.1`、`v1.0.0` などの SemVer。
  配布チャネルはタグで表し、バンドル版数には含めない。
  現在の開発期はタグを切らない。
- **`AppReleaseDate`**: リリースを切った日 (YYYY-MM-DD)。About 画面に
  表示される (`Ourin/About/AboutView.swift`)。リリース作業時に更新必須。
- **XPC バンドルのバージョン**: `MARKETING_VERSION` /
  `CURRENT_PROJECT_VERSION` から生成されるため、pbxproj 側も
  Info.plist と同じ値に揃える (本変更で 0.0.1.21 / 21 に統一済み)。

### 更新漏れ防止: `scripts/check_release_metadata.py`

CI (`metadata` ジョブ) とローカルで同じ検査を回す。

```bash
# 普段の整合チェック (CI と同一)
python3 scripts/check_release_metadata.py

# リリース時 (バージョン確定の検証)
python3 scripts/check_release_metadata.py --release \
    --expect-version 1.0.0 --expect-build 22 --release-date 2026-XX-XX
```

検査内容 (失敗 = exit 1):

- `CFBundleShortVersionString` が3整数、または通常検査のみ `X.Y.Z.B` dev 形式
- dev 形式では末尾成分 == `CFBundleVersion` (0.0.1.21 ↔ 21)
- `CFBundleVersion` が正の整数 (`--min-build N` で単調増加も検証可)
- `LSMinimumSystemVersion` == `--min-os` (既定 13.0)
- pbxproj の全 `MACOSX_DEPLOYMENT_TARGET` == `--min-os`
- pbxproj の全 `MARKETING_VERSION` == 同上バージョン、
  全 `CURRENT_PROJECT_VERSION` == 同上ビルド。各バンドルターゲットの
  Debug/Release 設定でキーが欠けた場合も不合格
- XPC の版数が上記 build setting を参照しているか、本体と同じ固定値である
- `AppReleaseDate` が YYYY-MM-DD・未来日でない (180 日超で警告)
- `--release`: 3整数のバンドル版数 + `AppReleaseDate` が当日/指定日と一致
- README 記載の macOS 要件 == `--min-os` (ドリフト検出)

### リリース時の版数更新手順

1. `Ourin/Resources/Info.plist` の `CFBundleShortVersionString` /
   `CFBundleVersion` / `AppReleaseDate` を更新
2. `Ourin.xcodeproj/project.pbxproj` の `MARKETING_VERSION` /
   `CURRENT_PROJECT_VERSION` を同値に更新
3. `python3 scripts/check_release_metadata.py --release ...` で検証
4. リリース物作成後、配布チャネルを含むタグ (例: `v1.0.0-beta.1`) を付ける

---

## 3. macOS CI リリースゲート (#96)

`.github/workflows/macOS.yml` をゲート化。PR 作成時と master push 時に実行。

### ジョブ構成

| ジョブ | 必須 | 内容 |
|---|---|---|
| `metadata` | ✅ | `check_release_metadata.py` (ubuntu、高速) |
| `test` | ✅ | macos-15 / arm64、Debug `xcodebuild test` (OurinTests + OurinUITests)、Installer `swift test`、カバレッジ付き |
| `helper-cores` | ✅ | `yaya_core` / `satori_core` を build.sh で単独ビルド、`lipo` で arm64+x86_64 を機械検証 |
| `release-gate` | ✅ | Release universal ビルド (`generic/platform=macOS`) + バンドル機械検証 + 未署名 .app artifact 保存 |
| `test-x86_64 (advisory)` | ⚠️ 参考 | Rosetta 下 x86_64 test。`continue-on-error: true` で非ブロッキング |

`release-gate` の機械検証:

- `Contents/MacOS/Ourin`・`yaya_core`・`satori_core` の存在
- `Contents/XPCServices/OurinShioriXPCService.xpc` (+ 実行ファイル) の存在
- `Contents/Resources/sakura.nar` (同梱既定ゴースト) の存在
- 全実行バイナリが `lipo -info` で arm64+x86_64 universal
- `LSMinimumSystemVersion == 13.0` 等の Info.plist 値
- ビルド後の XPC と本体の `CFBundleShortVersionString` / `CFBundleVersion` が一致

### Intel/Apple Silicon matrix の設計判断

- `macos-13` ランナー (Intel) は **Xcode 15 系まで**しか積めず、本プロジェクト
  (`objectVersion = 77`, 要件 Xcode 16.4, Swift Testing 使用) をビルドできない
  ため採用不可。
- `macos-15-intel` は
  [GitHub公式の標準Intelランナー](https://docs.github.com/en/actions/reference/runners/github-hosted-runners#standard-github-hosted-runners-for-public-repositories)
  に含まれる。larger runner 専用ではなく、Intel 上の試験を追加する候補となる。
- 現時点の workflow は **universal ビルド + lipo 検証**を hard gate、
  **Rosetta x86_64 test** を advisory leg としている。ネイティブ Intel job は
  未追加であり、Intel 実機での最終確認は #102 の残件とする。

この workflow の GitHub 上での実行成功と最低対応 macOS 13 上の動作は未確認。
上記は検査設定であり、CI 実測済み・実機対応確認済みを意味しない。

### ローカル再現手順 (README/CONTRIBUTING への追記案)

```bash
# metadata ゲート
python3 scripts/check_release_metadata.py

# test ゲート (Debug)
xcodebuild -project Ourin.xcodeproj -scheme Ourin \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO test
swift test --package-path Installer

# helper-cores ゲート
./yaya_core/build.sh && ./satori_core/build.sh
lipo -info yaya_core/build/yaya_core satori_core/build/satori_core

# release-gate (Release universal + 検証)
xcodebuild -project Ourin.xcodeproj -scheme Ourin -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO build
APP=DerivedData/Build/Products/Release/Ourin.app
ls "$APP/Contents/XPCServices" "$APP/Contents/MacOS"
lipo -info "$APP/Contents/MacOS/"{Ourin,yaya_core,satori_core}
```

### 補足: 共有スキーム

`Ourin.xcodeproj/xcshareddata/xcschemes/Ourin.xcscheme` を新設した。
従来リポジトリには共有スキームがコミットされておらず、クリーン checkout
では `xcodebuild -scheme Ourin` がスキーム未解決で失敗する。CI ゲートの
前提条件として追加した (Testables = OurinTests + OurinUITests)。

### ⚠️ 承認依存の残作業 (本workerでは実行不可)

- **branch protection**: master に required status checks
  `metadata` / `test` / `release-gate` / `helper-cores` を設定する。
  リポジトリ管理者が Settings → Branches → master のルールで設定、または
  `gh api repos/<owner>/<repo>/branches/master/protection` で設定。
  未設定の間は CI は走るが「必須」ではない点に注意。
- 署名 credential を CI へ置く設計は別途 (#98)。現行 PR CI は
  `CODE_SIGNING_ALLOWED=NO` で credential 不要。

---

## 4. Developer ID 署名・公証・配布 (#98 ローカル準備)

> 本workerは署名実行・credential 参照を行わない。以下は確立済み手順の整備状況。

### 既存資産

- `scripts/release.sh`: Developer ID 署名 → 公証 → staple → ZIP + SHA-256
  + Installer.app 連携まで一括。nested signing は「全 Mach-O → XPC → app」
  の内→外順で実施済み。
- `scripts/notarize.sh`: notarytool 提出・待機再試行・staple・`spctl` 確認。
- `scripts/build-installer.sh`: Installer.app 組み立て。

### 実行手順 (リリース担当者向け)

```bash
# 前提: Developer ID Application 証明書が login keychain にあり、
# notarytool の keychain profile を作成済み
#   xcrun notarytool store-credentials "ourin-notary" --apple-id <id> \
#     --team-id <TEAM> --password <app-specific-password>

scripts/release.sh            # 署名+公証+staple+ZIP+sha256+Installer
# 確認だけしたい場合
SKIP_NOTARIZE=1 scripts/release.sh
```

出力: `build/release/Ourin-<version>.zip` + `.sha256` (+ Installer.app)

### 手順上の確認ポイント (AC 対応表)

| AC | 状態 | 確認方法 |
|---|---|---|
| Developer ID 署名 | 手順済 | release.sh が codesign を内→外で実行 |
| `codesign --verify --deep --strict` | 手順済 | release.sh 内で実施 |
| XPC/helper 署名状態 | 手順済・**注意点あり** | 下記「署名の注意点」 |
| 公証 + staple | 手順済 | notarize.sh (wait 再試行×3 あり) |
| 配布形式 | **ZIP** (確立) | DMG 化は任意・将来検討 |
| Gatekeeper 確認 | 手順済 (`spctl -a -t exec -vv`) | quarantine 環境での実機確認は #102 |
| SHA-256 公開 | 手順済 | `.sha256` 同梱 |
| credential 非保管 | OK | keychain profile + env var のみ |

### 署名の注意点 (実機実行時に要確認)

- `Contents/Resources/yaya_core` に **unsigned copy が二重に存在**する
  (Resources には CodeSignOnCopy なしで複製される)。release.sh は全
  Mach-O を走査して署名するためカバーされるが、**Resources への無署名
  複製は公証で引っかかる既知パターン**。恒久対応としては Resources
  からの複製を除去するか CodeSignOnCopy 相当の対応を検討すべき
  (pbxproj 構造上の要検討事項として記録)。
- 未署名 app を Xcode が `CODE_SIGNING_ALLOWED=NO` で作ると ad-hoc 相当の
  未署名 Mach-O が残る。配布は必ず release.sh 経由の署名済み物を使う。

### ⚠️ 承認依存の残作業

- Developer ID 証明書・notarytool credential の保有確認 (ユーザー/管理者作業)
- quarantine 付きクリーン Mac での Gatekeeper 起動実測 (#102 と共通化)
- 必要なら DMG / 公証済み pkg の形式選定 (現状 ZIP のみ)

---

## 5. E2E リリース試験チェックリスト (#102 検証手順)

Public Beta 前に最低 1 回、RC ごとに実施。配布物は release.sh 産物
(または CI artifact の unsigned app を ad-hoc 起動確認用途に限定して使用)。

### 環境

- Apple Silicon Mac。**クリーン条件**: 以下が存在しないこと
  - `/Applications/Ourin.app`
  - `~/Library/Containers/furin-lab.Ourin/`
  - `~/Library/Application Support/Ourin/` (非コンテナ配置があれば)
  - FMO 共有メモリ `/dev/shm` 相当の残存 (再起動でクリア)
- Intel 対応を公称する場合は Intel Mac または信頼できる同等検証
- 配布 ZIP をブラウザ経由でダウンロードし quarantine 属性を付けた状態で試す
  (Gatekeeper 検証になるよう `curl -LO` ではなくブラウザ DL 推奨)

### シナリオ (issue #102 の 11 項目を手順化)

| # | 手順 | 期待結果 | 確認コマンド等 |
|---|---|---|---|
| 1 | ZIP を DL し /Applications へ展開・初回起動 | Gatekeeper で阻止されず起動 (署名済の場合)。未署名なら「開発元を確認」で起動可 | `spctl -a -t exec -vv /Applications/Ourin.app` |
| 2 | 既定ゴースト (sakura) 起動 | サーフェス表示・SHIORI 応答 | — |
| 3 | helper 確認 | `Contents/MacOS/yaya_core` / `satori_core` が存在し XPC 接続 | Activity Monitor で XPC サービス名確認 |
| 4 | .nar ダブルクリック | インストーラが起動しゴースト追加 | Finder で `sakura.nar` 等を開く |
| 5 | .nar をアプリへ D&D | 同上でインストール | — |
| 6 | ゴースト切替 | メニューから別ゴーストへ切替・スクリプト応答 | — |
| 7 | 会話/クリック/メニュー | 応答・バルーン表示・右クリックメニュー全項目 | — |
| 8 | savedata 生成 | 会話/設定後に保存先へ書き込み | `~/Library/Containers/furin-lab.Ourin/Data/Library/Application Support/Ourin/` |
| 9 | 終了 | 正常終了 (クラッシュなし) | — |
| 10 | 再起動後起動 | ゴースト選択・savedata が維持 | 8 の保存先の更新日時・内容確認 |
| 11 | 失敗系 | 破損 .nar / 権限なし dir で**アプリ全体がクラッシュしない** | ゼロバイト .nar、先頭数バイト破壊 zip、非 zip 拡張子偽装 |

### 追加確認

- 非対応 OS (12.x 実機があれば) で「このアプリケーションは macOS 13.0 以降
  が必要です」系の起動拒否が出ること (`LSMinimumSystemVersion` 機能)。
- アンインストール手順: app 削除 + 上記保存先削除をユーザー向けドキュメントへ
  記載 (README/ヘルプ整備は親タスク)。

### 記録フォーマット

実施ごとに下記を `docs/` か Issue コメントへ残す: 実施日 / OS・機種 /
配布物 SHA-256 / 各シナリオ合否 / 発見不具合 (Issue 分割)。

### ⚠️ 承認依存の残作業

- 実機 (macOS 13 実機・Intel 実機) の手配は環境依存
- 不具合発見時の Issue 起票は親/ユーザーが実施

---

## 6. 未完了・承認依存タスク一覧

| 項目 | 必要な権限/資産 | 関連 Issue |
|---|---|---|
| branch protection に必須チェック登録 | repo admin | #96 |
| Developer ID 証明書 + notarytool credential 実物 | Apple ID / keychain | #98 |
| クリーン Mac (AS/Intel) での E2E 実施 | 実機 | #98, #102 |
| `satori_core`/`yaya_core` の deployment target を 13.0 へ | file owner (本worker範囲外) | #97 |
| `Installer/Package.swift` min OS の方針決定 (v12 維持か v13 か) | 製品判断 | #97 |
| `Contents/Resources/yaya_core` 二重同梱の恒久対応 | pbxproj 設計判断 | #98 |
| README/CONTRIBUTING への CI 再現手順追記 (§3 の案) | file owner | #96 |
| Git tag `v…` 運用開始 | リリース時 | #99 |

配布前に[既知の問題](KNOWN_ISSUES_ja-jp.md)と[報告手順](BUG_REPORT_GUIDE_ja-jp.md)を当該リリースノートへ添付する。GitHub上の既存release本文は今回変更していない。
