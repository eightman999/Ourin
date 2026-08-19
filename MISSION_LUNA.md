# Mission — Luna (Codex CLI) 再起動用指示書

**作成日**: 2026-08-15（Devin CLI セッションからの引き継ぎ）
**対象**: Codex CLI「Luna」。起動時に `~/.codex/AGENTS.md` と本リポジトリの `AGENTS.md` / `CLAUDE.md` が自動適用される前提。本書はそれらと重複しない「現在地」と「次の仕事」だけを書く。

## Goal

Ourin の残タスクを `docs/AUDITS_TODO.md`（2026-08-15 一新済み・**唯一の正**）に従って消化する。
最優先は「1. 実ゴースト・実機検証待ち」の P2 群。ただし**どの項目から着手するかは、必ずユーザーに1行確認してから**始めること。

## Context（2026-08-15 時点の現在地）

- ブランチ: `codex/publish-all-changes`（origin より 169+ コミット先行、**未push**。push はユーザー指示があるまで禁止）
- 直近の完了作業（コミット済み、詳細は `git log --oneline -6`）:
  - `db24f41` 全mdとコードの整合性監査。完了済み計画書・テンプレ19ファイルを `docs/archive/` へ移動。`docs/AUDITS_TODO.md` を未完項目のみに一新（完了項目は `docs/AUDITS_COMPLETED.md` の「移管記録」へ）
  - `d4e7604` 第2次docs監査の修正（SUPPORTED_SAKURA_SCRIPT の move/moveasync/scaling/alpha は✅済み等）
  - `f5898b7` + `edeede6` docs/html を全再生成。`generate_html.py` の命名 off-by-one（`[:-10]`→`[:-9]`）修正済み。リンク切れ0件を検証済み
- ドキュメントの正本関係:
  - 未完タスク = `docs/AUDITS_TODO.md` ／ 完了記録 = `docs/AUDITS_COMPLETED.md`（file:line は判定時点のもの。シンボル名を優先）
  - さくらスクリプト対応状況 = `docs/SAKURASCRIPT_COMMANDS_SUPPORTED_*`（網羅）と `docs/SUPPORTED_SAKURA_SCRIPT*`（要約）
  - `TODO/todo.md` は DEPRECATED（履歴用残置。更新・削除しない）
  - `docs/archive/` は歴史的文書置き場（**一切触らない**）

## Constraints

- `docs/AUDITS_TODO.md` の項目はコード実装・単体テスト済みのものが大半。残作業は「実ゴースト/実機での検証」なので、**テストパスを完了扱いにしない**。分野別完了基準: Ourin は「アプリを実際に起動して該当機能を1回操作」まで
- 検証で不具合を見つけたら、その場で直さず AUDITS_TODO に項目追加 → ユーザーに報告 → 指示を待つ（スコープ厳守）
- md を更新したら対応する HTML も再生成する: `cd docs && uv run --with markdown python3 generate_html.py`（システム python3 に markdown は無い。シム自作は禁止。サンドボックスで uv キャッシュにアクセスできない場合は python3 -m venv でリポジトリ内に venv を作り pip install markdown）
- ビルド/テスト: `xcodebuild -project Ourin.xcodeproj -scheme Ourin build` / `test`。yaya_core は `cd yaya_core && ./build.sh`

## Relevant files

- `docs/AUDITS_TODO.md` — 残タスク一覧（優先度付き）
- `docs/AUDITS_COMPLETED.md` — 完了根拠（末尾に2026-08-15移管記録）
- `docs/SHIORI_RUNTIME_COMPATIBILITY_MATRIX_ja-jp.md` — ランタイム互換の受け入れ条件
- `emily4/` `emily4.nar` — 実ゴースト検証用アセット（Emily4）
- `OurinTests/` — 98テストスイート（回帰確認用）

## Acceptance criteria

- 着手した AUDITS_TODO 項目について、実機/実ゴーストでの操作結果（何をどう操作し何が表示されたか）を記録して報告
- 検証済み項目は AUDITS_TODO から AUDITS_COMPLETED へ根拠付きで移す（日付明記）
- `git status` / 実行ログを添えた完了報告（「動くはず」禁止、未検証範囲を明記）

## Do not

- push・force-push（ユーザー指示があるまで）
- `docs/archive/` と `TODO/todo.md` の変更
- AUDITS_TODO にない作業の「ついで」実施
- 依存パッケージのシム・スタブ自作（2026-08-15 に偽 markdown シムで壊れたHTMLを量産しかけた事故あり）

## Suggested routing

- Codex (Luna): 実機検証の実施・検証結果の文書化・小規模修正
- Fable (Claude Code): 統合判断・コミット・監査の突合
- Agy: read-only での docs/コード整合の再監査
- OpenCode(GLM): 独立した実装レーン（別worktree）

## Required final report

- changed files
- tests run（実出力添付）
- 実機検証の操作記録（未検証範囲を明示）
- risks
- unresolved questions
