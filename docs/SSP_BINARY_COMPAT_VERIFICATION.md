# SSP 2.8.35f バイナリ互換検証

**更新**: 2026-08-19  
**正本**: `/Users/eightman/Downloads/ssp_2_8_35f/` の exe を Ghidra デコンパイルした挙動  
**作業領域（git 外）**: `~/dev/apps/Ourin-decomp/`

## 結論

完全互換ではない。SSTP / SHIORI を中心にギャップを issue 化した。21 作業単位（WU）の網羅は継続中。

詳細サマリ: `~/dev/apps/Ourin-decomp/reports/COMPATIBILITY_SUMMARY.md`

## 作成済み issue（`compat-verify`）

| # | 内容 | P |
|---|------|---|
| [#106](https://github.com/eightman999/Ourin/issues/106) | Sender+User-Agent 両方無し → 400 | P1 |
| [#107](https://github.com/eightman999/Ourin/issues/107) | SHIORI 非標準ステータス → 204 丸め | P2 |
| [#108](https://github.com/eightman999/Ourin/issues/108) | X-Force-Activate-Me | P2 |
| [#109](https://github.com/eightman999/Ourin/issues/109) | FINE メソッド | P3 |
| [#110](https://github.com/eightman999/Ourin/issues/110) | X-SSTP-Return- フォールバック | P2 |
| [#111](https://github.com/eightman999/Ourin/issues/111) | ネイティブ SHIORI wire 形式（要確認） | P1 |
| [#112](https://github.com/eightman999/Ourin/issues/112) | SecurityOrigin: null | P2 |
| [#113](https://github.com/eightman999/Ourin/issues/113) | EXECUTE コマンド不足（SSFExec/URLExec/CallGhost 等） | P1 |
| [#114](https://github.com/eightman999/Ourin/issues/114) | mcp.exe 対象外 | P3 |
| [#115](https://github.com/eightman999/Ourin/issues/115) | Property selfname ≡ sakuraname | P2 |
| [#116](https://github.com/eightman999/Ourin/issues/116) | SERIKO interval 略称・never 複合 | P2 |
| [#117](https://github.com/eightman999/Ourin/issues/117) | SERIKO method ccyr / noop | P3 |
| [#118](https://github.com/eightman999/Ourin/issues/118) | Input scriptbox 未実装 | P2 |
| [#119](https://github.com/eightman999/Ourin/issues/119) | Calendar PlayTodaysEvent | P2 |
| [#120](https://github.com/eightman999/Ourin/issues/120) | Cookie ディスク永続化 | P2 |
| [#121](https://github.com/eightman999/Ourin/issues/121) | SaveShare クラウドセーブ | P2 |
| [#122](https://github.com/eightman999/Ourin/issues/122) | IP Messenger | P3 |
| [#123](https://github.com/eightman999/Ourin/issues/123) | Sound ストリーミング URL | P2 |
| [#124](https://github.com/eightman999/Ourin/issues/124) | FineFMO | P3 |

**合計 19 issue（#106–#124）。完全互換ではない。**

## 再実行

```bash
# デコンパイル再実行（要 Ghidra）
~/dev/apps/Ourin-decomp/scripts/run_ghidra.sh ssp
~/dev/apps/Ourin-decomp/scripts/run_ghidra.sh ssph

# シンボル索引
python3 ~/dev/apps/Ourin-decomp/scripts/make_index.py \
  ~/Downloads/ssp_2_8_35f/ssp.map ~/dev/apps/Ourin-decomp/index/ssp
```

## 関連

- [IMPLEMENTATION_STATUS_SUMMARY.md](IMPLEMENTATION_STATUS_SUMMARY.md)
- [AUDITS_TODO.md](AUDITS_TODO.md) / [AUDITS_COMPLETED.md](AUDITS_COMPLETED.md)
