> 本書は en-us 版「SHIORI_EVENTS_FULL_1.0M_PATCHED_en-us.md」の日本語版です。

# SHIORI Events FULL (Ourin/1.0M)

> メソッドの規則（UKADOC 準拠）:
> - イベントが UKADOC のリスト（https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html）で明示的に「[NOTIFY]」と記されていない限り、その既定メソッドは GET です。
> - 「[NOTIFY]」と記載されているイベントのみが既定で NOTIFY です。それ以外はすべて既定で GET です。
> - 本書も同じ慣例に従います。以下の ID について「Method」が示されていない場合は、実装固有の注記で別途指定されない限り、既定で GET と見なしてください。

## Notify 専用イベント（戻り値は無視される）
UKADOC の「Notifyイベント」に従い、以下の ID は NOTIFY で送信され、返されたスクリプトはベースウェア側で無視されなければなりません。Ourin も同じ挙動に従います。

- `basewareversion`
- `hwnd`
- `uniqueid`
- `capability`
- `ownerghostname`
- `otherghostname`
- `installedsakuraname`
- `installedkeroname`
- `installedghostname`
- `installedshellname`
- `installedballoonname`
- `installedheadlinename`
- `installedplugin`
- `configuredbiffname`
- `ghostpathlist`
- `balloonpathlist`
- `headlinepathlist`
- `pluginpathlist`
- `calendarskinpathlist`
- `calendarpluginpathlist`
- `rateofusegraph`
- `enable_log`
- `enable_debug`
- `OnNotifySelfInfo`
- `OnNotifyBalloonInfo`
- `OnNotifyShellInfo`
- `OnNotifyDressupInfo`
- `OnNotifyUserInfo`
- `OnNotifyOSInfo`
- `OnNotifyFontInfo`
- `OnNotifyInternationalInfo`

参照: https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html

