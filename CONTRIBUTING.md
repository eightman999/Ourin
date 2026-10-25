# Ourinへの貢献 / Contributing to Ourin

開発環境とビルドは[README](README.md)、報告前の確認は[既知の問題](docs/KNOWN_ISSUES_ja-jp.md)と[バグ報告ガイド](docs/BUG_REPORT_GUIDE_ja-jp.md)を参照してください。
See the [README](README.md) for setup, and check [Known Issues](docs/KNOWN_ISSUES_en-us.md) and the [Bug Report Guide](docs/BUG_REPORT_GUIDE_en-us.md) before reporting.

## Issueを起点にする / Start with an issue

機能追加・不具合修正・互換性改善・リリース作業、仕様や運用を変える文書修正は、原則として着手前にIssueを用意します。背景・目的・対象範囲・Acceptance Criteria（完了条件）を記載し、大型作業はMeta Issueと子Issueに分けます。既存の同内容Issueがあればそこへ再現条件を追加します。[Issue一覧](https://github.com/eightman999/Ourin/issues)からBug、Feature / Compatibility、Release taskのテンプレートを選んでください。

Create or reuse an issue before implementation, including documentation that changes behavior or process. Record the motivation, scope, and acceptance criteria. Split large changes into a meta issue and child issues; add reproductions to an existing matching issue instead of creating duplicates. Use the Bug, Feature / Compatibility, or Release task template from the [issue list](https://github.com/eightman999/Ourin/issues).

| 優先度 / Priority | 定義 / Definition |
|---|---|
| P0 | 対象リリースを止める問題。起動不能、データ破損、重大なセキュリティ問題、必須配布ゲートなど。 / Blocks the target release: startup failure, data corruption, critical security defects, or required distribution gates. |
| P1 | 正式版品質に必要な機能・互換性・検証。リリース対象への採否をIssueで明示。 / Required product quality, compatibility, or validation; state whether it blocks the particular release. |
| P2 | 後続改善。回避可能な細部や将来機能。 / Follow-up improvements and future features. |

タイトルの`[P0]`/`[P1]`/`[P2]`または対応ラベルで管理します。報告者が判断できない場合は「未判定」で構いません。重大な理由と影響を記し、メンテナーが判定します。
Use a title prefix or corresponding label. Reporters may leave priority untriaged; describe the impact and let maintainers triage it.

## 互換性変更 / Compatibility changes

- SSP/UKADOCまたは固定版の上流実装を根拠に、仕様・最小再現入力・Ourinの結果をIssueに残します。ゴーストを書き換えてOurin側の不具合を隠しません。
- fixture成功、実helper/IPC成功、実ゴーストの会話・保存・再起動、実画面確認は区別します。未検証を成功として扱いません。
- 利用者のゴースト・セーブデータは保全します。試験は許可された一時コピーで行い、配布許諾のないNARや辞書をリポジトリへ追加しません。

- Cite SSP/UKADOC or a pinned upstream implementation, a minimal reproducer, and the observed Ourin result. Do not mask a baseware defect by patching the ghost.
- Distinguish fixture tests, helper/IPC execution, real-ghost conversation/save/reload, and GUI checks. Unverified behavior is not a pass.
- Preserve user ghost and save data. Test authorized temporary copies; do not commit NARs or dictionaries without redistribution permission.

## PRと検証 / Pull requests and validation

1. PRに対象Issue、変更後の動作、実行した検証と結果、未確認範囲を記載します。完了条件をすべて満たす場合だけ`Closes #123`または`Fixes #123`を使い、部分対応は`Refs #123`と残件を記載します。
2. 変更に必要な検証を行います。Swiftは`xcodebuild -project Ourin.xcodeproj -scheme Ourin test`、対象を絞る場合は`-only-testing:OurinTests/TestClassName/testMethodName`を使用します。YAYA変更は`(cd yaya_core && ./build.sh)`、リリース情報は`python3 scripts/check_release_metadata.py`で確認します。実行ログにはPASS/FAIL/SKIPと理由を残します。
3. GUI・IPC・ゴースト動作の変更では、該当する実プロセスや画面操作も確認します。ローカル統合は公開版への反映とは別です。リリース時は[リリースゲート](docs/RELEASE_GATES_2026-10-25.md)とIssueの条件を確認します。
4. 修正済みの既知問題にはIssue/PR・検証日・検証版を残し、公開版に含まれたときに解消版を記録します。リリースノートには[既知の問題](docs/KNOWN_ISSUES_ja-jp.md)へのリンクを含めます。

1. Describe the issue, resulting behavior, actual validation, and remaining gaps. Use `Closes #123` / `Fixes #123` only when every acceptance criterion is met; otherwise use `Refs #123` and list remaining work.
2. Run checks appropriate to the change using the commands above. Record PASS/FAIL/SKIP and reasons rather than just an exit code.
3. Verify relevant real processes or UI interactions for GUI/IPC/ghost changes. Local integration does not imply a published fix. Check the [release gates](docs/RELEASE_GATES_2026-10-25.md) and issue criteria before a release.
4. Record the issue/PR, verification date, and tested version when fixing a known issue; add the released version after publication. Link [Known Issues](docs/KNOWN_ISSUES_en-us.md) from release notes.

## 例外 / Exceptions

意味を変えない誤字・書式修正は独立Issueを省略できます。PRに理由を一行残してください。緊急hotfixは先に修正しても構いませんが、再現条件・影響・検証結果・事後作業をIssueに記録し、遅くともPRのマージ時に関連付けます。これらの例外は外部公開・権限変更・ユーザーデータ変更などの承認を省略するものではありません。

An issue may be omitted for typos or formatting that do not change meaning; explain this briefly in the PR. Emergency hotfixes may start before filing, but must have a linked issue by merge time documenting reproduction, impact, validation, and follow-up work. These exceptions do not waive authorization for publication, permission changes, or user-data changes.
