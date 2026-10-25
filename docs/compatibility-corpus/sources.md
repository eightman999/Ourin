# 互換性検証用・配布元カタログ

調査日: 2026-10-25。検証runner用の `catalog.json` は初回52件と追加40件を統合した **92件（ゴースト67、バルーン10、プラグイン15）** です。以下は各バッチの発見・確認時点の記録です。

初回発見バッチは **52 件（ゴースト 28、バルーン 10、プラグイン 14）**。追加発見バッチ `catalog-batch2.json` は **40 件（ゴースト 39、プラグイン 1）**。重複除去後の計 **92 件（ゴースト 67、バルーン 10、プラグイン 15）**。全配布物の網羅、対応率、動作成功数を表すものではありません。実行結果は別の検証報告と併せて参照してください。

## 収録条件と確認した層

- `catalog.json` は公開配布名、種類、作者配布ページ、取得先の索引です。`download_link_policy: source_page_only` の項目は `download_url` も作者ページにし、公開データへ直接アーカイブURLを載せません。検証runnerは `github_release_asset` のファイル名を使って作者Release APIから取得先を解決します。同一 download URL と ID の重複はありません。
- 個人サイト 15 件は一次ページの HTML に掲載されたリンクを抽出。GitHub 37 件は偽SoSiReMiを発見元にし、作者リポジトリの Release API の `assets[].browser_download_url` と完全一致を確認しました。`source_url` は実際の作者リリースページです。
- 全 52 件で直接配布 URL への **HEAD が 200**（必要な通常のリダイレクトを追跡）。本文を取得していないため、ZIP/NARの内容、サイズ上限、種別、栞実体、利用条件の全容、Ourinでの動作を確認したことにはなりません。
- この収集作業ではアーカイブの GET、展開、実行、インストールを行っていません。検証 runner は別工程です。到達性はこの日時・環境に限ります。
- `engine_hint` は公開 README／配布説明に明記されたものだけです。配布一覧に複製された README を根拠に含むため、runner が実体を確認するまで暫定情報です。YAYA／里々／華和梨／灯を収録。プラグインの実装言語はSHIORIとして集計しません。未記載を非対応とは扱いません。
- `ninix-kagari`（ベースウェア）の言及を栞 KAGARI と誤認しないこと。UkagakaGhostMessenger 2.x は説明上、旧 akari を廃止して YAYA に変更されています。Aosora、その他旧栞は追加実体調査が必要です。
- 音声・SNS・DB・外部ウィンドウ等を扱うプラグインも含みます。配布されていることと、macOSで依存DLL／外部サービスまで動くことは別です。runner は外部送信や環境変更を安易に有効化しないでください。

## 権利・公開方針

公開するのは名前、URL、調査メタデータ、検証結果だけです。第三者の本文・辞書・画像・音声・アーカイブはここに転載／再配布しません。無料配布は再配布許諾を意味しません。作者ページ、同梱 README、シェル・音声ライブラリ等の個別条件を確認してください。Emily/Phase4.5 の一次ページには CC BY-NC 3.0 の表示がありますが、他作品や全同梱物へ一般化しません。ライセンス未確認の作品をオープンソース扱いしません。

## 発見元と拡張手順

