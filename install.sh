#!/usr/bin/env bash
# claude-harness 설치 — 이 저장소를 Claude Code 사용자 설정(~/.claude)에 연결한다.
#   ~/.claude/harness           → 이 저장소 (스킬이 shared/ · config 를 여기서 읽는다)
#   ~/.claude/skills/<스킬>      → skills/<스킬> (심볼릭 링크)
#   ~/.claude/agents/<에이전트>  ← agents/*.md (복사 — 에이전트 링크는 문서로 보장되지 않아서)
# 다시 돌려도 된다. 에이전트 · 스킬을 고친 뒤에는 다시 돌린다.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
new_agents_dir=0
[ -d "$CLAUDE_DIR/agents" ] || new_agents_dir=1
mkdir -p "$CLAUDE_DIR/skills" "$CLAUDE_DIR/agents"

link() {  # link <대상> <링크 경로>
  if [ -e "$2" ] && [ ! -L "$2" ]; then
    echo "  건너뜀: $2 — 링크가 아닌 파일이 이미 있음 (직접 확인하세요)"; return
  fi
  ln -sfn "$1" "$2"; echo "  연결: $2 → $1"
}

echo "claude-harness 설치 ($REPO)"
link "$REPO" "$CLAUDE_DIR/harness"
for d in "$REPO"/skills/*/; do
  name="$(basename "$d")"
  link "${d%/}" "$CLAUDE_DIR/skills/$name"
done
for f in "$REPO"/agents/*.md; do
  cp "$f" "$CLAUDE_DIR/agents/"; echo "  복사: $CLAUDE_DIR/agents/$(basename "$f")"
done
if [ ! -f "$REPO/config.local.json" ]; then
  cp "$REPO/config.example.json" "$REPO/config.local.json"
  echo "  설정 파일을 만들었습니다: $REPO/config.local.json — /harness-setup 으로 채우세요"
fi
echo "완료. 스킬: /web-full · /web-lite · /harness-setup"
if [ "$new_agents_dir" = 1 ]; then
  echo "※ 에이전트 폴더를 새로 만들었습니다. 열려 있는 Claude Code 를 다시 시작해야 작업자 에이전트가 보입니다."
fi
