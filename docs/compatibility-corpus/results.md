# 配布物の互換性検証結果

静的な構成確認は、アプリへのインストール成功や実画面の互換性を保証しません。

| 検証層 | 件数 | 率 | 分母の定義 |
| --- | ---: | ---: | --- |
| download | 92/92 | 100.0% | Downloaded successfully / selected catalog items |
| import | 91/92 | 98.91% | Recognized static entry structure / successful downloads (not app install) |
| runtime_tested | 59/91 | 64.84% | Explicit runtime_executed evidence / recognized static structures |
| runtime_pass | 34/59 | 57.63% | Probe runtime pass / items with runtime_executed evidence |
| runtime_pass_of_selected | 34/92 | 36.96% | Probe runtime pass / all selected catalog items |

選択件数: 92。再取得せず結果を再利用: 0 件。

| 配布物 | 種類 | 取得 | 静的構成 | 実行 | 削除 | 配布元 | ダウンロード |
| --- | --- | --- | --- | --- | --- | --- | --- |
| うにゅうのお弁当箱 | ghost | success | pass | partial | pass | [link](<https://github.com/lost-nd-xxx/unyu_lunchbox/releases/tag/1.0.1>) | [link](<https://github.com/lost-nd-xxx/unyu_lunchbox/releases/download/1.0.1/lnx_unyu_lunchbox.nar>) |
| うかくろっく | ghost | success | pass | pass | pass | [link](<https://github.com/lost-nd-xxx/ukaclock/releases/tag/1.0.2>) | [link](<https://github.com/lost-nd-xxx/ukaclock/releases/download/1.0.2/lnx_ukaclock.nar>) |
| LuminousModulation_Radio | ghost | success | pass | pass | pass | [link](<https://github.com/lost-nd-xxx/LuminousModulation_Radio/releases/tag/1.0.2>) | [link](<https://github.com/lost-nd-xxx/LuminousModulation_Radio/releases/download/1.0.2/LuminousModulation_Radio.nar>) |
| 雀-リンリン | ghost | success | pass | pass | pass | [link](<https://github.com/nikolat/jong-rinrin/releases/tag/v1.1.0>) | [link](<https://github.com/nikolat/jong-rinrin/releases/download/v1.1.0/jong-rinrin.nar>) |
| 雀-ホワンホワン | ghost | success | pass | partial | pass | [link](<https://github.com/nikolat/jong-whanwhan/releases/tag/v1.1.0>) | [link](<https://github.com/nikolat/jong-whanwhan/releases/download/v1.1.0/jong-whanwhan.nar>) |
| 雀-チュンチュン | ghost | success | pass | pass | pass | [link](<https://github.com/nikolat/jong-chunchun/releases/tag/v1.1.0>) | [link](<https://github.com/nikolat/jong-chunchun/releases/download/v1.1.0/jong-chunchun.nar>) |
| ポストと狛犬 | ghost | success | pass | pass | pass | [link](<https://github.com/ukatech/POST_and_KOMAINU_V2/releases/tag/38349596905>) | [link](<https://github.com/ukatech/POST_and_KOMAINU_V2/releases/download/38349596905/POST_and_KOMAINU_V2.nar>) |
| 紺野りりす | ghost | success | pass | partial | pass | [link](<https://github.com/YAYA-shiori/ayalilith/releases/tag/38346446309>) | [link](<https://github.com/YAYA-shiori/ayalilith/releases/download/38346446309/ayalilith.nar>) |
| 紺野ややめ | ghost | success | pass | pass | pass | [link](<https://github.com/YAYA-shiori/konnoyayame/releases/tag/38346316034>) | [link](<https://github.com/YAYA-shiori/konnoyayame/releases/download/38346316034/konnoyayame.nar>) |
| taidanaSanoSan | ghost | success | pass | pass | pass | [link](<https://github.com/tukinami/taidanaSanoSan/releases/tag/v1.23.0>) | [link](<https://github.com/tukinami/taidanaSanoSan/releases/tag/v1.23.0>) |
| something_like_balloon | balloon | success | pass | partial | pass | [link](<https://github.com/lost-nd-xxx/something_like_balloon/releases/tag/1.0.0>) | [link](<https://github.com/lost-nd-xxx/something_like_balloon/releases/download/1.0.0/something_like_berry_tart.nar>) |
| claudia | ghost | success | pass | pass | pass | [link](<https://github.com/ponapalt/claudia/releases/tag/37863574936>) | [link](<https://github.com/ponapalt/claudia/releases/download/37863574936/claudia.nar>) |
| UkagakaGhostMessenger | plugin | success | pass | unsupported | pass | [link](<https://github.com/lost-nd-xxx/UkagakaGhostMessenger/releases/tag/2.0.1>) | [link](<https://github.com/lost-nd-xxx/UkagakaGhostMessenger/releases/download/2.0.1/UkagakaGhostMessenger.nar>) |
| ぽにゃづま | ghost | success | pass | partial | pass | [link](<https://github.com/ponapalt/ponyaduma/releases/tag/v20260928161809-2354c2b>) | [link](<https://github.com/ponapalt/ponyaduma/releases/download/v20260928161809-2354c2b/ponyaduma.nar>) |
| knowledgeable_kernel | ghost | success | pass | error | pass | [link](<https://github.com/Tatakinov/knowledgeable_kernel/releases/tag/v2.0.0>) | [link](<https://github.com/Tatakinov/knowledgeable_kernel/releases/download/v2.0.0/knowledgeable_kernel.nar>) |
| tmidi_msg | plugin | success | pass | unsupported | pass | [link](<https://github.com/JiayuYangX/tmidi_msg/releases/tag/v1.1.0>) | [link](<https://github.com/JiayuYangX/tmidi_msg/releases/download/v1.1.0/tmidi_msg.nar>) |
| ghost_in_a_nutshell | ghost | success | pass | unsupported | pass | [link](<https://github.com/syobocat/ghost_in_a_nutshell/releases/tag/v0.1.1>) | [link](<https://github.com/syobocat/ghost_in_a_nutshell/releases/download/v0.1.1/ghost_in_a_nutshell.nar>) |
| my_own_translator | ghost | success | pass | pass | pass | [link](<https://github.com/Tatakinov/my_own_translator/releases/tag/v2.1.0>) | [link](<https://github.com/Tatakinov/my_own_translator/releases/download/v2.1.0/my_own_translator.nar>) |
| doll_at_the_bay_window | ghost | success | pass | unsupported | pass | [link](<https://github.com/tukinami/doll_at_the_bay_window/releases/tag/v1.0.0>) | [link](<https://github.com/tukinami/doll_at_the_bay_window/releases/tag/v1.0.0>) |
| stampcollection | plugin | success | pass | unsupported | pass | [link](<https://github.com/YAYA-shiori/stampcollection/releases/tag/v20260330102740-79221c6>) | [link](<https://github.com/YAYA-shiori/stampcollection/releases/download/v20260330102740-79221c6/stampcollection.nar>) |
| Wallet of Unyu | plugin | success | pass | unsupported | pass | [link](<https://github.com/nikolat/wallet_of_unyu/releases/tag/v1.2.0>) | [link](<https://github.com/nikolat/wallet_of_unyu/releases/download/v1.2.0/wallet_of_unyu.nar>) |
| HamirLore | ghost | success | pass | pass | pass | [link](<https://github.com/Shimofumi/HamirLore/releases/tag/v2.0.0>) | [link](<https://github.com/Shimofumi/HamirLore/releases/download/v2.0.0/HamirLore.nar>) |
| 魔除けの獣面紋 | balloon | success | pass | partial | pass | [link](<https://github.com/tukinami/talismanic_beast_pattern/releases/tag/v1.1.0>) | [link](<https://github.com/tukinami/talismanic_beast_pattern/releases/download/v1.1.0/talismanic_beast_pattern.nar>) |
| banjou_no_sumikko_de | ghost | success | pass | error | pass | [link](<https://github.com/Tatakinov/banjou_no_sumikko_de/releases/tag/1.0.0>) | [link](<https://github.com/Tatakinov/banjou_no_sumikko_de/releases/download/1.0.0/banjou_no_sumikko_de.nar>) |
| 雀々BARIBARI | ghost | success | pass | partial | pass | [link](<https://github.com/nikolat/jong-bari/releases/tag/v1.0.6>) | [link](<https://github.com/nikolat/jong-bari/releases/download/v1.0.6/jong-bari.nar>) |
| wind_memory_petit | ghost | success | pass | pass | pass | [link](<https://github.com/Tatakinov/wind_memory_petit/releases/tag/v1.0.0>) | [link](<https://github.com/Tatakinov/wind_memory_petit/releases/download/v1.0.0/wind_memory_petit.nar>) |
| yomibito_minarai | ghost | success | pass | error | pass | [link](<https://github.com/Tatakinov/yomibito_minarai/releases/tag/v1.1.0>) | [link](<https://github.com/Tatakinov/yomibito_minarai/releases/download/v1.1.0/yomibito_minarai.nar>) |
| Bouyomi | plugin | success | pass | unsupported | pass | [link](<https://github.com/apxxxxxxe/Bouyomi/releases/tag/v1.5.1>) | [link](<https://github.com/apxxxxxxe/Bouyomi/releases/download/v1.5.1/Bouyomi.nar>) |
| うかてん | plugin | success | pass | unsupported | pass | [link](<https://github.com/nikolat/ukaten/releases/tag/v1.0>) | [link](<https://github.com/nikolat/ukaten/releases/download/v1.0/ukaten.nar>) |
| うかどんゅう | plugin | success | pass | unsupported | pass | [link](<https://github.com/nikolat/ukadonyu/releases/tag/v2.2>) | [link](<https://github.com/nikolat/ukadonyu/releases/download/v2.2/ukadonyu.nar>) |
| ukagakaPlugin_CeVIO-Talker | plugin | success | pass | unsupported | pass | [link](<https://github.com/ambergon/ukagakaPlugin_CeVIO-Talker/releases/tag/version1.0.7>) | [link](<https://github.com/ambergon/ukagakaPlugin_CeVIO-Talker/releases/download/version1.0.7/ukagakaPlugin_CeVIO-Talker.nar>) |
| SSP-AIVOICE | plugin | success | pass | unsupported | pass | [link](<https://github.com/opera7133/SSP-AIVOICE/releases/tag/v1.0.2>) | [link](<https://github.com/opera7133/SSP-AIVOICE/releases/download/v1.0.2/AIVOICE.nar>) |
| ukagakaPlugin_getWindowTitle | plugin | success | pass | unsupported | pass | [link](<https://github.com/ambergon/ukagakaPlugin_getWindowTitle/releases/tag/1.0.0>) | [link](<https://github.com/ambergon/ukagakaPlugin_getWindowTitle/releases/download/1.0.0/ukagakaPlugin_getWindowTitle.nar>) |
| UkagakaPlugin_DBdiary | plugin | success | pass | unsupported | pass | [link](<https://github.com/ambergon/UkagakaPlugin_DBdiary/releases/tag/1.0.1>) | [link](<https://github.com/ambergon/UkagakaPlugin_DBdiary/releases/download/1.0.1/UkagakaPlugin_DBdiary.nar>) |
| 雀卓用透明バルーン | balloon | success | not_checked | unverified | pass | [link](<https://github.com/nikolat/jb-standard-balloon/releases/tag/v1.0.0>) | [link](<https://github.com/nikolat/jb-standard-balloon/releases/download/v1.0.0/jb-standard-balloon.nar>) |
| CharameLNetwork | plugin | success | pass | unsupported | pass | [link](<https://github.com/nikolat/CharameLNetwork/releases/tag/v0.5>) | [link](<https://github.com/nikolat/CharameLNetwork/releases/download/v0.5/CharameLNetwork.nar>) |
| balloonselector | plugin | success | pass | unsupported | pass | [link](<https://github.com/nikolat/balloonselector/releases/tag/v2.4.0>) | [link](<https://github.com/nikolat/balloonselector/releases/download/v2.4.0/balloonselector.nar>) |
| フタツギノフウセン・青 | balloon | success | pass | partial | pass | [link](<https://tukimibito.official.jp/ghost/ghost_balloon.html>) | [link](<http://tukimibito.official.jp/ghost/B0_puppets.zip>) |
| フタツギノフウセン・白 | balloon | success | pass | partial | pass | [link](<https://tukimibito.official.jp/ghost/ghost_balloon.html>) | [link](<http://tukimibito.official.jp/ghost/B1_puppets.zip>) |
| フタツギノフウセン・黒 | balloon | success | pass | partial | pass | [link](<https://tukimibito.official.jp/ghost/ghost_balloon.html>) | [link](<http://tukimibito.official.jp/ghost/B2_puppets.zip>) |
| フタツギノフウセン・紅 | balloon | success | pass | partial | pass | [link](<https://tukimibito.official.jp/ghost/ghost_balloon.html>) | [link](<http://tukimibito.official.jp/ghost/B3_puppets.zip>) |
| フタツギノフウセン・晶 | balloon | success | pass | partial | pass | [link](<https://tukimibito.official.jp/ghost/ghost_balloon.html>) | [link](<http://tukimibito.official.jp/ghost/B4_puppets.zip>) |
| Adaptation | ghost | success | pass | pass | pass | [link](<https://prayfortiny.net/ukagaka.html>) | [link](<https://prayfortiny.net/ukagaka/nar/cafe_adapt.nar>) |
| 小さなきみと歌ううた | ghost | success | pass | pass | pass | [link](<https://prayfortiny.net/ukagaka.html>) | [link](<https://prayfortiny.net/ukagaka/nar/for_the_tiny.nar>) |
| 未紅はグリッチガール | ghost | success | pass | pass | pass | [link](<https://prayfortiny.net/ukagaka.html>) | [link](<https://prayfortiny.net/ukagaka/nar/miku_glitched_girl.nar>) |
| Lilies | balloon | success | pass | partial | pass | [link](<https://prayfortiny.net/ukagaka.html>) | [link](<https://prayfortiny.net/ukagaka/nar/lilies.nar>) |
| Emily/Phase4.5 | ghost | success | pass | pass | pass | [link](<https://ssp.shillest.net/ghost.html>) | [link](<https://ssp.shillest.net/ghost/emily4.nar>) |
| Emily/Phase4.5 専用バルーン | balloon | success | pass | partial | pass | [link](<https://ssp.shillest.net/ghost.html>) | [link](<https://ssp.shillest.net/ghost/emily4-balloon.nar>) |
| the MobileMaster | ghost | success | pass | pass | pass | [link](<https://ssp.shillest.net/ghost.html>) | [link](<https://ssp.shillest.net/ghost/mobilemaster.nar>) |
| このみ3rd/Reloaded | ghost | success | pass | pass | pass | [link](<https://ssp.shillest.net/ghost.html>) | [link](<https://ssp.shillest.net/ghost/K3R.nar>) |
| レジ打ちファイター翔子 | ghost | success | pass | pass | pass | [link](<https://ssp.shillest.net/ghost.html>) | [link](<https://ssp.shillest.net/ghost/syoko.nar>) |
| 棒読みちゃん連携プラグイン | plugin | success | pass | unsupported | pass | [link](<https://nightwork.sakura.ne.jp/ukagaka/tools/BouyomiChan_PLUGIN/BouyomiChan_PLUGIN.html>) | [link](<https://nightwork.sakura.ne.jp/ukagaka/tools/BouyomiChan_PLUGIN/BouyomiChan_PLUGIN%2820241208%29.nar>) |
| sakura-restore | ghost | success | pass | unsupported | pass | [link](<https://github.com/JiayuYangX/sakura-restore/releases/tag/261005>) | [link](<https://github.com/JiayuYangX/sakura-restore/releases/download/261005/first.nar>) |
| LilyNovelPlayer | ghost | success | pass | partial | pass | [link](<https://github.com/lost-nd-xxx/LilyNovelPlayer/releases/tag/v1.0.5>) | [link](<https://github.com/lost-nd-xxx/LilyNovelPlayer/releases/download/v1.0.5/LilyNovelPlayer.nar>) |
| walk_with_unyu | ghost | success | pass | pass | pass | [link](<https://github.com/lost-nd-xxx/walk_with_unyu/releases/tag/v1.0.1>) | [link](<https://github.com/lost-nd-xxx/walk_with_unyu/releases/download/v1.0.1/lnx_walk_with_unyu.nar>) |
| UGMNavigator_Umechan | ghost | success | pass | pass | pass | [link](<https://github.com/lost-nd-xxx/UGMNavigator_Umechan/releases/tag/1.0.4>) | [link](<https://github.com/lost-nd-xxx/UGMNavigator_Umechan/releases/download/1.0.4/UGMNavigator_Umechan.nar>) |
| WeatherTimeCapsule | ghost | success | pass | partial | pass | [link](<https://github.com/lost-nd-xxx/WeatherTimeCapsule/releases/tag/1.0.2>) | [link](<https://github.com/lost-nd-xxx/WeatherTimeCapsule/releases/download/1.0.2/WeatherTimeCapsule.nar>) |
| mancala-player-amethyst | ghost | success | pass | pass | pass | [link](<https://github.com/lost-nd-xxx/mancala-player-amethyst/releases/tag/v1.0.0>) | [link](<https://github.com/lost-nd-xxx/mancala-player-amethyst/releases/download/v1.0.0/mancala-player-amethyst.nar>) |
| mancala-player-amber | ghost | success | pass | partial | pass | [link](<https://github.com/lost-nd-xxx/mancala-player-amber/releases/tag/v1.0.0>) | [link](<https://github.com/lost-nd-xxx/mancala-player-amber/releases/download/v1.0.0/mancala-player-amber.nar>) |
| mancala-board-ghost | ghost | success | pass | unsupported | pass | [link](<https://github.com/lost-nd-xxx/mancala-board-ghost/releases/tag/v1.0.1>) | [link](<https://github.com/lost-nd-xxx/mancala-board-ghost/releases/download/v1.0.1/mancala-board-ghost.nar>) |
| HopefullyEverAfter_Yume | ghost | success | pass | partial | pass | [link](<https://github.com/lost-nd-xxx/HopefullyEverAfter_Yume/releases/tag/1.0.1>) | [link](<https://github.com/lost-nd-xxx/HopefullyEverAfter_Yume/releases/download/1.0.1/HopefullyEverAfter_Yume.nar>) |
| flele_aya | ghost | success | pass | partial | pass | [link](<https://github.com/YAYA-shiori/flele_aya/releases/tag/v20260425170548-16c3df0>) | [link](<https://github.com/YAYA-shiori/flele_aya/releases/download/v20260425170548-16c3df0/flele_aya.nar>) |
| FortuneTeller_FiniteSeaslugTheorem | ghost | success | pass | pass | pass | [link](<https://github.com/lost-nd-xxx/FortuneTeller_FiniteSeaslugTheorem/releases/tag/1.0.0>) | [link](<https://github.com/lost-nd-xxx/FortuneTeller_FiniteSeaslugTheorem/releases/download/1.0.0/FortuneTeller_FiniteSeaslugTheorem.nar>) |
| YouSaveMe_ILoveYou | ghost | success | pass | pass | pass | [link](<https://github.com/lost-nd-xxx/YouSaveMe_ILoveYou/releases/tag/1.0.0>) | [link](<https://github.com/lost-nd-xxx/YouSaveMe_ILoveYou/releases/download/1.0.0/YouSaveMe_ILoveYou.nar>) |
| perpetual_whisper | ghost | success | pass | pass | pass | [link](<https://github.com/lost-nd-xxx/perpetual_whisper/releases/tag/1.0.0>) | [link](<https://github.com/lost-nd-xxx/perpetual_whisper/releases/download/1.0.0/perpetual_whisper.nar>) |
| _the_hand_ | ghost | success | pass | partial | pass | [link](<https://github.com/YAYA-shiori/_the_hand_/releases/tag/v20260223112405-124d41a>) | [link](<https://github.com/YAYA-shiori/_the_hand_/releases/download/v20260223112405-124d41a/_the_hand_.nar>) |
| ukagaka-simultaneous-interpreter | ghost | success | pass | partial | pass | [link](<https://github.com/nikolat/ukagaka-simultaneous-interpreter/releases/tag/v1.0.1>) | [link](<https://github.com/nikolat/ukagaka-simultaneous-interpreter/releases/download/v1.0.1/simultaneous-interpreter.nar>) |
| countdown_to_the_end | ghost | success | pass | partial | pass | [link](<https://github.com/lost-nd-xxx/countdown_to_the_end/releases/tag/1.0.0>) | [link](<https://github.com/lost-nd-xxx/countdown_to_the_end/releases/download/1.0.0/countdown_to_the_end.nar>) |
| Youto | ghost | success | pass | pass | pass | [link](<https://github.com/apxxxxxxe/Youto/releases/tag/v1.0.5>) | [link](<https://github.com/apxxxxxxe/Youto/releases/download/v1.0.5/omoideno.nar>) |
| nostalk | ghost | success | pass | pass | pass | [link](<https://github.com/nikolat/nostalk/releases/tag/v0.6.0>) | [link](<https://github.com/nikolat/nostalk/releases/download/v0.6.0/nostalk.nar>) |
| who_is_cursing_him | ghost | success | pass | pass | pass | [link](<https://github.com/tukinami/who_is_cursing_him/releases/tag/v1.0.0>) | [link](<https://github.com/tukinami/who_is_cursing_him/releases/tag/v1.0.0>) |
| Yada-Yada-Yada | ghost | success | pass | pass | pass | [link](<https://github.com/tukinami/Yada-Yada-Yada/releases/tag/v1.0.0>) | [link](<https://github.com/tukinami/Yada-Yada-Yada/releases/tag/v1.0.0>) |
| incubation_of_animas | ghost | success | pass | pass | pass | [link](<https://github.com/tukinami/incubation_of_animas/releases/tag/v1.0.0>) | [link](<https://github.com/tukinami/incubation_of_animas/releases/download/v1.0.0/incubation_of_animas.nar>) |
| yakutai_nashi | ghost | success | pass | partial | pass | [link](<https://github.com/lost-nd-xxx/yakutai_nashi/releases/tag/1.0.1>) | [link](<https://github.com/lost-nd-xxx/yakutai_nashi/releases/download/1.0.1/i_was_useless.nar>) |
| SakanaiUsoWoHitotsuDake | ghost | success | pass | pass | pass | [link](<https://github.com/lost-nd-xxx/SakanaiUsoWoHitotsuDake/releases/tag/1.0.0>) | [link](<https://github.com/lost-nd-xxx/SakanaiUsoWoHitotsuDake/releases/download/1.0.0/SakanaiUsoWoHitotsuDake.nar>) |
| ごーすとじてん | ghost | success | pass | pass | pass | [link](<https://github.com/nikolat/ghostbook/releases/tag/v1.0.0>) | [link](<https://github.com/nikolat/ghostbook/releases/download/v1.0.0/ghostbook.nar>) |
| びーふれんず | ghost | success | pass | pass | pass | [link](<https://github.com/nikolat/bee/releases/tag/v1.0.0>) | [link](<https://github.com/nikolat/bee/releases/download/v1.0.0/bee.nar>) |
| Shennong_kanadome | ghost | success | pass | pass | pass | [link](<https://github.com/Shimofumi/Shennong_kanadome/releases/tag/v1.0.0>) | [link](<https://github.com/Shimofumi/Shennong_kanadome/releases/download/v1.0.0/Shennong_kanadome.nar>) |
| Taromati2 | ghost | success | pass | partial | pass | [link](<https://github.com/Taromati2/package-factory/releases/tag/37566752565>) | [link](<https://github.com/Taromati2/package-factory/releases/download/37566752565/Taromati2.nar>) |
| Oyatsu_ha_Macaroni | ghost | success | pass | pass | pass | [link](<https://github.com/Shimofumi/Oyatsu_ha_Macaroni/releases/tag/v1.0.0>) | [link](<https://github.com/Shimofumi/Oyatsu_ha_Macaroni/releases/download/v1.0.0/Oyatsu_ha_Macaroni.nar>) |
| 箱入り娘 | ghost | success | pass | partial | pass | [link](<https://github.com/nikolat/ukagaka-hakoirimusume/releases/tag/v1.0.0>) | [link](<https://github.com/nikolat/ukagaka-hakoirimusume/releases/download/v1.0.0/hakoirimusume.nar>) |
| しぇるずかん | ghost | success | pass | partial | pass | [link](<https://github.com/nikolat/shellbook/releases/tag/v1.0.3>) | [link](<https://github.com/nikolat/shellbook/releases/download/v1.0.3/shellbook.nar>) |
| れしばいぬ | ghost | success | pass | unsupported | pass | [link](<https://github.com/nikolat/reshibainu/releases/tag/v1.0.0>) | [link](<https://github.com/nikolat/reshibainu/releases/download/v1.0.0/reshibainu.nar>) |
| クローラ＆ロダ | ghost | success | pass | unsupported | pass | [link](<https://github.com/nikolat/crawler_uploader/releases/tag/v1.0.0>) | [link](<https://github.com/nikolat/crawler_uploader/releases/download/v1.0.0/crawler_uploader.nar>) |
| desktop_tempter | ghost | success | pass | error | pass | [link](<https://github.com/Tatakinov/desktop_tempter/releases/tag/1.0.0>) | [link](<https://github.com/Tatakinov/desktop_tempter/releases/download/1.0.0/desktop_tempter.nar>) |
| Party Parrot | ghost | success | pass | partial | pass | [link](<https://github.com/nikolat/ukagaka-party-parrot/releases/tag/v1.6.0>) | [link](<https://github.com/nikolat/ukagaka-party-parrot/releases/download/v1.6.0/party-parrot.nar>) |
| すどはいくゅう | plugin | success | pass | unsupported | pass | [link](<https://github.com/nikolat/sudohaikuyu/releases/tag/v0.4>) | [link](<https://github.com/nikolat/sudohaikuyu/releases/download/v0.4/sudohaikuyu.nar>) |
| desktop_tempter_casino_chip_blue | ghost | success | pass | partial | pass | [link](<https://github.com/Tatakinov/desktop_tempter_casino_chip_blue/releases/tag/1.0.0>) | [link](<https://github.com/Tatakinov/desktop_tempter_casino_chip_blue/releases/download/1.0.0/desktop_tempter_casino_chip_blue.nar>) |
| desktop_tempter_casino_chip_green | ghost | success | pass | partial | pass | [link](<https://github.com/Tatakinov/desktop_tempter_casino_chip_green/releases/tag/1.0.0>) | [link](<https://github.com/Tatakinov/desktop_tempter_casino_chip_green/releases/download/1.0.0/desktop_tempter_casino_chip_green.nar>) |
| desktop_tempter_casino_chip_red | ghost | success | pass | partial | pass | [link](<https://github.com/Tatakinov/desktop_tempter_casino_chip_red/releases/tag/1.0.0>) | [link](<https://github.com/Tatakinov/desktop_tempter_casino_chip_red/releases/download/1.0.0/desktop_tempter_casino_chip_red.nar>) |
| 佳由 period 8 | ghost | success | pass | unsupported | pass | [link](<https://efasus.sakura.ne.jp/ukagaka_works.html>) | [link](<https://efasus.sakura.ne.jp/persona/kayu0008.nar>) |
| 深果 period 9 | ghost | success | pass | unsupported | pass | [link](<https://efasus.sakura.ne.jp/ukagaka_works.html>) | [link](<https://efasus.sakura.ne.jp/persona/mika0209.nar>) |

## 確認事項

- うにゅうのお弁当箱: lifecycle_without_conversation
- 雀-ホワンホワン: lifecycle_without_conversation
- 紺野りりす: lifecycle_without_conversation
- something_like_balloon: static_parse_and_png_decode_ui_unverified
- UkagakaGhostMessenger: windows_plugin_not_executable_on_macos
- ぽにゃづま: lifecycle_without_conversation
- knowledgeable_kernel: helper_failed
- tmidi_msg: windows_plugin_not_executable_on_macos
- ghost_in_a_nutshell: windows_shiori_not_executable
- doll_at_the_bay_window: windows_shiori_not_executable
- stampcollection: windows_plugin_not_executable_on_macos
- Wallet of Unyu: windows_plugin_not_executable_on_macos
- 魔除けの獣面紋: static_parse_and_png_decode_ui_unverified
- banjou_no_sumikko_de: helper_failed
- 雀々BARIBARI: incomplete_lifecycle_or_conversation
- yomibito_minarai: helper_failed
- Bouyomi: windows_plugin_not_executable_on_macos
- うかてん: windows_plugin_not_executable_on_macos
- うかどんゅう: windows_plugin_not_executable_on_macos
- ukagakaPlugin_CeVIO-Talker: windows_plugin_not_executable_on_macos
- SSP-AIVOICE: windows_plugin_not_executable_on_macos
- ukagakaPlugin_getWindowTitle: windows_plugin_not_executable_on_macos
- UkagakaPlugin_DBdiary: windows_plugin_not_executable_on_macos
- 雀卓用透明バルーン: archive_absolute_path
- CharameLNetwork: windows_plugin_not_executable_on_macos
- balloonselector: windows_plugin_not_executable_on_macos
- フタツギノフウセン・青: static_parse_and_png_decode_ui_unverified
- フタツギノフウセン・白: static_parse_and_png_decode_ui_unverified
- フタツギノフウセン・黒: static_parse_and_png_decode_ui_unverified
- フタツギノフウセン・紅: static_parse_and_png_decode_ui_unverified
- フタツギノフウセン・晶: static_parse_and_png_decode_ui_unverified
- Lilies: static_parse_and_png_decode_ui_unverified
- Emily/Phase4.5 専用バルーン: static_parse_and_png_decode_ui_unverified
- 棒読みちゃん連携プラグイン: windows_plugin_not_executable_on_macos
- sakura-restore: windows_shiori_not_executable
- LilyNovelPlayer: lifecycle_without_conversation
- WeatherTimeCapsule: lifecycle_without_conversation
- mancala-player-amber: lifecycle_without_conversation
- mancala-board-ghost: windows_shiori_not_executable
- HopefullyEverAfter_Yume: lifecycle_without_conversation
- flele_aya: host_capability_unavailable
- _the_hand_: host_capability_unavailable
- ukagaka-simultaneous-interpreter: incomplete_lifecycle_or_conversation
- countdown_to_the_end: lifecycle_without_conversation
- yakutai_nashi: lifecycle_without_conversation
- Taromati2: host_capability_unavailable
- 箱入り娘: incomplete_lifecycle_or_conversation
- しぇるずかん: incomplete_lifecycle_or_conversation
- れしばいぬ: windows_shiori_not_executable
- クローラ＆ロダ: windows_shiori_not_executable
- desktop_tempter: helper_failed
- Party Parrot: incomplete_lifecycle_or_conversation
- すどはいくゅう: windows_plugin_not_executable_on_macos
- desktop_tempter_casino_chip_blue: lifecycle_without_conversation
- desktop_tempter_casino_chip_green: lifecycle_without_conversation
- desktop_tempter_casino_chip_red: lifecycle_without_conversation
- 佳由 period 8: windows_shiori_not_executable
- 深果 period 9: windows_shiori_not_executable
