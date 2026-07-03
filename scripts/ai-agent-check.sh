#!/usr/bin/env bash
# AI agent tool availability & repo status check (read-only, no secrets)
set -u

echo "=== AI Agent Environment Check ==="
echo

echo "--- Tool availability ---"
for cmd in git node npm claude codex opencode agy; do
    if command -v "$cmd" >/dev/null 2>&1; then
        ver="$("$cmd" --version 2>/dev/null | head -1 || true)"
        printf "  %-10s OK    %s\n" "$cmd" "$ver"
    else
        printf "  %-10s MISSING\n" "$cmd"
    fi
done
echo

echo "--- Git status ---"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "  repo root: $(git rev-parse --show-toplevel)"
    echo "  branch:    $(git branch --show-current 2>/dev/null || echo '(detached)')"
    dirty="$(git status --short | wc -l | tr -d ' ')"
    echo "  changes:   ${dirty} file(s) modified/untracked"
    echo "  worktrees:"
    git worktree list | sed 's/^/    /'
else
    echo "  NOT a git repository"
fi
echo

echo "--- Config files ---"
for f in CLAUDE.md AGENTS.md MISSION.template.md docs/AI_ORCHESTRATION.md; do
    if [ -f "$f" ]; then
        printf "  %-40s exists\n" "$f"
    else
        printf "  %-40s MISSING\n" "$f"
    fi
done
# サブエージェント定義はリポジトリ側かユーザーレベル(~/.claude/agents/)のどちらかにあればよい
for a in deep-reasoner fast-worker; do
    if [ -f ".claude/agents/${a}.md" ]; then
        printf "  %-40s exists (repo)\n" ".claude/agents/${a}.md"
    elif [ -f "${HOME}/.claude/agents/${a}.md" ]; then
        printf "  %-40s exists (user-level)\n" "agent: ${a}"
    else
        printf "  %-40s MISSING\n" "agent: ${a}"
    fi
done
echo
echo "=== Check complete (no files modified) ==="