| ID | Ourin(mac) メモ |
|---|---|
| `OnFirstBoot` | OS 非依存 |
| `OnBoot` | EventHub でのライフサイクル対応付け |
| `OnClose` | EventHub でのライフサイクル対応付け |
| `OnCloseAll` | OS 非依存 |
| `OnGhostChanged` | EventHub でのライフサイクル対応付け |
| `OnGhostChanging` | EventHub でのライフサイクル対応付け |
| `OnGhostCalled` | OS 非依存 |
| `OnGhostCalling` | OS 非依存 |
| `OnGhostCallComplete` | OS 非依存 |
| `OnOtherGhostBooted` | OS 非依存 |
| `OnOtherGhostChanged` | OS 非依存 |
| `OnOtherGhostClosed` | OS 非依存 |
| `OnShellChanged` | Ourin におけるシェル/バルーンの更新 |
| `OnShellChanging` | Ourin におけるシェル/バルーンの更新 |
| `OnDressupChanged` | 着せ替えフック（SERIKO パーツ） |
| `OnBalloonChange` | Ourin におけるシェル/バルーンの更新 |
| `OnWindowStateRestore` | OS 非依存 |
| `OnWindowStateMinimize` | OS 非依存 |
| `OnFullScreenAppMinimize` | OS 非依存 |
| `OnFullScreenAppRestore` | OS 非依存 |
| `OnVirtualDesktopChanged` | OS 非依存 |
| `OnCacheSuspend` | OS 非依存 |
| `OnCacheRestore` | OS 非依存 |
| `OnInitialize` | OS 非依存 |
| `OnDestroy` | OS 非依存 |
| `OnSysResume` | OS 非依存 |
| `OnSysSuspend` | OS 非依存 |
| `OnBasewareUpdating` | OS 非依存 |
| `OnBasewareUpdated` | OS 非依存 |
| `OnTeachStart` | OS 非依存 |
| `OnTeachInputCancel` | OS 非依存 |
| `OnTeach` | OS 非依存 |
| `OnCommunicate` | OS 非依存 |
| `OnCommunicateInputCancel` | OS 非依存 |
| `OnUserInput` | OS 非依存 |
| `OnUserInputCancel` | OS 非依存 |
| `OnSystemDialog` | OS 非依存 |
| `OnSystemDialogCancel` | OS 非依存 |
| `OnConfigurationDialogHelp` | OS 非依存 |
| `OnGhostTermsAccept` | OS 非依存 |
| `OnGhostTermsDecline` | OS 非依存 |
| `OnSecondChange` | OS 非依存 |
| `OnMinuteChange` | OS 非依存 |
| `OnHourTimeSignal` | OS 非依存 |
| `OnVanishSelecting` | OS 非依存 |
| `OnVanishSelected` | OS 非依存 |
| `OnVanishCancel` | OS 非依存 |
| `OnVanishButtonHold` | OS 非依存 |
| `OnVanished` | OS 非依存 |
| `OnOtherGhostVanished` | OS 非依存 |
| `OnChoiceSelect` | OS 非依存 |
| `OnChoiceSelectEx` | OS 非依存 |
| `OnChoiceEnter` | OS 非依存 |
| `OnChoiceTimeout` | OS 非依存 |
| `OnChoiceHover` | OS 非依存 |
| `OnAnchorSelect` | OS 非依存 |
| `OnAnchorSelectEx` | OS 非依存 |
| `OnAnchorEnter` | OS 非依存 |
| `OnAnchorHover` | OS 非依存 |
| `OnSurfaceChange` | OS 非依存 |
| `OnSurfaceRestore` | OS 非依存 |
| `OnOtherSurfaceChange` | OS 非依存 |
| `OnMouseClick` | OS 非依存 |
| `OnMouseClickEx` | OS 非依存 |
| `OnMouseDoubleClick` | NSEvent から対応付け（画面→論理座標） |
| `OnMouseDoubleClickEx` | OS 非依存 |
| `OnMouseMultipleClick` | OS 非依存 |
| `OnMouseMultipleClickEx` | OS 非依存 |
| `OnMouseUp` | NSEvent から対応付け（画面→論理座標） |
| `OnMouseUpEx` | OS 非依存 |
| `OnMouseDown` | NSEvent から対応付け（画面→論理座標） |
| `OnMouseDownEx` | OS 非依存 |
| `OnMouseMove` | NSEvent から対応付け（画面→論理座標） |
| `OnMouseWheel` | OS 非依存 |
| `OnMouseEnterAll` | OS 非依存 |
| `OnMouseLeaveAll` | OS 非依存 |
| `OnMouseEnter` | OS 非依存 |
| `OnMouseLeave` | OS 非依存 |
| `OnMouseDragStart` | OS 非依存 |
| `OnMouseDragEnd` | OS 非依存 |
| `OnMouseHover` | OS 非依存 |
| `OnMouseGesture` | OS 非依存 |
| `OnBalloonBreak` | OS 非依存 |
| `OnBalloonClose` | OS 非依存 |
| `OnBalloonTimeout` | OS 非依存 |
| `OnTrayBalloonClick` | OS 非依存 |
| `OnTrayBalloonTimeout` | OS 非依存 |
| `OnInstallBegin` | OS 非依存 |
| `OnInstallComplete` | OS 非依存 |
| `OnInstallCompleteEx` | OS 非依存 |
| `OnInstallCompleteAll` | OS 非依存 |
| `OnInstallFailure` | OS 非依存 |
| `OnInstallRefuse` | OS 非依存 |
| `OnInstallReroute` | OS 非依存 |
| `OnFileDropping` | OS 非依存 |
| `OnFileDropped` | OS 非依存 |
| `OnOtherObjectDropping` | OS 非依存 |
| `OnOtherObjectDropped` | OS 非依存 |
| `OnDirectoryDrop` | OS 非依存 |
| `OnWallpaperChange` | OS 非依存 |
| `OnFileDrop` | OS 非依存 |
| `OnFileDropEx` | OS 非依存 |
| `OnFileDrop2` | OS 非依存 |
| `OnUpdatedataCreating` | OS 非依存 |
| `OnUpdatedataCreated` | OS 非依存 |
| `OnNarCreating` | OS 非依存 |
| `OnNarCreated` | OS 非依存 |
| `OnURLDragDropping` | OS 非依存 |
| `OnURLDropping` | OS 非依存 |
| `OnURLDropped` | OS 非依存 |
| `OnURLDropFailure` | OS 非依存 |
| `OnURLQuery` | OS 非依存 |
| `OnXUkagakaLinkOpen` | OS 非依存 |
| `OnUpdateProcessExec` | OS 非依存 |
| `OnUpdateBegin` | OS 非依存 |
| `OnUpdateReady` | OS 非依存 |
| `OnUpdateComplete` | OS 非依存 |
| `OnUpdateFailure` | OS 非依存 |
| `OnUpdate` | OS 非依存 |
| `OnDownloadBegin` | OS 非依存 |
| `OnMD5CompareBegin` | OS 非依存 |
| `OnMD5CompareComplete` | OS 非依存 |
| `OnMD5CompareFailure` | OS 非依存 |
| `OnUpdateOtherBegin` | OS 非依存 |
| `OnUpdateOtherReady` | OS 非依存 |
| `OnUpdateOtherComplete` | OS 非依存 |
| `OnUpdateOtherFailure` | OS 非依存 |
| `OnUpdateOther` | OS 非依存 |
| `OnUpdateCheckComplete` | OS 非依存 |
| `OnUpdateCheckFailure` | OS 非依存 |
| `OnUpdateResult` | OS 非依存 |
| `OnUpdateResultEx` | OS 非依存 |
| `OnUpdateCheckResult` | OS 非依存 |
| `OnUpdateCheckResultEx` | OS 非依存 |
| `OnUpdateResultExplorer` | OS 非依存 |
| `OnSNTPBegin` | OS 非依存 |
| `OnSNTPCompareEx` | OS 非依存 |
| `OnSNTPCompare` | OS 非依存 |
| `OnSNTPCorrectEx` | OS 非依存 |
| `OnSNTPCorrect` | OS 非依存 |
| `OnSNTPFailure` | OS 非依存 |
| `OnBIFFBegin` | OS 非依存 |
| `OnBIFFComplete` | OS 非依存 |
| `OnBIFF2Complete` | OS 非依存 |
| `OnBIFFFailure` | OS 非依存 |
| `OnHeadlinesenseBegin` | OS 非依存 |
| `OnHeadlinesense` | OS 非依存 |
| `OnFind` | OS 非依存 |
| `OnHeadlinesenseComplete` | OS 非依存 |
| `OnHeadlinesenseFailure` | OS 非依存 |
| `OnRSSBegin` | OS 非依存 |
| `OnRSSComplete` | OS 非依存 |
| `OnRSSFailure` | OS 非依存 |
| `OnSchedule5MinutesToGo` | OS 非依存 |
| `OnScheduleRead` | OS 非依存 |
| `OnSchedulesenseBegin` | OS 非依存 |
| `OnSchedulesenseComplete` | OS 非依存 |
| `OnSchedulesenseFailure` | OS 非依存 |
| `OnSchedulepostBegin` | OS 非依存 |
| `OnSchedulepostComplete` | OS 非依存 |
| `OnSSTPBreak` | SSTP は既定で localhost のみ |
| `OnSSTPBlacklisting` | SSTP は既定で localhost のみ |
| `OnExecuteHTTPComplete` | OS 非依存 |
| `OnExecuteHTTPFailure` | OS 非依存 |
| `OnExecuteHTTPProgress` | OS 非依存 |
| `OnExecuteHTTPSSLInfo` | OS 非依存 |
| `OnExecuteRSSComplete` | OS 非依存 |
| `OnExecuteRSSFailure` | OS 非依存 |
| `OnExecuteRSS_SSLInfo` | OS 非依存 |
| `OnPingComplete` | OS 非依存 |
| `OnPingProgress` | OS 非依存 |
| `OnNSLookupComplete` | OS 非依存 |
| `OnNSLookupFailure` | OS 非依存 |
| `OnRaisePluginFailure` | OS 非依存 |
| `OnNotifyPluginFailure` | OS 非依存 |
| `OnRaiseOtherFailure` | OS 非依存 |
| `OnNotifyOtherFailure` | OS 非依存 |
| `OnOverlap` | OS 非依存 |
| `OnOtherOverlap` | OS 非依存 |
| `OnOffscreen` | OS 非依存 |
| `OnOtherOffscreen` | OS 非依存 |
| `OnNetworkHeavy` | OS 非依存 |
| `OnNetworkStatusChange` | OS 非依存 |
| `OnScreenSaverStart` | OS 非依存 |
| `OnScreenSaverEnd` | OS 非依存 |
| `OnSessionLock` | OS 非依存 |
| `OnSessionUnlock` | OS 非依存 |
| `OnSessionDisconnect` | OS 非依存 |
| `OnSessionReconnect` | OS 非依存 |
| `OnCPULoadHigh` | OS 非依存 |
| `OnCPULoadLow` | OS 非依存 |
| `OnMemoryLoadHigh` | OS 非依存 |
| `OnMemoryLoadLow` | OS 非依存 |
| `OnDisplayChange` | OS 非依存 |
| `OnDisplayHandover` | OS 非依存 |
| `OnDisplayChangeEx` | OS 非依存 |
| `OnDisplayPowerStatus` | OS 非依存 |
| `OnBatteryNotify` | OS 非依存 |
| `OnBatteryLow` | OS 非依存 |
| `OnBatteryCritical` | OS 非依存 |
| `OnBatteryChargingStart` | OS 非依存 |
| `OnBatteryChargingStop` | OS 非依存 |
| `OnDeviceArrival` | OS 非依存 |
| `OnDeviceRemove` | OS 非依存 |
| `OnTabletMode` | OS 非依存 |
| `OnDarkTheme` | OS 非依存 |
| `OnOSUpdateInfo` | OS 非依存 |
| `OnRecycleBinEmpty` | OS 非依存 |
| `OnRecycleBinEmptyFromOther` | OS 非依存 |
| `OnRecycleBinStatusUpdate` | OS 非依存 |
| `OnSelectModeBegin` | OS 非依存 |
| `OnSelectModeCancel` | OS 非依存 |
| `OnSelectModeComplete` | OS 非依存 |
| `OnSelectModeMouseDown` | OS 非依存 |
| `OnSelectModeMouseUp` | OS 非依存 |
| `OnSpeechSynthesisStatus` | OS 非依存 |
| `OnVoiceRecognitionStatus` | OS 非依存 |
| `OnVoiceRecognitionWord` | OS 非依存 |
| `OnKeyPress` | キーイベントから対応付け（IME 対応） |
| `OnRecommendsiteChoice` | OS 非依存 |
| `OnTranslate` | OS 非依存 |
| `OnAITalk` | OS 非依存 |
| `OnOtherGhostTalk` | OS 非依存 |
| `OnEmbryoExist` | OS 非依存 |
| `OnNekodorifExist` | OS 非依存 |
| `OnSoundStop` | OS 非依存 |
| `OnSoundError` | OS 非依存 |
| `OnTextDrop` | OS 非依存 |
| `OnShellScaling` | OS 非依存 |
| `OnBalloonScaling` | OS 非依存 |
| `OnLanguageChange` | OS 非依存 |
| `OnResetWindowPos` | OS 非依存 |
| `OnNotifySelfInfo` | OS 非依存 |
| `OnNotifyBalloonInfo` | OS 非依存 |
| `OnNotifyShellInfo` | OS 非依存 |
| `OnNotifyDressupInfo` | 着せ替えフック（SERIKO パーツ） |
| `OnNotifyUserInfo` | OS 非依存 |
| `OnNotifyOSInfo` | OS 非依存 |
| `OnNotifyFontInfo` | OS 非依存 |
| `OnNotifyInternationalInfo` | OS 非依存 |
| `OnRequestValues` | OS 非依存 |
| `OnGetValues` | OS 非依存 |
| `OnTalkRequest` | OS 非依存 |
| `OnHandActivate` | OS 非依存 |
| `OnJitenBattle` | OS 非依存 |
| `OnJitenTagBattle` | OS 非依存 |
| `OnMglBattle` | OS 非依存 |
| `OnKanadeTeaPartyInfomationRequest` | OS 非依存 |
| `OnKanadeTeaParty` | OS 非依存 |
| `OnKanadeTeaPartyEnd` | OS 非依存 |
| `OnPoker` | OS 非依存 |
| `OnPokerNotify` | OS 非依存 |
| `OnMopClear` | OS 非依存 |
| `OnNeedlePoke` | OS 非依存 |
| `OnBeerShower` | OS 非依存 |
| `OnDive` | OS 非依存 |
| `OnHitThunder` | OS 非依存 |
| `OnStampInfo` | OS 非依存 |
| `OnStampAdd` | OS 非依存 |
| `OnStampInfoCall` | OS 非依存 |
| `OnPotatoReturn` | OS 非依存 |
| `OnPotatoFileNotFound` | OS 非依存 |
| `OnPotatoError` | OS 非依存 |
| `OnCrystalDiskInfoEvent` | OS 非依存 |
| `OnCrystalDiskInfoClear` | OS 非依存 |
| `OnWeatherStation` | OS 非依存 |
| `OnSpectrePlugin` | OS 非依存 |
| `OnHttpcNotify` | OS 非依存 |
| `OnKinokoObjectCreate` | OS 非依存 |
| `OnKinokoObjectDestroy` | OS 非依存 |
| `OnKinokoObjectChanging` | OS 非依存 |
| `OnKinokoObjectChanged` | OS 非依存 |
| `OnKinokoObjectInstalled` | OS 非依存 |
| `OnSysResourceLow` | OS 非依存 |
| `OnSysResourceCritical` | OS 非依存 |
| `OnNekodorifObjectEmerge` | OS 非依存 |
| `OnNekodorifObjectHit` | OS 非依存 |
| `OnNekodorifObjectDrop` | OS 非依存 |
| `OnNekodorifObjectVanish` | OS 非依存 |
| `OnNekodorifObjectDodge` | OS 非依存 |
| `OnMusicPlay` | OS 非依存 |
| `OnFleetClockComplete` | OS 非依存 |
| `OnElonaOmakeMMAEventNewGame` | OS 非依存 |
| `OnElonaOmakeMMAEventGameLoad` | OS 非依存 |
| `OnElonaOmakeMMAEventGameQuit` | OS 非依存 |
| `OnElonaOmakeMMAEventHourPlayed` | OS 非依存 |
| `OnElonaOmakeMMAEventMapChanged` | OS 非依存 |
| `OnElonaOmakeMMAEventLevelUp` | OS 非依存 |
| `OnElonaOmakeMMAEventSkillUp` | OS 非依存 |
| `OnElonaOmakeMMAEventSkillDown` | OS 非依存 |
| `OnElonaOmakeMMAEventBelieveGod` | OS 非依存 |
| `OnElonaOmakeMMAEventJoinParty` | OS 非依存 |
| `OnElonaOmakeMMAEventSleep` | OS 非依存 |
| `OnElonaOmakeMMAEventAwake` | OS 非依存 |
| `OnElonaOmakeMMAEventInvestNPC` | OS 非依存 |
| `OnElonaOmakeMMAEventRandomEvent` | OS 非依存 |
| `OnElonaOmakeMMAEventAddNewsTopic` | OS 非依存 |
| `OnElonaOmakeMMAEventWish` | OS 非依存 |
| `OnElonaOmakeMMAEventWished` | OS 非依存 |
| `OnElonaOmakeMMAEventDead` | OS 非依存 |
| `OnElonaOmakeMMAEventPetDead` | OS 非依存 |
| `OnElonaOmakeMMAEventLastword` | OS 非依存 |
| `OnElonaOmakeMMAEventTravelGuide` | OS 非依存 |
| `OnElonaOmakeMMAEventAbandonPet` | OS 非依存 |
| `OnElonaOmakeMMAEventSaleSlave` | OS 非依存 |
| `OnElonaOmakeMMAEventSaleWife` | OS 非依存 |
| `OnElonaOmakeMMAEventMarriage` | OS 非依存 |
| `OnElonaOmakeMMAEventRefuseMarriage` | OS 非依存 |
| `OnElonaOmakeMMAEventJoinGuild` | OS 非依存 |
| `OnElonaOmakeMMAEventMutation` | OS 非依存 |
| `OnElonaOmakeMMAEventMutationCured` | OS 非依存 |
| `OnElonaOmakeMMAEventEtherDisease` | OS 非依存 |
| `OnElonaOmakeMMAEventEtherDiseaseCured` | OS 非依存 |
| `OnElonaOmakeMMAEventAdventGod` | OS 非依存 |
| `OnElonaOmakeMMAEventMewmewmew` | OS 非依存 |
| `OnElonaOmakeMMAEventBuyNuke` | OS 非依存 |
| `OnElonaOmakeMMAEventSetNuke` | OS 非依存 |
| `OnElonaOmakeMMAEventNukeExploded` | OS 非依存 |
| `OnElonaOmakeMMAEventLomiasInTheParty` | OS 非依存 |
| `OnElonaOmakeMMAEventLomiasKilled` | OS 非依存 |
| `OnElonaOmakeMMAEventZeomeKilled` | OS 非依存 |
| `OnElonaOmakeMMAEventConqueredLesimas` | OS 非依存 |
| `OnElonaOmakeMMAEventAtonement` | OS 非依存 |
| `OnElonaOmakeMMAEventBecomeCriminal` | OS 非依存 |
| `OnElonaOmakeMMAEventPerformance` | OS 非依存 |
| `OnElonaOmakeMMAEventClothOut` | OS 非依存 |
| `OnElonaOmakeMMAEventStealItem` | OS 非依存 |
| `OnElonaOmakeMMAEventTreasureDigging` | OS 非依存 |
| `OnElonaOmakeMMAEventReadTreasureMap` | OS 非依存 |
| `OnElonaOmakeMMAEventSkillLearned` | OS 非依存 |
| `OnElonaOmakeMMAEventWeatherChanged` | OS 非依存 |
| `OnElonaOmakeMMAEventRagnarok` | OS 非依存 |
| `OnElonaOmakeMMAEventSisterRagnarok` | OS 非依存 |
| `OnElonaOmakeMMAEventPray` | OS 非依存 |
| `OnElonaOmakeMMAEventOffer` | OS 非依存 |
| `OnElonaOmakeMMAEventPrayFailed` | OS 非依存 |
| `OnElonaOmakeMMAEventPrayEyth` | OS 非依存 |
| `OnElonaOmakeMMAEventAreaChanged` | OS 非依存 |
| `OnElonaOmakeMMAEventPayTax` | OS 非依存 |
| `OnElonaOmakeMMAEventCooking` | OS 非依存 |
| `OnElonaOmakeMMAEventHour` | OS 非依存 |
| `OnElonaOmakeMMAEventGrandmapocalypse` | OS 非依存 |
| `OnMahjong` | OS 非依存 |
| `OnMahjongResponse` | OS 非依存 |
| `OnNostr` | OS 非依存 |
| `OnSatolistBoot` | OS 非依存 |
| `OnSatolistGhostOpened` | OS 非依存 |
| `OnSatolistSaved` | OS 非依存 |
| `OnSatolistClosed` | OS 非依存 |
| `OnSatolistEventAdded` | OS 非依存 |
| `OnSatolistDictionaryFolderChanged` | OS 非依存 |
| `OnTourabuConquestStart` | OS 非依存 |
| `OnTourabuConquestEnd` | OS 非依存 |
| `OnTourabuDutyStart` | OS 非依存 |
| `OnTourabuDutyEnd` | OS 非依存 |
| `OnElinAllyCondition` | OS 非依存 |
| `OnElinAllyDead` | OS 非依存 |
| `OnElinCatchFish` | OS 非依存 |
| `OnElinMapCharaGenerate` | OS 非依存 |
| `OnElinMapEnter` | OS 非依存 |
| `OnElinMapItemGenerate` | OS 非依存 |
| `OnElinPCCondition` | OS 非依存 |
| `OnElinPCDead` | OS 非依存 |
| `OnElinTarget` | OS 非依存 |
| `OnApplicationBoot` | OS 非依存 |
| `OnApplicationClose` | OS 非依存 |
| `OnApplicationExist` | OS 非依存 |
| `OnApplicationVersion` | OS 非依存 |
| `OnApplicationOperationFinish` | OS 非依存 |
| `OnApplicationFileOpen` | OS 非依存 |
| `OnWebsiteUpdateNotify` | OS 非依存 |
| `OnUkadocScriptExample` | OS 非依存 |


