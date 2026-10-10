#!/usr/bin/env bash
# claude-harness 제거 — install.sh 가 만든 링크와 복사한 에이전트만 지운다. 저장소와 프로젝트 문서는 그대로.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
for d in "$REPO"/skills/*/; do
  t="$CLAUDE_DIR/skills/$(basename "$d")"
  [ -L "$t" ] && rm "$t" && echo "  지움: $t"
done
for f in "$REPO"/agents/*.md; do
  t="$CLAUDE_DIR/agents/$(basename "$f")"
  [ -f "$t" ] && rm "$t" && echo "  지움: $t"
done
[ -L "$CLAUDE_DIR/harness" ] && rm "$CLAUDE_DIR/harness" && echo "  지움: $CLAUDE_DIR/harness"
echo "완료."
