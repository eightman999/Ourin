# AI Orchestration Guide

マルチエージェント運用の実務手順書。Fable 5 がリードとして計画・分解・委譲・統合を行い、
Opus / Sonnet サブエージェントと外部ピアツール（Codex / Agy / OpenCode(GLM)）を使い分ける。

## Roles

| Agent | Role | Default mode |
|---|---|---|
| Fable 5 (main) | オーケストレーター・テックリード・最終判断 | high/xhigh, max は最終統合・行き詰まりデバッグ・不可逆判断のみ |
| deep-reasoner (Opus) | 設計・難デバッグ・アルゴリズム・高リスク判断の推論 | read-only 中心、簡潔な結論を返す |
| fast-worker (Sonnet) | 機械的編集・boilerplate・テスト・整形 | 最小スコープで実行 |
| Codex CLI | ピアシニアエンジニア・救援・敵対的レビュー・独立セカンドオピニオン | オンデマンド（常時レビューゲートにしない） |
| Agy CLI | 長文コンテキスト監査・ドキュメント整合・ログ圧縮 | read-only |
| OpenCode(GLM) | 第二実装レーン | 別 worktree / `glm/<task>` ブランチ |

## Routing table

```text
Normal small task:
Fable + fast-worker

Medium implementation:
Fable + fast-worker + optional OpenCode(GLM)

Large implementation:
Fable + OpenCode(GLM) in worktree + fast-worker for integration

Hard design:
Fable + deep-reasoner + Agy

Stuck debugging:
Fable + Codex rescue + deep-reasoner

High-risk change:
Fable + deep-reasoner + Codex + Agy
```

## Flows

### 1. Normal task flow
1. Fable がミッション（MISSION.template.md）を読み、計画を立てる。
2. 機械的な部分は fast-worker に委譲。判断が要る部分だけ Fable が実装。
3. Fable が統合し、テストを実行して出力を確認（「通るはず」禁止）。
4. `git status` / `git diff` で実変更を確認してから完了報告。

### 2. Difficult debugging flow
1. Fable が再現手順とエラーログを最小化。
2. deep-reasoner に read-only で原因仮説を出させる（結論・根拠・リスク・次アクション）。
3. 2回試して直らない／ループし始めたら Codex に救援を依頼（独立視点で同じ問題を渡す）。
4. Fable が両者の仮説を突き合わせ、最小の修正を適用。

### 3. High-risk flow（データ損失・マイグレーション・セキュリティ・並行処理・公開API・大規模設計）
1. deep-reasoner に独立に設計/リスク評価させる。
2. Codex に独立に同じ問いを投げる（相互の回答は見せない）。
3. Agy に前提・ドキュメント整合を監査させる（read-only）。
4. 必要なら OpenCode(GLM) に隔離 worktree で実装試行させる。
5. Fable が全出力を比較し、最小安全パスを選択。不可逆操作の前にユーザー確認。

### 4. OpenCode(GLM) worktree flow
```bash
# メインリポジトリで
git worktree add ../<repo-name>-glm -b glm/<task-name>
cd ../<repo-name>-glm
opencode   # ミッションを渡す
```
- 完了後、OpenCode に必須レポート（変更ファイル・アプローチ・実行テスト・リスク・未解決事項）を出させる。
- Fable がメイン側で diff をレビューし、cherry-pick または merge。
- 終わったら `git worktree remove ../<repo-name>-glm`（未マージ変更がないことを確認してから）。
- **禁止**: `/share`、公開同期、メインブランチへの直接push。

### 5. Agy audit flow
- 用途: 大規模リポジトリスキャン、CLAUDE.md/AGENTS.md/README/docs の整合チェック、
  隠れた前提の検出、ログ圧縮、「実装はミッションを満たしているか」監査。
- 常に read-only 指示で起動し、AGENTS.md の Default prompt を使う。
- 出力は 6 項目（結論・隠れた前提・矛盾・影響ファイル・リスク・推奨次アクション）に圧縮させる。

### 6. Codex rescue flow
- 発動条件: Claude が同じ修正を 2 回以上失敗、または設計判断が割れて進まない。
- Codex プラグイン（codex@openai-codex 1.0.5, 導入済み・実在コマンド確認済み）:
  - `/codex:review` — 直前の変更のレビュー
  - `/codex:adversarial-review` — 敵対的レビュー（高リスクマージ前）
  - `/codex:rescue --background` — 救援（バックグラウンド実行、`codex-rescue` エージェント）
  - `/codex:result` / `/codex:status` / `/codex:cancel` — ジョブの結果取得・状態確認・中止
  - `/codex:transfer` — セッション引き継ぎ
- stop-review-gate（毎ターン自動レビュー）は **既定で無効**。方針どおり有効化しない。
  必要になった場合のみ `/codex:setup --enable-review-gate`、戻すときは `--disable-review-gate`。
- 代替経路: cc-workers MCP の codex worker、または codex CLI 直接。
  いずれも最小化した問題記述 + 関連ファイルパスを渡し、独立解を得る。
- Codex の提案も無検証で採用しない。Fable がテストで裏取りしてから統合。

## Merge / integration policy
- 統合は常に Fable（メイン）が行う。外部エージェントに直接 merge させない。
- 複数エージェントが同一ファイルを同時編集することを禁止。並行させる場合は worktree で隔離。
- worktree からの取り込みは diff レビュー → テスト実行 → merge の順。
- コミットはユーザー指示があるまで行わない（Conventional Commits）。

## Cost-control policy
- 既定は Fable high/xhigh。max は最終統合・行き詰まり・不可逆判断のみ。
- Opus (deep-reasoner) は本当に推論が重いタスクだけ。調査・棚卸しは investigator/Sonnet で足りる。
- Codex は高リスク判断でコストに見合う場合のみ。常時レビューゲートは張らない。
- 大量ファイル読み込み・横断調査はメインで行わず、サブエージェント/worker に委譲してメインコンテキストを節約。
- サブエージェントの返答は「結論・根拠・変更ファイル・リスク・次アクション」の 5 点に圧縮させる。