---

# Appendix: Ourin(mac) 差分注記（イベント, 2025-07-29 21:06 UTC+09:00）

Ourin における **OS 依存イベント**のマッピング／制約を明文化します。本文の ID/意味は Ukadoc に準拠し、ここでは **発火源と公開API**を明記します。

## 電源/スリープ/画面
| イベント例 | Ourin(mac) 発火源/メモ |
|---|---|
| `OnSysSuspend` / `OnSysResume` | **NSWorkspace.willSleepNotification / didWakeNotification** をブリッジ。 |
| `OnScreenSaverStart` / `OnScreenSaverEnd` | 画面スリープ/復帰は **screensDidSleepNotification / screensDidWakeNotification** を準用。 |
| `OnDisplay*` | 画面構成変化は NSWorkspace 通知や CGDisplay 変更の観測で補完（必要最小限）。 |

## バッテリー/電源
| イベント例 | Ourin(mac) 発火源/メモ |
|---|---|
| `OnBattery*`（残量/充電/AC接続など） | **IOKit IOPowerSources**（`IOPSCopyPowerSourcesInfo` 系）をポーリング/通知で監視。 |

## 通知/トレイ相当
| イベント例 | Ourin(mac) 発火源/メモ |
|---|---|
| `OnTrayBalloon*` 系 | **NSStatusItem** 常駐＋ **UNUserNotificationCenter** で代替。タイムアウト等は **OS 依存**。 |