| 発見元 | 次の列挙手順・注意 |
| --- | --- |
| [偽SoSiReMi](https://nikolat.github.io/sosiremi/) | HTML の `article` 単位に公開リポジトリ、category、download URL を取得。ghost / balloon / plugin だけ残し、作者 release assets と一致を確認。今回未採用の記録も残るため継続バッチを作れる。トップ HTML に掲載された `feed.json` / `rss2.xml` は更新差分の入口。カテゴリ・作者リンクで拡大し、実際にあるページ送りのみ追跡する。 |
| [SSP 公式配布](https://ssp.shillest.net/ghost.html) | ghost と専用 balloon のリンクを区別。旧 shell、SVG拡張データ、旧版を別作品として水増ししない。 |
| [月見図書館のバルーン](https://tukimibito.official.jp/ghost/ghost_balloon.html) | 青・白・黒・紅・晶を別配布 ZIP として収録。ページ内のゴースト配布ページへ広げられる。HTTP配布リンクは元の表記を保持。 |
| [mice’s nest](https://prayfortiny.net/ukagaka.html) | ゴースト3件と単体バルーンLiliesを収録。free shellのZIPは今回の3分類対象外。 |
| [nightworkの伺か配布](https://nightwork.sakura.ne.jp/ukagaka/ukagaka.html) | SSP plugin の専用ページを確認。AviUtl／サクラエディタ側のplugin、SAORI、MAKOTOをSSP pluginと混同しない。ghost専用ページにも拡大可能。 |
| [基本的に物置き](https://kogami.sakura.ne.jp/ghost.html) | 作品別ページへ遷移して最新配布URLを確認。Web表示スクリプト／動画生成ツールはghostではないため除外。作者の権利・切替ガイドも参照する。今回は索引確認のみ。 |
| [SSP通信施設](https://ssp.shillest.net/antenna.html) | ニュースから作者の一次配布ページへ移り、そこでURLと公開継続を確認。ニュース本文の配布告知だけで収録しない。 |
| [ななっちの運営サービス案内](https://kanadelab.ukagaka.net/) | 実際に掲載されたななろだ・うかフィードへのリンクから作品一覧を辿る。作品ページと直接配布リンクを対応付け、更新専用URLをNAR URLと混同しない。 |
| [GHOST TOWN / BALLOON TOWN](http://ghosttown.mikage.jp/) | SSP公式リンク集から発見。今回のWebツールではアクセスエラー。到達性を再確認してからカテゴリ一覧、作品、作者ページの順に辿る。未取得件数を対応率分母に混ぜない。 |
| [燕雀の伺か置き場](https://uu.getuploader.com/nextlast/index/filename/asc/1) | 一覧は58件、実際の次ページリンクを辿れる。ダウンロード確認画面を直接アーカイブURLと取り違えない。2026-11-25サービス終了告知あり。今回直接リンク未確定のため未収録。 |

全体の到達済みURLを集合で保持してループを防ぎ、download URLで重複排除します。同じ作品の複数版は最新を優先し、別バルーン／別配布物は作者の区分に従います。robots・アクセス規約・サーバ負荷を確認し、認証／購入／robots拒否／配布停止は別の理由付き状態へ分け、回避しません。並列数を抑え、同じ一覧を無用に再取得しません。

## 今回未収録・未完了

- 大手一覧や作者別ページの全件列挙は未完了。52件だけで「伺か全体の対応率」を算出しないこと。
- 里珠／MiyoJS／美坂／ese-shiori／偽栞／忍／翡翠／結奈／KAGARIの配布ゴーストを確実に識別する追加調査が残ります。engine自体や最小fixtureを一般配布ghostとして数えません。
- GHOST TOWN、里珠作者ページ、narazakaの入口はWebツールでアクセスエラーでした。通常のHTTPクライアントで里珠作者ページと `nayuki.sherry.jp` は取得できましたが、作者が示す `temp.nayuki.sherry.jp` はDNS解決失敗、narazakaはタイムアウトでした。robots拒否だとは断定せず、URLを推測補完しませんでした。
- konnatokojayaの作者ページにGoogle Drive／firestorageの配布リンクもありましたが、直接アーカイブと公開継続を未確認のため今回未収録。読み取り文字コードも再確認が必要です。
- BOOTH、ログイン必須、有料、配布停止に対する回避操作は行っていません。robots拒否を確認したURLは今回ありません（未確認サイトの許可を意味しません）。

## Geminiによる照合

`/opt/homebrew/bin/agy --help` と `agy models` で実CLI・モデルID `gemini-3.8-flash-high` を確認しました。別モデルへの置換はしていません。

初回は `--model gemini-3.8-flash-high --mode plan --sandbox --print-timeout 600s --print` でWeb調査を依頼しましたが、headlessモードがcommand権限を要求できず自動拒否。終了コード0でも「no output produced」のため成功扱いしていません。権限を緩和せず、親が取得した公開データを入力する方式へ切り替えました。

第2回は実際に取得した37件の公開メタデータ、作者release API照合結果、分類用の短いREADME抜粋を入力し、ツールを呼ばず分類・engine_hintの誤認を確認するよう実Geminiへ依頼。結果は正常に得られました（exit 0、計測 1147.89 秒）。CLIの指定timeoutと実測時間は一致していないため、timeout値を所要時間として記録しません。出力には未完のJSONと続く完全なJSONが混在していたため、最後の完全な37件をJSONとして構文確認し、元データとURL・種類が全件一致することを再確認しました。

- Geminiの指摘により、pluginのYAYAをSHIORIヒントから除外し、ライブラリのリンクだけの記載は栞確定に使いませんでした。
- `ayalilith` をDLLのみかもしれないとするGeminiの疑いは、[作者のinstall.txt](https://github.com/YAYA-shiori/ayalilith/blob/main/install.txt) の `type,ghost` / `name,紺野りりす` と `ghost/`・`shell/` の存在で再照合しました。ghost分類を維持し、リリース実体確認はrunnerへ引き継ぎます。
- `konnoyayame` はテンプレートゴーストです。一般的な完成キャラクター作品との用途差を対応率集計で留意してください。
- 実モデル出力を無検証で採用せず、公開名も元のREADME本文と一致するものだけ反映しました。

証跡（SHA-256。生ログは作業用一時領域に保管、第三者README抜粋を公開複製しない）:

| 証跡 | SHA-256 |
| --- | --- |
| `review-prompt.txt` | `e32536d272515b0df667baa428d57451d9bb19a7647e9dc5606a17e327f9cc8d` |
| `gemini-review-output.txt` | `be694fd36ced67e4c6726d061561baaf3af8b885e5e18bf3ef718399bc451452` |
| `review-result.json` | `4ebaa4e1ef5be93e71ac4777a374f72fe402b855c4f58a00be066beb58884274` |


## 52件の確認記録

HEADは全件200。GitHub作者Release内のasset一致確認を `Release API + HEAD`、作者HTMLを `作者HTML + HEAD` と表記します。実行結果ではありません。

| ID | 種別 | 公開名／配布ページ | 確認 |
| --- | --- | --- | --- |
| `unyu-lunchbox` | ghost | [うにゅうのお弁当箱](https://github.com/lost-nd-xxx/unyu_lunchbox/releases/tag/1.0.1) | Release API + HEAD |
| `ukaclock` | ghost | [うかくろっく](https://github.com/lost-nd-xxx/ukaclock/releases/tag/1.0.2) | Release API + HEAD |
| `luminousmodulation-radio` | ghost | [LuminousModulation_Radio](https://github.com/lost-nd-xxx/LuminousModulation_Radio/releases/tag/1.0.2) | Release API + HEAD |
| `jong-rinrin` | ghost | [雀-リンリン](https://github.com/nikolat/jong-rinrin/releases/tag/v1.1.0) | Release API + HEAD |
| `jong-whanwhan` | ghost | [雀-ホワンホワン](https://github.com/nikolat/jong-whanwhan/releases/tag/v1.1.0) | Release API + HEAD |
| `jong-chunchun` | ghost | [雀-チュンチュン](https://github.com/nikolat/jong-chunchun/releases/tag/v1.1.0) | Release API + HEAD |
| `post-and-komainu-v2` | ghost | [ポストと狛犬](https://github.com/ukatech/POST_and_KOMAINU_V2/releases/tag/38349596905) | Release API + HEAD |
| `ayalilith` | ghost | [紺野りりす](https://github.com/YAYA-shiori/ayalilith/releases/tag/38346446309) | Release API + HEAD |
| `konnoyayame` | ghost | [紺野ややめ](https://github.com/YAYA-shiori/konnoyayame/releases/tag/38346316034) | Release API + HEAD |
| `taidanasanosan` | ghost | [taidanaSanoSan](https://github.com/tukinami/taidanaSanoSan/releases/tag/v1.23.0) | Release API + HEAD |
| `something-like-balloon` | balloon | [something_like_balloon](https://github.com/lost-nd-xxx/something_like_balloon/releases/tag/1.0.0) | Release API + HEAD |
| `claudia` | ghost | [claudia](https://github.com/ponapalt/claudia/releases/tag/37863574936) | Release API + HEAD |
| `ukagakaghostmessenger` | plugin | [UkagakaGhostMessenger](https://github.com/lost-nd-xxx/UkagakaGhostMessenger/releases/tag/2.0.1) | Release API + HEAD |
| `ponyaduma` | ghost | [ぽにゃづま](https://github.com/ponapalt/ponyaduma/releases/tag/v20260928161809-2354c2b) | Release API + HEAD |
| `knowledgeable-kernel` | ghost | [knowledgeable_kernel](https://github.com/Tatakinov/knowledgeable_kernel/releases/tag/v2.0.0) | Release API + HEAD |
| `tmidi-msg` | plugin | [tmidi_msg](https://github.com/JiayuYangX/tmidi_msg/releases/tag/v1.1.0) | Release API + HEAD |
| `ghost-in-a-nutshell` | ghost | [ghost_in_a_nutshell](https://github.com/syobocat/ghost_in_a_nutshell/releases/tag/v0.1.1) | Release API + HEAD |
| `my-own-translator` | ghost | [my_own_translator](https://github.com/Tatakinov/my_own_translator/releases/tag/v2.1.0) | Release API + HEAD |
| `doll-at-the-bay-window` | ghost | [doll_at_the_bay_window](https://github.com/tukinami/doll_at_the_bay_window/releases/tag/v1.0.0) | Release API + HEAD |
| `stampcollection` | plugin | [stampcollection](https://github.com/YAYA-shiori/stampcollection/releases/tag/v20260330102740-79221c6) | Release API + HEAD |
| `wallet-of-unyu` | plugin | [Wallet of Unyu](https://github.com/nikolat/wallet_of_unyu/releases/tag/v1.2.0) | Release API + HEAD |
| `hamirlore` | ghost | [HamirLore](https://github.com/Shimofumi/HamirLore/releases/tag/v2.0.0) | Release API + HEAD |
| `talismanic-beast-pattern` | balloon | [魔除けの獣面紋](https://github.com/tukinami/talismanic_beast_pattern/releases/tag/v1.1.0) | Release API + HEAD |
| `banjou-no-sumikko-de` | ghost | [banjou_no_sumikko_de](https://github.com/Tatakinov/banjou_no_sumikko_de/releases/tag/1.0.0) | Release API + HEAD |
| `jong-bari` | ghost | [雀々BARIBARI](https://github.com/nikolat/jong-bari/releases/tag/v1.0.6) | Release API + HEAD |
| `wind-memory-petit` | ghost | [wind_memory_petit](https://github.com/Tatakinov/wind_memory_petit/releases/tag/v1.0.0) | Release API + HEAD |
| `yomibito-minarai` | ghost | [yomibito_minarai](https://github.com/Tatakinov/yomibito_minarai/releases/tag/v1.1.0) | Release API + HEAD |
| `bouyomi` | plugin | [Bouyomi](https://github.com/apxxxxxxe/Bouyomi/releases/tag/v1.5.1) | Release API + HEAD |
| `ukaten` | plugin | [うかてん](https://github.com/nikolat/ukaten/releases/tag/v1.0) | Release API + HEAD |
| `ukadonyu` | plugin | [うかどんゅう](https://github.com/nikolat/ukadonyu/releases/tag/v2.2) | Release API + HEAD |
| `ukagakaplugin-cevio-talker` | plugin | [ukagakaPlugin_CeVIO-Talker](https://github.com/ambergon/ukagakaPlugin_CeVIO-Talker/releases/tag/version1.0.7) | Release API + HEAD |
| `ssp-aivoice` | plugin | [SSP-AIVOICE](https://github.com/opera7133/SSP-AIVOICE/releases/tag/v1.0.2) | Release API + HEAD |
| `ukagakaplugin-getwindowtitle` | plugin | [ukagakaPlugin_getWindowTitle](https://github.com/ambergon/ukagakaPlugin_getWindowTitle/releases/tag/1.0.0) | Release API + HEAD |
| `ukagakaplugin-dbdiary` | plugin | [UkagakaPlugin_DBdiary](https://github.com/ambergon/UkagakaPlugin_DBdiary/releases/tag/1.0.1) | Release API + HEAD |
| `jb-standard-balloon` | balloon | [雀卓用透明バルーン](https://github.com/nikolat/jb-standard-balloon/releases/tag/v1.0.0) | Release API + HEAD |
| `charamelnetwork` | plugin | [CharameLNetwork](https://github.com/nikolat/CharameLNetwork/releases/tag/v0.5) | Release API + HEAD |
| `balloonselector` | plugin | [balloonselector](https://github.com/nikolat/balloonselector/releases/tag/v2.4.0) | Release API + HEAD |
| `futatsugi-balloon-0` | balloon | [フタツギノフウセン・青](https://tukimibito.official.jp/ghost/ghost_balloon.html) | 作者HTML + HEAD |
| `futatsugi-balloon-1` | balloon | [フタツギノフウセン・白](https://tukimibito.official.jp/ghost/ghost_balloon.html) | 作者HTML + HEAD |
| `futatsugi-balloon-2` | balloon | [フタツギノフウセン・黒](https://tukimibito.official.jp/ghost/ghost_balloon.html) | 作者HTML + HEAD |
| `futatsugi-balloon-3` | balloon | [フタツギノフウセン・紅](https://tukimibito.official.jp/ghost/ghost_balloon.html) | 作者HTML + HEAD |
| `futatsugi-balloon-4` | balloon | [フタツギノフウセン・晶](https://tukimibito.official.jp/ghost/ghost_balloon.html) | 作者HTML + HEAD |
| `cafe-adapt` | ghost | [Adaptation](https://prayfortiny.net/ukagaka.html) | 作者HTML + HEAD |
| `for-the-tiny` | ghost | [小さなきみと歌ううた](https://prayfortiny.net/ukagaka.html) | 作者HTML + HEAD |
| `miku-glitched-girl` | ghost | [未紅はグリッチガール](https://prayfortiny.net/ukagaka.html) | 作者HTML + HEAD |
| `lilies` | balloon | [Lilies](https://prayfortiny.net/ukagaka.html) | 作者HTML + HEAD |
| `emily4` | ghost | [Emily/Phase4.5](https://ssp.shillest.net/ghost.html) | 作者HTML + HEAD |
| `emily4-balloon` | balloon | [Emily/Phase4.5 専用バルーン](https://ssp.shillest.net/ghost.html) | 作者HTML + HEAD |
| `mobilemaster` | ghost | [the MobileMaster](https://ssp.shillest.net/ghost.html) | 作者HTML + HEAD |
| `k3r` | ghost | [このみ3rd/Reloaded](https://ssp.shillest.net/ghost.html) | 作者HTML + HEAD |
| `syoko` | ghost | [レジ打ちファイター翔子](https://ssp.shillest.net/ghost.html) | 作者HTML + HEAD |
| `nightwork-bouyomi-plugin` | plugin | [棒読みちゃん連携プラグイン](https://nightwork.sakura.ne.jp/ukagaka/tools/BouyomiChan_PLUGIN/BouyomiChan_PLUGIN.html) | 作者HTML + HEAD |

## 追加バッチ2の確認記録

`catalog-batch2.json` は初回と重複しない40件。偽SoSiReMiの取得済みHTMLに掲載された対象3カテゴリの未採用38件を作者release assetsと一致確認し、すべてHEAD200。さらに [maemako WORKS](https://efasus.sakura.ne.jp/ukagaka_works.html) の作者ページから真絵（mae）採用の「佳由」「深果」を確認し、掲載された直接NARリンクがHEAD200であることを確認しました。この2件は同じNARへの「SHIORI本体」と「ゴースト」の重複リンクを1件に統合済みです。Asymmetry PrologueのLZHはゴースト配布ではないため除外。初回と同様、アーカイブ本文は取得・実行していません。

この追加分は担当エージェントが実HTML／作者Release APIと照合したものです。Geminiがレビューした37件と区別し、追加40件もGeminiで確認したとは主張しません。sakura-restoreのfirst.dllは公開READMEの明記だけで、Ourinで対応するという意味ではありません。真絵も同様です。

| ID | 種別 | 公開名／配布ページ | 確認 |
| --- | --- | --- | --- |
| `sakura-restore` | ghost | [sakura-restore](https://github.com/JiayuYangX/sakura-restore/releases/tag/261005) | Release API + HEAD |
| `lilynovelplayer` | ghost | [LilyNovelPlayer](https://github.com/lost-nd-xxx/LilyNovelPlayer/releases/tag/v1.0.5) | Release API + HEAD |
| `walk-with-unyu` | ghost | [walk_with_unyu](https://github.com/lost-nd-xxx/walk_with_unyu/releases/tag/v1.0.1) | Release API + HEAD |
| `ugmnavigator-umechan` | ghost | [UGMNavigator_Umechan](https://github.com/lost-nd-xxx/UGMNavigator_Umechan/releases/tag/1.0.4) | Release API + HEAD |
| `weathertimecapsule` | ghost | [WeatherTimeCapsule](https://github.com/lost-nd-xxx/WeatherTimeCapsule/releases/tag/1.0.2) | Release API + HEAD |
| `mancala-player-amethyst` | ghost | [mancala-player-amethyst](https://github.com/lost-nd-xxx/mancala-player-amethyst/releases/tag/v1.0.0) | Release API + HEAD |
| `mancala-player-amber` | ghost | [mancala-player-amber](https://github.com/lost-nd-xxx/mancala-player-amber/releases/tag/v1.0.0) | Release API + HEAD |
| `mancala-board-ghost` | ghost | [mancala-board-ghost](https://github.com/lost-nd-xxx/mancala-board-ghost/releases/tag/v1.0.1) | Release API + HEAD |
| `hopefullyeverafter-yume` | ghost | [HopefullyEverAfter_Yume](https://github.com/lost-nd-xxx/HopefullyEverAfter_Yume/releases/tag/1.0.1) | Release API + HEAD |
| `flele-aya` | ghost | [flele_aya](https://github.com/YAYA-shiori/flele_aya/releases/tag/v20260425170548-16c3df0) | Release API + HEAD |
| `fortuneteller-finiteseaslugtheorem` | ghost | [FortuneTeller_FiniteSeaslugTheorem](https://github.com/lost-nd-xxx/FortuneTeller_FiniteSeaslugTheorem/releases/tag/1.0.0) | Release API + HEAD |
| `yousaveme-iloveyou` | ghost | [YouSaveMe_ILoveYou](https://github.com/lost-nd-xxx/YouSaveMe_ILoveYou/releases/tag/1.0.0) | Release API + HEAD |
| `perpetual-whisper` | ghost | [perpetual_whisper](https://github.com/lost-nd-xxx/perpetual_whisper/releases/tag/1.0.0) | Release API + HEAD |
| `the-hand` | ghost | [_the_hand_](https://github.com/YAYA-shiori/_the_hand_/releases/tag/v20260223112405-124d41a) | Release API + HEAD |
| `ukagaka-simultaneous-interpreter` | ghost | [ukagaka-simultaneous-interpreter](https://github.com/nikolat/ukagaka-simultaneous-interpreter/releases/tag/v1.0.1) | Release API + HEAD |
| `countdown-to-the-end` | ghost | [countdown_to_the_end](https://github.com/lost-nd-xxx/countdown_to_the_end/releases/tag/1.0.0) | Release API + HEAD |
| `youto` | ghost | [Youto](https://github.com/apxxxxxxe/Youto/releases/tag/v1.0.5) | Release API + HEAD |
| `nostalk` | ghost | [nostalk](https://github.com/nikolat/nostalk/releases/tag/v0.6.0) | Release API + HEAD |
| `who-is-cursing-him` | ghost | [who_is_cursing_him](https://github.com/tukinami/who_is_cursing_him/releases/tag/v1.0.0) | Release API + HEAD |
| `yada-yada-yada` | ghost | [Yada-Yada-Yada](https://github.com/tukinami/Yada-Yada-Yada/releases/tag/v1.0.0) | Release API + HEAD |
| `incubation-of-animas` | ghost | [incubation_of_animas](https://github.com/tukinami/incubation_of_animas/releases/tag/v1.0.0) | Release API + HEAD |
| `yakutai-nashi` | ghost | [yakutai_nashi](https://github.com/lost-nd-xxx/yakutai_nashi/releases/tag/1.0.1) | Release API + HEAD |
| `sakanaiusowohitotsudake` | ghost | [SakanaiUsoWoHitotsuDake](https://github.com/lost-nd-xxx/SakanaiUsoWoHitotsuDake/releases/tag/1.0.0) | Release API + HEAD |
| `ghostbook` | ghost | [ごーすとじてん](https://github.com/nikolat/ghostbook/releases/tag/v1.0.0) | Release API + HEAD |
| `bee` | ghost | [びーふれんず](https://github.com/nikolat/bee/releases/tag/v1.0.0) | Release API + HEAD |
| `shennong-kanadome` | ghost | [Shennong_kanadome](https://github.com/Shimofumi/Shennong_kanadome/releases/tag/v1.0.0) | Release API + HEAD |
| `taromati2` | ghost | [Taromati2](https://github.com/Taromati2/package-factory/releases/tag/37566752565) | Release API + HEAD |
| `oyatsu-ha-macaroni` | ghost | [Oyatsu_ha_Macaroni](https://github.com/Shimofumi/Oyatsu_ha_Macaroni/releases/tag/v1.0.0) | Release API + HEAD |
| `ukagaka-hakoirimusume` | ghost | [箱入り娘](https://github.com/nikolat/ukagaka-hakoirimusume/releases/tag/v1.0.0) | Release API + HEAD |
| `shellbook` | ghost | [しぇるずかん](https://github.com/nikolat/shellbook/releases/tag/v1.0.3) | Release API + HEAD |
| `reshibainu` | ghost | [れしばいぬ](https://github.com/nikolat/reshibainu/releases/tag/v1.0.0) | Release API + HEAD |
| `crawler-uploader` | ghost | [クローラ＆ロダ](https://github.com/nikolat/crawler_uploader/releases/tag/v1.0.0) | Release API + HEAD |
| `desktop-tempter` | ghost | [desktop_tempter](https://github.com/Tatakinov/desktop_tempter/releases/tag/1.0.0) | Release API + HEAD |
| `ukagaka-party-parrot` | ghost | [Party Parrot](https://github.com/nikolat/ukagaka-party-parrot/releases/tag/v1.6.0) | Release API + HEAD |
| `sudohaikuyu` | plugin | [すどはいくゅう](https://github.com/nikolat/sudohaikuyu/releases/tag/v0.4) | Release API + HEAD |
| `desktop-tempter-casino-chip-blue` | ghost | [desktop_tempter_casino_chip_blue](https://github.com/Tatakinov/desktop_tempter_casino_chip_blue/releases/tag/1.0.0) | Release API + HEAD |
| `desktop-tempter-casino-chip-green` | ghost | [desktop_tempter_casino_chip_green](https://github.com/Tatakinov/desktop_tempter_casino_chip_green/releases/tag/1.0.0) | Release API + HEAD |
| `desktop-tempter-casino-chip-red` | ghost | [desktop_tempter_casino_chip_red](https://github.com/Tatakinov/desktop_tempter_casino_chip_red/releases/tag/1.0.0) | Release API + HEAD |
| `kayu` | ghost | [佳由 period 8](https://efasus.sakura.ne.jp/ukagaka_works.html) | 作者HTML + HEAD |
| `mika` | ghost | [深果 period 9](https://efasus.sakura.ne.jp/ukagaka_works.html) | 作者HTML + HEAD |

次の拡張では[ゴーストマスカレード7の作者あとがき](https://earlduant.blog.fc2.com/blog-entry-923.html)で偽栞使用を明示された「偽ねこみこ」、およびGM3「偽コンフィズリー」の作者配布元を優先して確認できます。今回は記事だけ確認し、作者の現行直接配布URLを未確定のため未収録です。栞「結奈」は作者名の「高遠結奈」と区別して調べてください。取得済み偽SoSiReMiトップHTMLの全88記事のうち、対象カテゴリは75記事であり、初回37＋追加38でその索引スナップショット内の対象分を列挙済みです（同サイトの将来更新・他一覧・伺か全体の網羅を意味しません）。残る13記事はshell・supplement等で今回指定3分類から除外しました。

## 実検証で判明したカタログ補正（2026-10-25）

- `ukaclock`: 偽SoSiReMi掲載リンクの `digital_seconds.nar` は追加シェルでした。同じ[作者Release](https://github.com/lost-nd-xxx/ukaclock/releases/tag/1.0.2)の本体 `lnx_ukaclock.nar` へ補正し、HEAD200を確認しました。旧URLの構造不足をゴースト非対応と集計しません。本体のruntime検証は補正後の別runで行います。
- `doll-at-the-bay-window`（追想の窓辺）: 公開READMEの作者方針に従い、[作者配布ページ](https://github.com/tukinami/doll_at_the_bay_window/releases/tag/v1.0.0)のみを案内します。作者は配布ページへのリンクを認め、アーカイブへの直接リンクを認めていません。`download_url` を `source_url` と同一にし、`github_release_asset: doll_at_the_bay_window.nar` と `download_link_policy: source_page_only` を追加しました。公開Web・JSON・文書も作者ページへ誘導し、runnerが解決した一時的な取得URLを公開しないでください。


- 追加確認した次の3作品も、各作品の公開READMEに「配布ページ可・アーカイブ直リンク不可」と明記されているため、同じ `source_page_only` と `github_release_asset` 方式へ補正しました。`catalog-batch2.json` に重複掲載される2作品にも同じ方針を反映しています。
  - [taidanaSanoSan](https://github.com/tukinami/taidanaSanoSan/releases/tag/v1.23.0)
  - [who_is_cursing_him](https://github.com/tukinami/who_is_cursing_him/releases/tag/v1.0.0)
  - [Yada-Yada-Yada](https://github.com/tukinami/Yada-Yada-Yada/releases/tag/v1.0.0)
- この制限は作品ごとの一次資料を確認した結果です。同作者でも未確認の作品へ一律に適用していません。

以上はカタログと公開導線の補正で、Ourinの互換性修正や動作成功を意味しません。
