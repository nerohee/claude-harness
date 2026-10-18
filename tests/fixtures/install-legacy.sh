#!/usr/bin/env bash
# claude-harness 설치 — 이 저장소를 Claude Code 사용자 설정(~/.claude)에 연결한다.
#   ~/.claude/harness           → 이 저장소 (스킬이 shared/ · config 를 여기서 읽는다)
#   ~/.claude/skills/<스킬>      → skills/<스킬> (심볼릭 링크)
#   ~/.claude/agents/<에이전트>  ← agents/*.md + agents/_common/ (합쳐서 복사 — 에이전트 링크는 문서로 보장되지 않아서)
# 다시 돌려도 된다. 에이전트 · 스킬을 고친 뒤에는 다시 돌린다.
#   bash install.sh --check   설치하지 않고, 설치된 작업자가 저장소와 같은지만 본다 (다르면 종료 코드 1)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
RETIRED="harness-builder harness-builder-deep"  # 이름이 바뀌어 저장소에서 빠진 예전 작업자
COMMON="$REPO/agents/_common"
MARK='<!-- harness:common -->'

check_agent() {  # check_agent <원본> — 틀이 맞는지 본다
  local f="$1" base; base="$(basename "$f" .md)"
  if [ "$(sed -n 2p "$f")" != "name: $base" ]; then
    echo "  오류: $f — 두 번째 줄이 'name: $base' 이어야 한다" >&2; return 1
  fi
  if sed -n '2,/^---$/p' "$f" | grep -q '^hooks:'; then
    echo "  오류: $f — hooks 는 쓰지 않는다 (설치할 때 agents/_common/hooks.yml 이 붙는다)" >&2; return 1
  fi
}

build_agent() {  # build_agent <원본> — 앞머리 끝에 hooks.yml, 표시 줄 자리(없으면 끝)에 rules.md 를 넣어 출력한다
  awk -v hooks="$COMMON/hooks.yml" -v rules="$COMMON/rules.md" -v mark="$MARK" '
    function put(f,  l) { while ((getline l < f) > 0) print l; close(f) }
    NR == 1 && $0 == "---" { fm = 1; print; next }
    fm && $0 == "---"      { put(hooks); print; fm = 0; next }
    $0 == mark             { put(rules); done = 1; next }
                           { print }
    END { if (!done) { print ""; put(rules) } }
  ' "$1"
}

if [ "${1:-}" = "--check" ]; then
  diff=0
  for f in "$REPO"/agents/*.md; do
    t="$CLAUDE_DIR/agents/$(basename "$f")"
    if [ ! -f "$t" ]; then echo "빠짐: $(basename "$f")"; diff=1
    elif ! build_agent "$f" | cmp -s - "$t"; then echo "다름: $(basename "$f")"; diff=1; fi
  done
  for r in $RETIRED; do
    if [ -f "$CLAUDE_DIR/agents/$r.md" ]; then echo "남음 (예전 작업자): $r.md"; diff=1; fi
  done
  [ "$diff" = 0 ] && echo "작업자: 저장소와 같음"
  exit "$diff"
fi

for f in "$REPO"/agents/*.md; do check_agent "$f"; done

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
for r in $RETIRED; do
  t="$CLAUDE_DIR/agents/$r.md"
  if [ -f "$t" ]; then rm "$t"; echo "  지움 (예전 작업자): $t"; fi
done
for f in "$REPO"/agents/*.md; do
  build_agent "$f" > "$CLAUDE_DIR/agents/$(basename "$f")"
  echo "  설치: $CLAUDE_DIR/agents/$(basename "$f") (+ 공통 규칙 · 가드 hook)"
done
if [ ! -f "$REPO/config.local.json" ]; then
  cp "$REPO/config.example.json" "$REPO/config.local.json"
  echo "  설정 파일을 만들었습니다: $REPO/config.local.json — /harness-setup 으로 채우세요"
fi
echo "완료. 스킬: /web-full · /web-lite · /desktop-app · /harness-resume · /harness-setup"
if [ "$new_agents_dir" = 1 ]; then
  echo "※ 에이전트 폴더를 새로 만들었습니다. 열려 있는 Claude Code 를 다시 시작해야 작업자 에이전트가 보입니다."
fi
