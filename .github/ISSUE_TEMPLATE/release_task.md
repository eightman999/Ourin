---
name: Release task / リリース作業
about: リリース条件・検証・復旧方法を記録 / Track release work and validation
title: "[Release] "
---

## 対象版と影響 / Target version and impact

優先度 / Priority: 未判定 / Untriaged（P0/P1/P2と理由 / with rationale）
リリース阻害 / Blocks release: はい・いいえ・未判定 / yes, no, untriaged
親リリースIssue / Parent release tracker:

## 実施内容 / Work

## 検証方法 / Validation

<!-- 対象OS/CPU、クリーン環境、署名・公証・NAR導入・保存・再起動等の該当項目。
Relevant OS/CPU, clean installation, signing/notarization, NAR installation, save/reload checks. -->

## 失敗時の扱い・復旧 / Failure handling and rollback

<!-- 対象・バックアップ・復旧手順。秘密鍵・認証情報の値は記載しない。
Identify the target, backup, and recovery procedure. Never include credential values. -->

## 完了条件 / Acceptance criteria

- [ ] 対象ゲートの実行結果を記録 / Record actual gate results
- [ ] 未検証項目と配布可否の判断を記録 / Record remaining gaps and release decision
- [ ] リリースノートに既知の問題へのリンクを含める / Link Known Issues from release notes
  - 日本語: https://github.com/eightman999/Ourin/blob/master/docs/KNOWN_ISSUES_ja-jp.md
  - English: https://github.com/eightman999/Ourin/blob/master/docs/KNOWN_ISSUES_en-us.md
