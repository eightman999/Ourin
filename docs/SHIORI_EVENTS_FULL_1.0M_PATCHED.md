# SHIORI Events FULL (Ourin/1.0M)

> Method rule (per UKADOC):
> - Unless an event is explicitly marked as "[NOTIFY]" in the UKADOC list (https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html), its default method is GET.
> - Only events documented with "[NOTIFY]" are NOTIFY by default. All others are GET by default.
> - This document follows the same convention. When the "Method" is not shown for an ID below, assume GET by default unless otherwise noted by implementation-specific remarks.

## Notify-only events (return ignored)
Per UKADOC “Notifyイベント”, the following IDs are sent via NOTIFY and any returned script must be ignored by the baseware. Ourin follows the same behavior.

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

Reference: https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html

| ID | Ourin(mac) メモ |
|---|---|
| `OnFirstBoot` | OS-agnostic |
| `OnBoot` | Lifecycle mapping in EventHub |
| `OnClose` | Lifecycle mapping in EventHub |
| `OnCloseAll` | OS-agnostic |
| `OnGhostChanged` | Lifecycle mapping in EventHub |
| `OnGhostChanging` | Lifecycle mapping in EventHub |
| `OnGhostCalled` | OS-agnostic |
| `OnGhostCalling` | OS-agnostic |
| `OnGhostCallComplete` | OS-agnostic |
| `OnOtherGhostBooted` | OS-agnostic |
| `OnOtherGhostChanged` | OS-agnostic |
| `OnOtherGhostClosed` | OS-agnostic |
| `OnShellChanged` | Shell/Balloon updates in Ourin |
| `OnShellChanging` | Shell/Balloon updates in Ourin |
| `OnDressupChanged` | Dressup hooks (SERIKO parts) |
| `OnBalloonChange` | Shell/Balloon updates in Ourin |
| `OnWindowStateRestore` | OS-agnostic |
| `OnWindowStateMinimize` | OS-agnostic |
| `OnFullScreenAppMinimize` | OS-agnostic |
| `OnFullScreenAppRestore` | OS-agnostic |
| `OnVirtualDesktopChanged` | OS-agnostic |
| `OnCacheSuspend` | OS-agnostic |
| `OnCacheRestore` | OS-agnostic |
| `OnInitialize` | OS-agnostic |
| `OnDestroy` | OS-agnostic |
| `OnSysResume` | OS-agnostic |
| `OnSysSuspend` | OS-agnostic |
| `OnBasewareUpdating` | OS-agnostic |
| `OnBasewareUpdated` | OS-agnostic |
| `OnTeachStart` | OS-agnostic |
| `OnTeachInputCancel` | OS-agnostic |
| `OnTeach` | OS-agnostic |
| `OnCommunicate` | OS-agnostic |
| `OnCommunicateInputCancel` | OS-agnostic |
| `OnUserInput` | OS-agnostic |
| `OnUserInputCancel` | OS-agnostic |
| `OnSystemDialog` | OS-agnostic |
| `OnSystemDialogCancel` | OS-agnostic |
| `OnConfigurationDialogHelp` | OS-agnostic |
| `OnGhostTermsAccept` | OS-agnostic |
| `OnGhostTermsDecline` | OS-agnostic |
| `OnSecondChange` | OS-agnostic |
| `OnMinuteChange` | OS-agnostic |
| `OnHourTimeSignal` | OS-agnostic |
| `OnVanishSelecting` | OS-agnostic |
| `OnVanishSelected` | OS-agnostic |
| `OnVanishCancel` | OS-agnostic |
| `OnVanishButtonHold` | OS-agnostic |
| `OnVanished` | OS-agnostic |
| `OnOtherGhostVanished` | OS-agnostic |
| `OnChoiceSelect` | OS-agnostic |
| `OnChoiceSelectEx` | OS-agnostic |
| `OnChoiceEnter` | OS-agnostic |
| `OnChoiceTimeout` | OS-agnostic |
| `OnChoiceHover` | OS-agnostic |
| `OnAnchorSelect` | OS-agnostic |
| `OnAnchorSelectEx` | OS-agnostic |
| `OnAnchorEnter` | OS-agnostic |
| `OnAnchorHover` | OS-agnostic |
| `OnSurfaceChange` | OS-agnostic |
| `OnSurfaceRestore` | OS-agnostic |
| `OnOtherSurfaceChange` | OS-agnostic |
| `OnMouseClick` | OS-agnostic |
| `OnMouseClickEx` | OS-agnostic |
| `OnMouseDoubleClick` | Map from NSEvent (screen→logical coords) |
| `OnMouseDoubleClickEx` | OS-agnostic |
| `OnMouseMultipleClick` | OS-agnostic |
| `OnMouseMultipleClickEx` | OS-agnostic |
| `OnMouseUp` | Map from NSEvent (screen→logical coords) |
| `OnMouseUpEx` | OS-agnostic |
| `OnMouseDown` | Map from NSEvent (screen→logical coords) |
| `OnMouseDownEx` | OS-agnostic |
| `OnMouseMove` | Map from NSEvent (screen→logical coords) |
| `OnMouseWheel` | OS-agnostic |
| `OnMouseEnterAll` | OS-agnostic |
| `OnMouseLeaveAll` | OS-agnostic |
| `OnMouseEnter` | OS-agnostic |
| `OnMouseLeave` | OS-agnostic |
| `OnMouseDragStart` | OS-agnostic |
| `OnMouseDragEnd` | OS-agnostic |
| `OnMouseHover` | OS-agnostic |
| `OnMouseGesture` | OS-agnostic |
| `OnBalloonBreak` | OS-agnostic |
| `OnBalloonClose` | OS-agnostic |
| `OnBalloonTimeout` | OS-agnostic |
| `OnTrayBalloonClick` | OS-agnostic |
| `OnTrayBalloonTimeout` | OS-agnostic |
| `OnInstallBegin` | OS-agnostic |
| `OnInstallComplete` | OS-agnostic |
| `OnInstallCompleteEx` | OS-agnostic |
| `OnInstallCompleteAll` | OS-agnostic |
| `OnInstallFailure` | OS-agnostic |
| `OnInstallRefuse` | OS-agnostic |
| `OnInstallReroute` | OS-agnostic |
| `OnFileDropping` | OS-agnostic |
| `OnFileDropped` | OS-agnostic |
| `OnOtherObjectDropping` | OS-agnostic |
| `OnOtherObjectDropped` | OS-agnostic |
| `OnDirectoryDrop` | OS-agnostic |
| `OnWallpaperChange` | OS-agnostic |
| `OnFileDrop` | OS-agnostic |
| `OnFileDropEx` | OS-agnostic |
| `OnFileDrop2` | OS-agnostic |
| `OnUpdatedataCreating` | OS-agnostic |
| `OnUpdatedataCreated` | OS-agnostic |
| `OnNarCreating` | OS-agnostic |
| `OnNarCreated` | OS-agnostic |
| `OnURLDragDropping` | OS-agnostic |
| `OnURLDropping` | OS-agnostic |
| `OnURLDropped` | OS-agnostic |
| `OnURLDropFailure` | OS-agnostic |
| `OnURLQuery` | OS-agnostic |
| `OnXUkagakaLinkOpen` | OS-agnostic |
| `OnUpdateProcessExec` | OS-agnostic |
| `OnUpdateBegin` | OS-agnostic |
| `OnUpdateReady` | OS-agnostic |
| `OnUpdateComplete` | OS-agnostic |
| `OnUpdateFailure` | OS-agnostic |
| `OnUpdate` | OS-agnostic |
| `OnDownloadBegin` | OS-agnostic |
| `OnMD5CompareBegin` | OS-agnostic |
| `OnMD5CompareComplete` | OS-agnostic |
| `OnMD5CompareFailure` | OS-agnostic |
| `OnUpdateOtherBegin` | OS-agnostic |
| `OnUpdateOtherReady` | OS-agnostic |
| `OnUpdateOtherComplete` | OS-agnostic |
| `OnUpdateOtherFailure` | OS-agnostic |
| `OnUpdateOther` | OS-agnostic |
| `OnUpdateCheckComplete` | OS-agnostic |
| `OnUpdateCheckFailure` | OS-agnostic |
| `OnUpdateResult` | OS-agnostic |
| `OnUpdateResultEx` | OS-agnostic |
| `OnUpdateCheckResult` | OS-agnostic |
| `OnUpdateCheckResultEx` | OS-agnostic |
| `OnUpdateResultExplorer` | OS-agnostic |
| `OnSNTPBegin` | OS-agnostic |
| `OnSNTPCompareEx` | OS-agnostic |
| `OnSNTPCompare` | OS-agnostic |
| `OnSNTPCorrectEx` | OS-agnostic |
| `OnSNTPCorrect` | OS-agnostic |
| `OnSNTPFailure` | OS-agnostic |
| `OnBIFFBegin` | OS-agnostic |
| `OnBIFFComplete` | OS-agnostic |
| `OnBIFF2Complete` | OS-agnostic |
| `OnBIFFFailure` | OS-agnostic |
| `OnHeadlinesenseBegin` | OS-agnostic |
| `OnHeadlinesense` | OS-agnostic |
| `OnFind` | OS-agnostic |
| `OnHeadlinesenseComplete` | OS-agnostic |
| `OnHeadlinesenseFailure` | OS-agnostic |
| `OnRSSBegin` | OS-agnostic |
| `OnRSSComplete` | OS-agnostic |
| `OnRSSFailure` | OS-agnostic |
| `OnSchedule5MinutesToGo` | OS-agnostic |
| `OnScheduleRead` | OS-agnostic |
| `OnSchedulesenseBegin` | OS-agnostic |
| `OnSchedulesenseComplete` | OS-agnostic |
| `OnSchedulesenseFailure` | OS-agnostic |
| `OnSchedulepostBegin` | OS-agnostic |
| `OnSchedulepostComplete` | OS-agnostic |
| `OnSSTPBreak` | SSTP localhost-only by default |
| `OnSSTPBlacklisting` | SSTP localhost-only by default |
| `OnExecuteHTTPComplete` | OS-agnostic |
| `OnExecuteHTTPFailure` | OS-agnostic |
| `OnExecuteHTTPProgress` | OS-agnostic |
| `OnExecuteHTTPSSLInfo` | OS-agnostic |
| `OnExecuteRSSComplete` | OS-agnostic |
| `OnExecuteRSSFailure` | OS-agnostic |
| `OnExecuteRSS_SSLInfo` | OS-agnostic |
| `OnPingComplete` | OS-agnostic |
| `OnPingProgress` | OS-agnostic |
| `OnNSLookupComplete` | OS-agnostic |
| `OnNSLookupFailure` | OS-agnostic |
| `OnRaisePluginFailure` | OS-agnostic |
| `OnNotifyPluginFailure` | OS-agnostic |
| `OnRaiseOtherFailure` | OS-agnostic |
| `OnNotifyOtherFailure` | OS-agnostic |
| `OnOverlap` | OS-agnostic |
| `OnOtherOverlap` | OS-agnostic |
| `OnOffscreen` | OS-agnostic |
| `OnOtherOffscreen` | OS-agnostic |
| `OnNetworkHeavy` | OS-agnostic |
| `OnNetworkStatusChange` | OS-agnostic |
| `OnScreenSaverStart` | OS-agnostic |
| `OnScreenSaverEnd` | OS-agnostic |
| `OnSessionLock` | OS-agnostic |
| `OnSessionUnlock` | OS-agnostic |
| `OnSessionDisconnect` | OS-agnostic |
| `OnSessionReconnect` | OS-agnostic |
| `OnCPULoadHigh` | OS-agnostic |
| `OnCPULoadLow` | OS-agnostic |
| `OnMemoryLoadHigh` | OS-agnostic |
| `OnMemoryLoadLow` | OS-agnostic |
| `OnDisplayChange` | OS-agnostic |
| `OnDisplayHandover` | OS-agnostic |
| `OnDisplayChangeEx` | OS-agnostic |
| `OnDisplayPowerStatus` | OS-agnostic |
| `OnBatteryNotify` | OS-agnostic |
| `OnBatteryLow` | OS-agnostic |
| `OnBatteryCritical` | OS-agnostic |
| `OnBatteryChargingStart` | OS-agnostic |
| `OnBatteryChargingStop` | OS-agnostic |
| `OnDeviceArrival` | OS-agnostic |
| `OnDeviceRemove` | OS-agnostic |
| `OnTabletMode` | OS-agnostic |
| `OnDarkTheme` | OS-agnostic |
| `OnOSUpdateInfo` | OS-agnostic |
| `OnRecycleBinEmpty` | OS-agnostic |
| `OnRecycleBinEmptyFromOther` | OS-agnostic |
| `OnRecycleBinStatusUpdate` | OS-agnostic |
| `OnSelectModeBegin` | OS-agnostic |
| `OnSelectModeCancel` | OS-agnostic |
| `OnSelectModeComplete` | OS-agnostic |
| `OnSelectModeMouseDown` | OS-agnostic |
| `OnSelectModeMouseUp` | OS-agnostic |
| `OnSpeechSynthesisStatus` | OS-agnostic |
| `OnVoiceRecognitionStatus` | OS-agnostic |
| `OnVoiceRecognitionWord` | OS-agnostic |
| `OnKeyPress` | Map from key events (IME aware) |
| `OnRecommendsiteChoice` | OS-agnostic |
| `OnTranslate` | OS-agnostic |
| `OnAITalk` | OS-agnostic |
| `OnOtherGhostTalk` | OS-agnostic |
| `OnEmbryoExist` | OS-agnostic |
| `OnNekodorifExist` | OS-agnostic |
| `OnSoundStop` | OS-agnostic |
| `OnSoundError` | OS-agnostic |
| `OnTextDrop` | OS-agnostic |
| `OnShellScaling` | OS-agnostic |
| `OnBalloonScaling` | OS-agnostic |
| `OnLanguageChange` | OS-agnostic |
| `OnResetWindowPos` | OS-agnostic |
| `OnNotifySelfInfo` | OS-agnostic |
| `OnNotifyBalloonInfo` | OS-agnostic |
| `OnNotifyShellInfo` | OS-agnostic |
| `OnNotifyDressupInfo` | Dressup hooks (SERIKO parts) |
| `OnNotifyUserInfo` | OS-agnostic |
| `OnNotifyOSInfo` | OS-agnostic |
| `OnNotifyFontInfo` | OS-agnostic |
| `OnNotifyInternationalInfo` | OS-agnostic |
| `OnRequestValues` | OS-agnostic |
| `OnGetValues` | OS-agnostic |
| `OnTalkRequest` | OS-agnostic |
| `OnHandActivate` | OS-agnostic |
| `OnJitenBattle` | OS-agnostic |
| `OnJitenTagBattle` | OS-agnostic |
| `OnMglBattle` | OS-agnostic |
| `OnKanadeTeaPartyInfomationRequest` | OS-agnostic |
| `OnKanadeTeaParty` | OS-agnostic |
| `OnKanadeTeaPartyEnd` | OS-agnostic |
| `OnPoker` | OS-agnostic |
| `OnPokerNotify` | OS-agnostic |
| `OnMopClear` | OS-agnostic |
| `OnNeedlePoke` | OS-agnostic |
| `OnBeerShower` | OS-agnostic |
| `OnDive` | OS-agnostic |
| `OnHitThunder` | OS-agnostic |
| `OnStampInfo` | OS-agnostic |
| `OnStampAdd` | OS-agnostic |
| `OnStampInfoCall` | OS-agnostic |
| `OnPotatoReturn` | OS-agnostic |
| `OnPotatoFileNotFound` | OS-agnostic |
| `OnPotatoError` | OS-agnostic |
| `OnCrystalDiskInfoEvent` | OS-agnostic |
| `OnCrystalDiskInfoClear` | OS-agnostic |
| `OnWeatherStation` | OS-agnostic |
| `OnSpectrePlugin` | OS-agnostic |
| `OnHttpcNotify` | OS-agnostic |
| `OnKinokoObjectCreate` | OS-agnostic |
| `OnKinokoObjectDestroy` | OS-agnostic |
| `OnKinokoObjectChanging` | OS-agnostic |
| `OnKinokoObjectChanged` | OS-agnostic |
| `OnKinokoObjectInstalled` | OS-agnostic |
| `OnSysResourceLow` | OS-agnostic |
| `OnSysResourceCritical` | OS-agnostic |
| `OnNekodorifObjectEmerge` | OS-agnostic |
| `OnNekodorifObjectHit` | OS-agnostic |
| `OnNekodorifObjectDrop` | OS-agnostic |
| `OnNekodorifObjectVanish` | OS-agnostic |
| `OnNekodorifObjectDodge` | OS-agnostic |
| `OnMusicPlay` | OS-agnostic |
| `OnFleetClockComplete` | OS-agnostic |
| `OnElonaOmakeMMAEventNewGame` | OS-agnostic |
| `OnElonaOmakeMMAEventGameLoad` | OS-agnostic |
| `OnElonaOmakeMMAEventGameQuit` | OS-agnostic |
| `OnElonaOmakeMMAEventHourPlayed` | OS-agnostic |
| `OnElonaOmakeMMAEventMapChanged` | OS-agnostic |
| `OnElonaOmakeMMAEventLevelUp` | OS-agnostic |
| `OnElonaOmakeMMAEventSkillUp` | OS-agnostic |
| `OnElonaOmakeMMAEventSkillDown` | OS-agnostic |
| `OnElonaOmakeMMAEventBelieveGod` | OS-agnostic |
| `OnElonaOmakeMMAEventJoinParty` | OS-agnostic |
| `OnElonaOmakeMMAEventSleep` | OS-agnostic |
| `OnElonaOmakeMMAEventAwake` | OS-agnostic |
| `OnElonaOmakeMMAEventInvestNPC` | OS-agnostic |
| `OnElonaOmakeMMAEventRandomEvent` | OS-agnostic |
| `OnElonaOmakeMMAEventAddNewsTopic` | OS-agnostic |
| `OnElonaOmakeMMAEventWish` | OS-agnostic |
| `OnElonaOmakeMMAEventWished` | OS-agnostic |
| `OnElonaOmakeMMAEventDead` | OS-agnostic |
| `OnElonaOmakeMMAEventPetDead` | OS-agnostic |
| `OnElonaOmakeMMAEventLastword` | OS-agnostic |
| `OnElonaOmakeMMAEventTravelGuide` | OS-agnostic |
| `OnElonaOmakeMMAEventAbandonPet` | OS-agnostic |
| `OnElonaOmakeMMAEventSaleSlave` | OS-agnostic |
| `OnElonaOmakeMMAEventSaleWife` | OS-agnostic |
| `OnElonaOmakeMMAEventMarriage` | OS-agnostic |
| `OnElonaOmakeMMAEventRefuseMarriage` | OS-agnostic |
| `OnElonaOmakeMMAEventJoinGuild` | OS-agnostic |
| `OnElonaOmakeMMAEventMutation` | OS-agnostic |
| `OnElonaOmakeMMAEventMutationCured` | OS-agnostic |
| `OnElonaOmakeMMAEventEtherDisease` | OS-agnostic |
| `OnElonaOmakeMMAEventEtherDiseaseCured` | OS-agnostic |
| `OnElonaOmakeMMAEventAdventGod` | OS-agnostic |
| `OnElonaOmakeMMAEventMewmewmew` | OS-agnostic |
| `OnElonaOmakeMMAEventBuyNuke` | OS-agnostic |
| `OnElonaOmakeMMAEventSetNuke` | OS-agnostic |
| `OnElonaOmakeMMAEventNukeExploded` | OS-agnostic |
| `OnElonaOmakeMMAEventLomiasInTheParty` | OS-agnostic |
| `OnElonaOmakeMMAEventLomiasKilled` | OS-agnostic |
| `OnElonaOmakeMMAEventZeomeKilled` | OS-agnostic |
| `OnElonaOmakeMMAEventConqueredLesimas` | OS-agnostic |
| `OnElonaOmakeMMAEventAtonement` | OS-agnostic |
| `OnElonaOmakeMMAEventBecomeCriminal` | OS-agnostic |
| `OnElonaOmakeMMAEventPerformance` | OS-agnostic |
| `OnElonaOmakeMMAEventClothOut` | OS-agnostic |
| `OnElonaOmakeMMAEventStealItem` | OS-agnostic |
| `OnElonaOmakeMMAEventTreasureDigging` | OS-agnostic |
| `OnElonaOmakeMMAEventReadTreasureMap` | OS-agnostic |
| `OnElonaOmakeMMAEventSkillLearned` | OS-agnostic |
| `OnElonaOmakeMMAEventWeatherChanged` | OS-agnostic |
| `OnElonaOmakeMMAEventRagnarok` | OS-agnostic |
| `OnElonaOmakeMMAEventSisterRagnarok` | OS-agnostic |
| `OnElonaOmakeMMAEventPray` | OS-agnostic |
| `OnElonaOmakeMMAEventOffer` | OS-agnostic |
| `OnElonaOmakeMMAEventPrayFailed` | OS-agnostic |
| `OnElonaOmakeMMAEventPrayEyth` | OS-agnostic |
| `OnElonaOmakeMMAEventAreaChanged` | OS-agnostic |
| `OnElonaOmakeMMAEventPayTax` | OS-agnostic |
| `OnElonaOmakeMMAEventCooking` | OS-agnostic |
| `OnElonaOmakeMMAEventHour` | OS-agnostic |
| `OnElonaOmakeMMAEventGrandmapocalypse` | OS-agnostic |
| `OnMahjong` | OS-agnostic |
| `OnMahjongResponse` | OS-agnostic |
| `OnNostr` | OS-agnostic |
| `OnSatolistBoot` | OS-agnostic |
| `OnSatolistGhostOpened` | OS-agnostic |
| `OnSatolistSaved` | OS-agnostic |
| `OnSatolistClosed` | OS-agnostic |
| `OnSatolistEventAdded` | OS-agnostic |
| `OnSatolistDictionaryFolderChanged` | OS-agnostic |
| `OnTourabuConquestStart` | OS-agnostic |
| `OnTourabuConquestEnd` | OS-agnostic |
| `OnTourabuDutyStart` | OS-agnostic |
| `OnTourabuDutyEnd` | OS-agnostic |
| `OnElinAllyCondition` | OS-agnostic |
| `OnElinAllyDead` | OS-agnostic |
| `OnElinCatchFish` | OS-agnostic |
| `OnElinMapCharaGenerate` | OS-agnostic |
| `OnElinMapEnter` | OS-agnostic |
| `OnElinMapItemGenerate` | OS-agnostic |
| `OnElinPCCondition` | OS-agnostic |
| `OnElinPCDead` | OS-agnostic |
| `OnElinTarget` | OS-agnostic |
| `OnApplicationBoot` | OS-agnostic |
| `OnApplicationClose` | OS-agnostic |
| `OnApplicationExist` | OS-agnostic |
| `OnApplicationVersion` | OS-agnostic |
| `OnApplicationOperationFinish` | OS-agnostic |
| `OnApplicationFileOpen` | OS-agnostic |
| `OnWebsiteUpdateNotify` | OS-agnostic |
| `OnUkadocScriptExample` | OS-agnostic |


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