## ファイル/ゴミ箱（Recycle Bin 相当）
| イベント例 | Ourin(mac) 発火源/メモ |
|---|---|
| `OnRecycleBin*` | `~/.Trash` 配下を **FSEvents** で監視（Best‑Effort）。APFS/権限により検出粒度は変動。 |

## 外観/テーマ
| イベント例 | Ourin(mac) 発火源/メモ |
|---|---|
| `OnDarkTheme`（相当の独自拡張を含む） | **NSApplication.effectiveAppearance** を監視（KVO 等）。 |

## 非推奨/縮退候補（mac に概念差あり）
| イベント例 | Ourin(mac) 方針 |
|---|---|
| `OnTabletMode` | macOS にタブレットモード概念なし。**非対応**（常に未発火）。 |
| `OnVirtualDesktopChanged` 等 | **Spaces** は**安定した公開 API が乏しい**ため、既定は未対応。必要なら実験的に通知のみに留める。 |

#### 参考（出典）
- Ukadoc: **SHIORI Event リスト（本体／外部）**。  
- Apple: **NSWorkspace** の各通知（sleep/wake/screens）、**IOKit IOPowerSources**（バッテリー/AC 判定）、**File System Events (FSEvents)**、**UNUserNotificationCenter**、**NSStatusItem**、**effectiveAppearance**。
