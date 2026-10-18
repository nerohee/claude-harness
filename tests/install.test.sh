#!/usr/bin/env bash
# install.sh 시험 — 임시 폴더를 ~/.claude · 하네스 폴더로 돌린다. 실제 ~/.claude · ~/.claude-harness 는 건드리지 않는다.
#   bash tests/install.test.sh
# 필요한 것: bash · python3 (JSON 읽기) · sha256sum 또는 shasum.
# 기준: tests/fixtures/install-legacy.sh — 내 수정 · 백업이 생기기 전의 install.sh (내 수정이 없으면 같은 결과여야 한다)
set -u
export LC_ALL=C
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/harness-test.XXXXXX")"
export HOME="$TMP/home-dir"   # 어디서든 기본 위치로 새어 나가도 실제 ~/.claude 가 아니게
mkdir -p "$HOME"
unset CLAUDE_CONFIG_DIR CLAUDE_HARNESS_HOME CLAUDE_HARNESS_NO_SYMLINK
cleanup() { chmod -R u+rwx "$TMP" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT

command -v python3 >/dev/null 2>&1 || { echo "python3 가 필요합니다 (JSON 읽기)"; exit 2; }

PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); printf '  통과: %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  실패: %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "기대 [$3] 실제 [$2]"; fi; }
yes_() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$n"; else bad "$n" "명령이 실패: $*"; fi; }
no_() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then bad "$n" "명령이 성공해 버림: $*"; else ok "$n"; fi; }
head_() { printf '\n[%s]\n' "$1"; }

# ── 상자 (시험마다 새로 만든다) ──
copy_repo() { (cd "$REPO" && tar cf - --exclude=.git --exclude=./tests --exclude=./config.local.json .) | (cd "$1" && tar xf -); }
new_box() {
  BOX="$TMP/$1"; CL="$BOX/claude"; HH="$BOX/home"
  mkdir -p "$BOX/repo" "$BOX/legacy"
  copy_repo "$BOX/repo"
  copy_repo "$BOX/legacy"
  cp "$HERE/fixtures/install-legacy.sh" "$BOX/legacy/install.sh"
}
run() {  # run <옵션…> — OUT (표준 출력) · ERR (표준 오류) · RC
  OUT="$(CLAUDE_CONFIG_DIR="$CL" CLAUDE_HARNESS_HOME="$HH" bash "$BOX/repo/install.sh" "$@" 2>"$BOX/stderr")"; RC=$?
  ERR="$(cat "$BOX/stderr")"
}
run_legacy() {  # 같은 상자의 예전 install.sh — OUT · RC
  OUT="$(CLAUDE_CONFIG_DIR="$CL" bash "$BOX/legacy/install.sh" "$@" 2>&1)"; RC=$?
}
J() { printf '%s' "$OUT" | python3 -I -c "import json,sys; d=json.load(sys.stdin); print($1)"; }
snap() {  # snap <폴더> — 이름 · 종류 · 내용 해시 · 링크 대상 목록 (수정 시각은 빼고)
  (cd "$1" && find . -mindepth 1 | sort | while IFS= read -r f; do
    if [ -L "$f" ]; then echo "L $f -> $(readlink "$f")"
    elif [ -d "$f" ]; then echo "D $f"
    else echo "F $f $(sha256_ "$f")"; fi
  done)
}
sha256_() { if command -v sha256sum >/dev/null 2>&1; then sha256sum < "$1" | cut -d' ' -f1; else shasum -a 256 < "$1" | cut -d' ' -f1; fi; }
custom() {  # custom <상대 경로> <내용> — 내 수정 폴더에 파일을 둔다
  mkdir -p "$(dirname "$HH/custom/$1")"; printf '%s' "$2" > "$HH/custom/$1"
}
agent_text() { printf -- '---\nname: %s\ndescription: %s\nmodel: sonnet\n---\n\n너는 %s다.\n' "$1" "$2" "$3"; }
norm_out() { sed -e "s#$BOX/legacy#@REPO@#g" -e "s#$BOX/repo#@REPO@#g" -e "s#$BOX/c-old#@C@#g" -e "s#$BOX/c-new#@C@#g" -e "s#$BOX/claude#@C@#g"; }

# ═══════════════════════════════════════
head_ "1. 내 수정이 없으면 지금과 같다 (예전 install.sh 와 비교)"
new_box parity
OLD="$BOX/c-old"; NEW="$BOX/c-new"
CLAUDE_CONFIG_DIR="$OLD" bash "$BOX/legacy/install.sh" > "$BOX/old1.out" 2>&1; OLDRC=$?
CL="$NEW"; run; NEWRC=$RC
eq "첫 설치 종료 코드가 같다" "$NEWRC" "$OLDRC"
eq "첫 설치 출력이 같다 (개발자 모드 한 줄만 더 있음)" "$(printf '%s\n' "$OUT" | grep -v '개발자 모드 —' | norm_out)" "$(norm_out < "$BOX/old1.out")"
yes_ "에이전트 파일이 바이트까지 같다" diff -r "$OLD/agents" "$NEW/agents"
eq "하네스는 저장소로 가는 링크" "$(readlink "$NEW/harness")" "$BOX/repo"
for s in web-full web-lite desktop-app harness-resume harness-setup; do
  eq "스킬 링크 $s" "$(readlink "$NEW/skills/$s")" "$BOX/repo/skills/$s"
done
eq "링크 모양이 예전과 같다" "$(snap "$NEW" | grep '^L' | norm_out)" "$(snap "$OLD" | grep '^L' | norm_out)"
eq "내 수정 폴더는 만들지 않는다 (백업만)" "$(ls "$HH")" "backups"
no_ "상태 파일을 만들지 않는다" test -e "$NEW/.harness-installed"
yes_ "저장소에 설정 파일을 만들어 준다 (예전처럼)" test -f "$BOX/repo/config.local.json"
CL="$NEW"; run
CLAUDE_CONFIG_DIR="$OLD" bash "$BOX/legacy/install.sh" > "$BOX/old2.out" 2>&1
eq "다시 돌린 출력이 같다" "$(printf '%s\n' "$OUT" | grep -v '개발자 모드 —' | norm_out)" "$(norm_out < "$BOX/old2.out")"
eq "다시 돌려도 백업을 더 만들지 않는다" "$(ls "$HH/backups" | wc -l | tr -d ' ')" "1"

head_ "1-2. --check 가 예전과 같다"
CL="$NEW"
check_both() {  # check_both <이름> — 같은 상태에서 예전 · 지금 --check 를 비교
  CLAUDE_CONFIG_DIR="$NEW" bash "$BOX/legacy/install.sh" --check > "$BOX/oldc.out" 2>&1; local orc=$?
  run --check
  eq "$1 — 출력" "$OUT" "$(cat "$BOX/oldc.out")"
  eq "$1 — 종료 코드" "$RC" "$orc"
}
check_both "같을 때"
echo "손으로 고침" >> "$NEW/agents/harness-helper.md"; check_both "고쳐 둔 작업자"
rm "$NEW/agents/harness-tester.md"; check_both "빠진 작업자"
printf 'x\n' > "$NEW/agents/harness-builder.md"; check_both "남은 예전 작업자"
run; check_both "다시 설치한 뒤"

# ═══════════════════════════════════════
head_ "2. 값 바꾸기 · 덧붙이기 · 새 에이전트 · 새 스킬 · 통째 바꾸기 (복사 설치)"
new_box overlay
custom agents/harness-builder-ui.values.yml $'# 값만 바꾼다\neffort: high\nmodel: opus\nmaxTurns: 20\n'
custom agents/harness-builder-ui.append.md $'## 내 규칙\n- 시험 이름은 한국어로.\n'
custom agents/translator.md "$(agent_text translator "문서를 영어로 옮긴다" "번역가")"$'\n'
custom skills/mine/SKILL.md $'---\nname: mine\ndescription: 내 스킬\n---\n\n본문\n'
custom skills/web-lite/SKILL.values.yml $'effort: low\n'
printf '{"language":"en"}\n' > /dev/null; custom config.local.json $'{"language":"ko","mine":true}\n'
custom agent-cats.json '{"version":1,"agents":{}}'
mkdir -p "$HH/custom/.git"; echo x > "$HH/custom/.git/HEAD"
# 통째로 바꾸기 — 원본 해시를 같이 남긴다
run --origin-hash agents/harness-designer.md
HASH_DESIGNER="$OUT"
eq "원본 해시는 64글자" "${#HASH_DESIGNER}" "64"
sed 's/^description: .*/description: claude-harness 디자이너. 따뜻한 게임 UI 를 잘 아는 아트 디렉터./' "$BOX/repo/agents/harness-designer.md" > "$HH/custom/agents/harness-designer.md"
echo "$HASH_DESIGNER" > "$HH/custom/agents/harness-designer.md.origin"

run --plan --json
eq "미리보기는 문제 없이 끝난다" "$RC" "0"
eq "방식은 복사" "$(J "d['mode']")" "copy"
eq "내 수정 종류" "$(J "sorted(set(i['kind'] for i in d['custom']['items']))")" "['append', 'config', 'new', 'replace', 'values']"
eq "통째 바꾼 파일의 원본은 안 바뀜" "$(J "[i['originChanged'] for i in d['custom']['items'] if i['kind']=='replace']")" "[False]"
no_ "미리보기는 아무것도 쓰지 않는다 (~/.claude 가 없다)" test -e "$CL"
no_ "미리보기는 백업 폴더도 만들지 않는다" test -e "$HH/backups"
PLAN_JSON="$OUT"
run --json
eq "설치 성공" "$RC" "0"
INSTALL_JSON="$OUT"
eq "미리보기와 실제 설치가 같은 목록 (changes)" "$(printf '%s' "$PLAN_JSON" | python3 -I -c "import json,sys; d=json.load(sys.stdin); print(json.dumps([d['changes'], d['counts']]))")" "$(printf '%s' "$INSTALL_JSON" | python3 -I -c "import json,sys; d=json.load(sys.stdin); print(json.dumps([d['changes'], d['counts']]))")"
eq "설치 뒤 백업 정보가 JSON 에 있다" "$(J "d['backup'] is not None and d['backup']['id'][:2]")" "20"
run --plan --json
eq "설치 뒤 미리보기는 바뀔 것이 없다" "$(J "d['same']")" "True"

UI="$CL/agents/harness-builder-ui.md"
yes_ "값 바꾸기 — effort" grep -qx 'effort: high' "$UI"
yes_ "값 바꾸기 — model" grep -qx 'model: opus' "$UI"
yes_ "값 바꾸기 — 없던 키는 앞머리 끝에 넣는다" test "$(sed -n '2,/^---$/p' "$UI" | grep -c '^maxTurns: 20$')" = 1
eq "값 바꾸기 — 앞머리 다른 줄은 그대로" "$(sed -n 2,4p "$UI" | cut -c1-30)" "$(printf 'name: harness-builder-ui\ndescription: claude-harness 화면\n' | head -2 | cut -c1-30; sed -n 4p "$UI" | cut -c1-30)"
yes_ "덧붙이기 — 끝에 내 규칙" test "$(tail -n 2 "$UI")" = "$(printf '## 내 규칙\n- 시험 이름은 한국어로.')"
yes_ "덧붙이기 — 공통 규칙 · 가드 hook 은 그대로 붙는다" grep -q 'builder-guard.sh' "$UI"
yes_ "새 에이전트가 설치됨 (공통 규칙 · hook 포함)" grep -q 'harness:common\|모든 작업자 공통' "$CL/agents/translator.md"
yes_ "새 에이전트에도 가드 hook" grep -q 'builder-guard.sh' "$CL/agents/translator.md"
yes_ "통째 바꾸기가 적용됨" grep -q '따뜻한 게임 UI' "$CL/agents/harness-designer.md"
eq "복사 설치 표시" "$(sed -n 1p "$CL/harness/.install-mode")" "copy"
eq "표시에 원본 위치" "$(sed -n 2p "$CL/harness/.install-mode")" "$BOX/repo"
no_ "하네스는 링크가 아니다" test -L "$CL/harness"
yes_ "복사본에도 값 바꾸기가 들어 있다" grep -qx 'effort: high' "$CL/harness/agents/harness-builder-ui.md"
yes_ "복사본에 내 스킬" test -f "$CL/harness/skills/mine/SKILL.md"
yes_ "스킬 값 바꾸기 (복사본)" grep -qx 'effort: low' "$CL/harness/skills/web-lite/SKILL.md"
eq "스킬은 복사본으로 링크" "$(readlink "$CL/skills/web-lite")" "$CL/harness/skills/web-lite"
eq "스킬 링크 — 내 스킬" "$(readlink "$CL/skills/mine")" "$CL/harness/skills/mine"
yes_ "설정은 custom 에서 복사본으로 (스킬이 읽는 자리)" test "$(cat "$CL/harness/config.local.json")" = '{"language":"ko","mine":true}'
no_ "앱 전용 파일(agent-cats.json)은 설치하지 않는다" test -e "$CL/harness/agent-cats.json"
no_ ".git 은 복사하지 않는다" test -e "$CL/harness/.git"
eq "상태 파일 — 새로 만든 것만" "$(cat "$CL/.harness-installed")" "$(printf 'agent translator.md\nskill mine')"
yes_ "원본 저장소는 그대로 (설정 파일을 만들지 않았다)" test ! -e "$BOX/repo/config.local.json"
yes_ "원본 저장소의 에이전트도 그대로" diff <(cat "$BOX/legacy/agents/harness-builder-ui.md") "$BOX/repo/agents/harness-builder-ui.md"

head_ "2-2. 내 수정에서 에이전트 · 스킬을 지우면 설치에서도 빠진다"
rm "$HH/custom/agents/translator.md"; rm -r "$HH/custom/skills/mine"
run --plan --json
eq "지워질 것 — 에이전트 · 스킬 · 복사본" "$(J "sorted(c['path'] for c in d['changes'] if c['action']=='remove' and not c['path'].startswith('harness/skills/web') )")" "['.harness-installed', 'agents/translator.md', 'harness/agents/translator.md', 'harness/skills/mine/SKILL.md', 'skills/mine']"
run
yes_ "새 에이전트가 지워짐" test ! -e "$CL/agents/translator.md"
yes_ "새 스킬 링크가 지워짐" test ! -e "$CL/skills/mine" -a ! -L "$CL/skills/mine"
yes_ "상태 파일이 지워짐" test ! -e "$CL/.harness-installed"
yes_ "하네스 에이전트는 남음" test -f "$CL/agents/harness-helper.md"

# ═══════════════════════════════════════
head_ "3. 원본 바뀜 (통째로 바꾼 파일)"
new_box origin
sed 's/^description: .*/description: 내 디자이너/' "$BOX/repo/agents/harness-designer.md" > /dev/null
mkdir -p "$HH/custom/agents"
cp "$BOX/repo/agents/harness-designer.md" "$HH/custom/agents/harness-designer.md"
echo "# 내 수정" >> "$HH/custom/agents/harness-designer.md"
run --origin-hash agents/harness-designer.md; H1="$OUT"
printf '%s\n' "$H1" > "$HH/custom/agents/harness-designer.md.origin"
run --plan --json
eq "원본이 그대로면 바뀜 아님" "$(J "[i['originChanged'] for i in d['custom']['items'] if i['kind']=='replace']")" "[False]"
eq "원본 바뀜 목록이 비어 있다" "$(J "d['originChanged']")" "[]"
echo "원본에서 한 줄 고침" >> "$BOX/repo/agents/harness-designer.md"
run --plan --json
eq "원본이 바뀌면 바뀜" "$(J "[i['originChanged'] for i in d['custom']['items'] if i['kind']=='replace']")" "[True]"
eq "원본 바뀜 목록에 적어 둔 해시 · 지금 해시" "$(J "[(o['path'], o['recorded']==\"$H1\", o['current']!=o['recorded']) for o in d['originChanged']]")" "[('agents/harness-designer.md', True, True)]"
run --plan
yes_ "사람용 미리보기에도 원본 바뀜이 나온다" grep -q '원본 바뀜: agents/harness-designer.md' <<<"$OUT"
run
eq "원본이 바뀌어도 설치는 내 것으로 끝난다 (종료 코드)" "$RC" "0"
yes_ "내 것을 그대로 쓴다" grep -q '^# 내 수정$' "$CL/agents/harness-designer.md"
yes_ "설치 출력에 원본 바뀜 안내" grep -q '원본 바뀜: agents/harness-designer.md' <<<"$OUT"
run --origin-hash agents/harness-designer.md; H2="$OUT"
no_ "새 원본 해시는 다르다" test "$H1" = "$H2"
printf '%s\n' "$H2" > "$HH/custom/agents/harness-designer.md.origin"   # 내 것 유지 — 해시를 새 원본으로
run --plan --json
eq "해시를 새로 적으면 바뀜이 풀린다" "$(J "d['originChanged']")" "[]"
rm "$HH/custom/agents/harness-designer.md.origin"
run --plan --json
eq "해시가 없으면 알 수 없음(null)" "$(J "[i['originChanged'] for i in d['custom']['items'] if i['kind']=='replace']")" "[None]"
eq "해시가 없으면 알림" "$(J "[w['reason'] for w in d['warnings']]")" "['noOriginHash']"
printf '%s\n' "$H1" > "$HH/custom/agents/harness-designer.md.origin"
rm "$BOX/repo/agents/harness-designer.md"; cp "$BOX/legacy/agents/harness-tester.md" "$BOX/repo/agents/harness-tester.md"
run --plan --json
eq "원본에서 사라진 파일을 통째로 바꿔 둔 경우 — 바뀜 + 알림" "$(J "(d['originChanged'][0]['current'], [w['reason'] for w in d['warnings']])")" "(None, ['originGone'])"
# CRLF 로 저장된 내 파일도 LF 로 맞춰 설치된다
new_box crlf
custom agents/harness-helper.md "$(printf -- '---\r\nname: harness-helper\r\ndescription: 내 도우미\r\nmodel: haiku\r\n---\r\n\r\n내 도우미다.\r\n')"
run
eq "CRLF 로 저장된 통째 바꾸기도 설치된다" "$RC" "0"
no_ "설치된 에이전트에 CR 이 없다" grep -q $'\r' "$CL/agents/harness-helper.md"

# ═══════════════════════════════════════
head_ "4. 백업 · 되돌리기 (하네스와 상관없는 파일은 읽지도 백업하지도 않는다)"
new_box backup
CLAUDE_CONFIG_DIR="$CL" bash "$BOX/legacy/install.sh" >/dev/null 2>&1   # 지금 쓰는 사람의 상태: 링크 설치
mkdir -p "$CL/projects/p1" "$CL/plugins" "$CL/skills/my-own" "$CL/session-env"
echo '{"secret":"x"}' > "$CL/.credentials.json"; echo "기록" > "$CL/history.jsonl"; echo "{}" > "$CL/settings.json"
echo "세션" > "$CL/projects/p1/s.jsonl"; echo "내 스킬" > "$CL/skills/my-own/SKILL.md"; echo "내 에이전트" > "$CL/agents/my-own.md"
echo "플러그인" > "$CL/plugins/x"
snap "$CL" > "$BOX/before.snap"; snap "$BOX/repo" > "$BOX/repo.before.snap"
chmod 000 "$CL/.credentials.json" "$CL/history.jsonl" "$CL/projects/p1/s.jsonl"; chmod 000 "$CL/projects"   # 읽으면 실패하게
custom agents/harness-builder-ui.values.yml $'effort: high\n'
custom agents/translator.md "$(agent_text translator 번역 번역가)"$'\n'
run --json
chmod 755 "$CL/projects"; chmod 644 "$CL/.credentials.json" "$CL/history.jsonl" "$CL/projects/p1/s.jsonl"
eq "인증 · 기록 파일을 못 읽는 상태에서도 설치된다 (읽지 않는다)" "$RC" "0"
BK="$(J "d['backup']['id']")"
yes_ "백업 폴더가 생겼다" test -f "$HH/backups/$BK/manifest.txt"
BKFILES="$(cd "$HH/backups/$BK/files" && find . -type f | sed 's#^\./##' | sort | tr '\n' ' ')"
eq "백업한 파일은 하네스가 다루는 경로뿐" "$(printf '%s' "$BKFILES" | tr ' ' '\n' | grep -vcE '^(agents/harness-[a-z-]+\.md|harness/.*)$')" "0"
no_ "백업에 인증 · 기록 · 설정이 없다" grep -qE 'credentials|history|settings|projects|plugins|my-own' <(find "$HH/backups/$BK" -print)
no_ "목록에도 없다" grep -qE 'credentials|history|settings|projects|plugins|my-own' "$HH/backups/$BK/manifest.txt"
eq "하네스와 상관없는 파일은 그대로 (내용)" "$(cat "$CL/.credentials.json" "$CL/history.jsonl" "$CL/settings.json" "$CL/projects/p1/s.jsonl" "$CL/skills/my-own/SKILL.md" "$CL/agents/my-own.md" "$CL/plugins/x" | tr '\n' ' ')" "{\"secret\":\"x\"} 기록 {} 세션 내 스킬 내 에이전트 플러그인 "
run --backups --json
eq "백업 목록" "$(J "[(b['id']==\"$BK\", b['command'], b['readable'], b['added']>0, b['changed']>0) for b in d['backups']]")" "[(True, 'install', True, True, True)]"
run --backups
yes_ "사람용 백업 목록" grep -q "$BK" <<<"$OUT"
run --restore "$BK" --plan --json
eq "되돌리기 미리보기는 아무것도 바꾸지 않는다" "$(J "d['dryRun']")" "True"
snap "$CL" > "$BOX/mid.snap"
run --restore "$BK" --plan >/dev/null; snap "$CL" > "$BOX/mid2.snap"
eq "미리보기 뒤 상태가 같다" "$(diff "$BOX/mid.snap" "$BOX/mid2.snap" | wc -l | tr -d ' ')" "0"
run --restore "$BK" --json
eq "되돌리기 성공" "$RC" "0"
snap "$CL" > "$BOX/after.snap"
eq "되돌린 뒤 설치 전과 똑같다 (이름 · 내용 · 링크)" "$(diff "$BOX/before.snap" "$BOX/after.snap" | wc -l | tr -d ' ')" "0"
run --restore "$BK" --plan --json
eq "되돌린 뒤 다시 되돌릴 것이 없다" "$(J "[d['same'], d['counts']['same']>0]")" "[True, True]"
run --restore "$BK"; snap "$CL" > "$BOX/after2.snap"
eq "두 번 되돌려도 같다" "$(diff "$BOX/before.snap" "$BOX/after2.snap" | wc -l | tr -d ' ')" "0"
snap "$BOX/repo" > "$BOX/repo.after.snap"
eq "되돌리기가 링크를 따라가 원본 저장소를 건드리지 않는다" "$(diff "$BOX/repo.before.snap" "$BOX/repo.after.snap" | wc -l | tr -d ' ')" "0"

head_ "4-2. 두 번 설치해도 같다 · 링크 ↔ 복사 오가기"
run; snap "$CL" > "$BOX/i1.snap"
run; snap "$CL" > "$BOX/i2.snap"
eq "두 번 설치해도 같다" "$(diff "$BOX/i1.snap" "$BOX/i2.snap" | wc -l | tr -d ' ')" "0"
eq "같은 일이면 백업을 더 만들지 않는다" "$(ls "$HH/backups" | wc -l | tr -d ' ')" "2"
rm -r "$HH/custom"                                       # 내 수정을 모두 지우면 다시 링크로
run --json
eq "내 수정이 없어지면 링크로 돌아간다" "$(J "d['mode']")" "link"
eq "하네스가 다시 링크" "$(readlink "$CL/harness")" "$BOX/repo"
no_ "복사본 폴더가 남지 않는다" test -f "$CL/harness/.install-mode"
no_ "내 에이전트도 지워진다" test -e "$CL/agents/translator.md"
BK2="$(J "d['backup']['id']")"
run --restore "$BK2"; eq "복사 → 링크 되돌리기" "$RC" "0"
yes_ "복사본이 돌아왔다" test -f "$CL/harness/.install-mode"
yes_ "내 에이전트가 돌아왔다" test -f "$CL/agents/translator.md"
run --restore "$BK" ; snap "$CL" > "$BOX/after3.snap"
eq "첫 백업으로 되돌리면 처음 상태" "$(diff "$BOX/before.snap" "$BOX/after3.snap" | wc -l | tr -d ' ')" "0"

head_ "4-3. 처음 설치한 것을 되돌리면 ~/.claude 가 비어 있다 (폴더도 새로 만든 것은 지운다)"
new_box fresh
custom agents/translator.md "$(agent_text translator 번역 번역가)"$'\n'
run --json; FB="$(J "d['backup']['id']")"
run --restore "$FB" --json
eq "처음 설치 되돌리기 성공" "$RC" "0"
eq "하네스 파일 · 폴더가 하나도 남지 않는다" "$(ls -A "$CL" | tr '\n' ' ')" ""
new_box fresh2
run --json; FB="$(J "d['backup']['id']")"
run --restore "$FB" --json
eq "링크 설치를 처음으로 되돌려도 비어 있다" "$(ls -A "$CL" | tr '\n' ' ')" ""

# ═══════════════════════════════════════
head_ "5. 중간에 실패하면 — 되돌리고 알린다"
if [ "$(id -u)" = 0 ]; then
  echo "  건너뜀: root 로 돌려서 쓰기 금지를 시험할 수 없다"
else
  new_box fail
  CLAUDE_CONFIG_DIR="$CL" bash "$BOX/legacy/install.sh" >/dev/null 2>&1
  snap "$CL" > "$BOX/before.snap"
  echo "고침" >> "$BOX/repo/agents/harness-helper.md"
  echo "고침" >> "$BOX/repo/agents/harness-tester.md"
  chmod 555 "$CL/agents"           # 에이전트를 새로 쓰는 단계에서 실패
  run --json
  chmod 755 "$CL/agents"
  eq "실패하면 종료 코드 3" "$RC" "3"
  eq "오류 코드" "$(J "d['error']['code']")" "applyFailed"
  eq "되돌렸다고 알린다" "$(J "d['rolledBack']")" "True"
  eq "백업 번호를 알려 준다" "$(J "d['backup'] is not None")" "True"
  snap "$CL" > "$BOX/after.snap"
  eq "실패 뒤에도 설치 전과 똑같다" "$(diff "$BOX/before.snap" "$BOX/after.snap" | wc -l | tr -d ' ')" "0"
  no_ "임시 파일이 남지 않는다" bash -c "find '$CL' -name '*.harness-tmp.*' | grep -q ."
  no_ "잠금이 남지 않는다" test -e "$CL/.harness-install.lock"
  run; eq "문제를 고치면 다시 설치된다" "$RC" "0"
fi

# ═══════════════════════════════════════
head_ "6. 내 수정 폴더가 잘못됐으면 아무것도 쓰지 않고 멈춘다"
bad_case() {  # bad_case <이름> <코드>  (내 수정을 만든 뒤 호출)
  run --json
  eq "$1 — 종료 코드 2" "$RC" "2"
  eq "$1 — 사유 $2" "$(J "sorted(set(p['reason'] for p in d['problems']))")" "['$2']"
  no_ "$1 — ~/.claude 를 만들지 않았다" test -e "$CL"
  no_ "$1 — 백업도 만들지 않았다" test -e "$HH/backups"
}
new_box bad1; mkdir -p "$HH/custom/agents"; ln -s /etc/passwd "$HH/custom/agents/evil.md"; bad_case "링크" symlinkInCustom
new_box bad2; custom agents/harness-helper.values.yml $'effort high\n'; bad_case "값 모양" badValues
new_box bad3; custom agents/harness-helper.values.yml $'name: other\n'; bad_case "name 바꾸기" badValues
new_box bad4; custom agents/nothing.values.yml $'effort: high\n'; bad_case "없는 원본" targetMissing
new_box bad5; custom agents/_common/rules.md 'x'; bad_case "공통 규칙 바꾸기" unsupported
new_box bad6; custom agents/sub/x.md 'x'; bad_case "agents 하위 폴더" unsupported
new_box bad7; custom skills/loose.md 'x'; bad_case "skills 바로 아래 파일" unsupported
new_box bad8; custom agents/harness-helper.md "$(cat "$BOX/repo/agents/harness-helper.md")"; custom agents/harness-helper.md.origin 'xyz'; bad_case "원본 해시 모양" badOrigin
new_box bad9; custom agents/oops.md $'---\nname: other\n---\n'; bad_case "새 에이전트 틀(name)" invalidAgent
new_box bad10; custom agents/oops.md $'---\nname: oops\nhooks:\n  x: y\n---\n'; bad_case "새 에이전트 틀(hooks)" invalidAgent
new_box bad11; custom agents/harness-helper.values.yml $'tools: A\n'; printf -- '---\nname: harness-helper\ntools:\n  - A\n  - B\n---\n본문\n' > "$BOX/repo/agents/harness-helper.md"; bad_case "여러 줄 값" badValues
new_box bad12; custom agents/harness-helper.values.yml $'effort: high\neffort: low\n'; bad_case "키 중복" badValues
new_box bad13; custom agents $'x'; bad_case "agents 가 파일" unsupported
run --json; eq "문제 설명(detail)이 있다" "$(J "all(p['detail'] for p in d['problems'])")" "True"

# ═══════════════════════════════════════
head_ "7. 동시에 두 번 · 낯선 것이 있을 때"
new_box lock
mkdir -p "$CL/.harness-install.lock"; sleep 30 & SLEEPER=$!; echo "$SLEEPER" > "$CL/.harness-install.lock/pid"
run --json
eq "다른 설치가 돌고 있으면 종료 코드 2" "$RC" "2"
eq "오류 코드 busy" "$(J "d['error']['code']")" "busy"
no_ "아무것도 설치하지 않았다" test -e "$CL/agents"
kill "$SLEEPER" 2>/dev/null; wait "$SLEEPER" 2>/dev/null
run --json; eq "돌던 설치가 죽었으면(남은 잠금) 이어서 설치" "$RC" "0"
no_ "끝나면 잠금을 치운다" test -e "$CL/.harness-install.lock"
run --plan --json; eq "미리보기는 잠금과 상관없이 돈다" "$RC" "0"

new_box foreign
mkdir -p "$CL/harness" "$CL/skills/web-full" "$CL/agents"; echo "내 것" > "$CL/harness/mine.txt"; echo "내 스킬" > "$CL/skills/web-full/SKILL.md"
run --json
eq "낯선 폴더가 있어도 (링크 설치) 나머지는 설치된다" "$RC" "0"
eq "건너뛴 것 — 하네스 · 스킬" "$(J "sorted((c['path'],c['reason']) for c in d['changes'] if c['action']=='skip')")" "[('harness', 'notOurs'), ('skills/web-full', 'notOurs')]"
eq "낯선 파일은 그대로" "$(cat "$CL/harness/mine.txt" "$CL/skills/web-full/SKILL.md" | tr '\n' ' ')" "내 것 내 스킬 "
yes_ "다른 스킬은 연결됨" test -L "$CL/skills/web-lite"
run; yes_ "사람용 출력에 건너뜀" grep -q '건너뜀: .*harness — 링크가 아닌 파일이 이미 있음' <<<"$OUT"
custom config.local.json '{}'
run --json
eq "복사 설치인데 하네스 자리에 낯선 폴더가 있으면 멈춘다" "$RC" "2"
eq "사유 harnessNotOurs" "$(J "[p['reason'] for p in d['problems']]")" "['harnessNotOurs']"

new_box collide
mkdir -p "$CL/agents"; echo "내 번역가" > "$CL/agents/translator.md"
custom agents/translator.md "$(agent_text translator 번역 번역가)"$'\n'
run --json
eq "내 수정의 새 에이전트가 내 파일과 이름이 같으면 건너뛴다" "$(J "[(c['path'],c['reason']) for c in d['changes'] if c['action']=='skip']")" "[('agents/translator.md', 'notOurs')]"
eq "내 파일은 그대로" "$(cat "$CL/agents/translator.md")" "내 번역가"

new_box tamper
CLAUDE_CONFIG_DIR="$CL" bash "$BOX/legacy/install.sh" >/dev/null 2>&1
echo "내 것" > "$CL/mine.txt"; mkdir -p "$CL/projects"; echo "기록" > "$CL/projects/a.jsonl"; touch "$CL/.install-mode"
printf 'skill ..\nagent ..md\nskill ../x\nskill /etc\n' > "$CL/.harness-installed"   # 고쳐 둔 상태 파일 — 읽지 않는다
run --json
eq "고쳐 둔 상태 파일이 있어도 설치된다" "$RC" "0"
eq "상태 파일의 이상한 이름으로 아무것도 지우지 않는다" "$(cat "$CL/mine.txt" "$CL/projects/a.jsonl" | tr '\n' ' ')" "내 것 기록 "
yes_ "~/.claude 안의 다른 것도 그대로" test -e "$CL/.install-mode" -a -d "$CL/skills" -a -d "$CL/agents"

# ═══════════════════════════════════════
head_ "8. 지우기 (uninstall)"
new_box uninstall
CLAUDE_CONFIG_DIR="$CL" bash "$BOX/legacy/install.sh" >/dev/null 2>&1
mkdir -p "$CL/skills/my-own"; echo "내 스킬" > "$CL/skills/my-own/SKILL.md"; echo "{}" > "$CL/settings.json"
snap "$CL" > "$BOX/before.snap"
bash "$BOX/repo/uninstall.sh" --help >/dev/null 2>&1
CLAUDE_CONFIG_DIR="$CL" CLAUDE_HARNESS_HOME="$HH" bash "$BOX/repo/uninstall.sh" --plan --json > "$BOX/un.plan"; OUT="$(cat "$BOX/un.plan")"
eq "지우기 미리보기 — 지울 것" "$(J "sorted(c['path'] for c in d['changes'] if c['action']=='remove')")" "['agents/harness-builder-system.md', 'agents/harness-builder-ui.md', 'agents/harness-designer.md', 'agents/harness-helper.md', 'agents/harness-reviewer.md', 'agents/harness-tester.md', 'harness', 'skills/desktop-app', 'skills/harness-resume', 'skills/harness-setup', 'skills/web-full', 'skills/web-lite']"
snap "$CL" > "$BOX/mid.snap"; eq "미리보기는 아무것도 지우지 않는다" "$(diff "$BOX/before.snap" "$BOX/mid.snap" | wc -l | tr -d ' ')" "0"
OUT="$(CLAUDE_CONFIG_DIR="$CL" CLAUDE_HARNESS_HOME="$HH" bash "$BOX/repo/uninstall.sh" 2>&1)"; RC=$?
eq "지우기 성공" "$RC" "0"
yes_ "사람용 출력 (예전과 같은 줄)" grep -q "  지움: $CL/skills/web-full" <<<"$OUT"
yes_ "끝 줄" test "$(printf '%s' "$OUT" | tail -n 1)" = "완료."
no_ "하네스 링크가 지워짐" test -L "$CL/harness"
no_ "에이전트가 지워짐" test -e "$CL/agents/harness-helper.md"
eq "내 스킬 · 설정은 그대로" "$(cat "$CL/skills/my-own/SKILL.md" "$CL/settings.json" | tr '\n' ' ')" "내 스킬 {} "
yes_ "저장소는 그대로" test -f "$BOX/repo/agents/harness-helper.md"
run --backups --json; UBK="$(J "d['backups'][0]['id']")"; eq "지우기도 백업 (명령 이름)" "$(J "d['backups'][0]['command']")" "uninstall"
run --restore "$UBK"; snap "$CL" > "$BOX/after.snap"
eq "지운 것도 되돌릴 수 있다" "$(diff "$BOX/before.snap" "$BOX/after.snap" | wc -l | tr -d ' ')" "0"
# 복사 설치도 지운다
new_box uninstall2; custom agents/translator.md "$(agent_text translator 번역 번역가)"$'\n'; custom skills/mine/SKILL.md $'---\nname: mine\ndescription: x\n---\n'
run >/dev/null
OUT="$(CLAUDE_CONFIG_DIR="$CL" CLAUDE_HARNESS_HOME="$HH" bash "$BOX/repo/install.sh" --uninstall 2>&1)"
no_ "복사본 폴더도 지워진다" test -e "$CL/harness"
no_ "내 에이전트 · 스킬도 지워진다" bash -c "test -e '$CL/agents/translator.md' || test -L '$CL/skills/mine'"
no_ "상태 파일도 지워진다" test -e "$CL/.harness-installed"
eq "~/.claude 안에 남은 것이 없다 (잠금 · 임시 파일 포함)" "$(ls -A "$CL" | tr '\n' ' ')" "agents skills "

# ═══════════════════════════════════════
head_ "9. 개발자 모드 · 하네스 폴더 위치"
new_box dev
mkdir -p "$BOX/other-repo" "$CL"; ln -s "$BOX/other-repo" "$CL/harness"
run --json
eq "지금 연결된 원본을 알려 준다" "$(J "d['existingSource']")" "$BOX/other-repo"
eq "개발자 모드 (하네스 폴더의 repo 가 아님)" "$(J "d['developerMode']")" "True"
eq "다른 원본으로 다시 연결한다 (예전처럼)" "$(readlink "$CL/harness")" "$BOX/repo"
mkdir -p "$HH"; ln -s "$BOX/repo" "$HH/repo"
run --json
eq "하네스 폴더의 repo 에서 돌리면 개발자 모드가 아니다" "$(J "d['developerMode']")" "False"
new_box dev2
custom config.local.json '{}'; run >/dev/null
run --json; eq "복사 설치의 원본 위치도 알아본다" "$(J "d['existingSource']")" "$BOX/repo"
# 기본 위치: HOME 아래
new_box home
mkdir -p "$BOX/h2"
OUT="$(HOME="$BOX/h2" CLAUDE_CONFIG_DIR= CLAUDE_HARNESS_HOME= bash "$BOX/repo/install.sh" --json 2>/dev/null)"
eq "기본 위치 — ~/.claude" "$(J "d['claudeDir']")" "$BOX/h2/.claude"
eq "기본 위치 — ~/.claude-harness" "$(J "d['harnessHome']")" "$BOX/h2/.claude-harness"
yes_ "기본 위치에 설치됨" test -f "$BOX/h2/.claude/agents/harness-helper.md"
yes_ "백업은 하네스 폴더 아래" test -d "$BOX/h2/.claude-harness/backups"

# ═══════════════════════════════════════
head_ "10. 링크를 못 만드는 환경 (복사로) ↔ 링크"
new_box nolink
export CLAUDE_HARNESS_NO_SYMLINK=1
run --json
eq "링크 없이도 설치된다" "$RC" "0"
eq "방식은 복사" "$(J "d['mode']")" "copy"
no_ "스킬은 링크가 아니라 복사" test -L "$CL/skills/web-full"
yes_ "스킬 복사본에 표시 파일" test -f "$CL/skills/web-full/.install-mode"
yes_ "스킬 복사본" test -f "$CL/skills/web-full/SKILL.md"
run --plan --json; eq "두 번째는 바뀔 것이 없다" "$(J "d['same']")" "True"
snap "$CL" > "$BOX/c1.snap"
unset CLAUDE_HARNESS_NO_SYMLINK
run --json
eq "링크가 되는 환경으로 바꾸면 링크로 바뀐다" "$(J "d['mode']")" "link"
eq "스킬이 링크가 됨" "$(readlink "$CL/skills/web-full")" "$BOX/repo/skills/web-full"
BK3="$(J "d['backup']['id']")"
run --restore "$BK3"; snap "$CL" > "$BOX/c2.snap"
eq "복사 → 링크 되돌리기가 원래대로" "$(diff "$BOX/c1.snap" "$BOX/c2.snap" | wc -l | tr -d ' ')" "0"

# ═══════════════════════════════════════
head_ "11. 되돌리기 입력 검사 · 잘못된 사용"
new_box args
run --json; BKA="$(J "d['backup']['id']")"
run --restore '../x' --json; eq "백업 번호에 경로를 못 쓴다" "$RC" "2"
run --restore 2020-01-01_000000 --json; eq "없는 백업" "$(J "d['error']['code']")" "noBackup"
run --json --restore; eq "번호 없이 --restore" "$(J "d['error']['code']")" "badArgs"
run --bogus --json; eq "알 수 없는 옵션" "$(J "[d['error']['code'], d['exitCode']]")" "['badArgs', 2]"
run --check --uninstall --json; eq "옵션이 겹치면 오류" "$(J "d['error']['code']")" "badArgs"
run --origin-hash ../x --json; eq "원본 해시 — 경로 밖" "$(J "d['error']['code']")" "badArgs"
run --origin-hash nothing.md --json; eq "원본 해시 — 없는 파일" "$(J "d['error']['code']")" "notFound"
run --origin-hash agents/harness-helper.md --json; eq "원본 해시 JSON" "$(J "len(d['originHash']['sha256'])")" "64"
# 목록을 고쳐 둔 경우
cp "$HH/backups/$BKA/manifest.txt" "$BOX/manifest.keep"
printf 'add\tfile\t../../outside.txt\t\n' >> "$HH/backups/$BKA/manifest.txt"; echo "건드리면 안 됨" > "$TMP/outside.txt"   # $CL/../.. = $TMP
run --restore "$BKA" --json
eq "목록에 밖으로 나가는 경로가 있으면 거부" "$(J "d['error']['code']")" "badBackup"
eq "거부한 되돌리기는 backup 을 알리지 않는다" "$(J "d['backup']")" "None"
yes_ "밖의 파일은 그대로" test -f "$TMP/outside.txt"
yes_ "설치된 것도 그대로" test -f "$CL/agents/harness-helper.md"
cp "$BOX/manifest.keep" "$HH/backups/$BKA/manifest.txt"
printf 'add\tfile\tsettings.json\t\n' >> "$HH/backups/$BKA/manifest.txt"
run --restore "$BKA" --json; eq "하네스가 다루지 않는 자리(settings.json)도 거부" "$(J "d['error']['code']")" "badBackup"
cp "$BOX/manifest.keep" "$HH/backups/$BKA/manifest.txt"
sed -i.bak "s#^\# claudeDir: .*#\# claudeDir: /somewhere/else#" "$HH/backups/$BKA/manifest.txt"
run --restore "$BKA" --json; eq "다른 대상의 백업은 거부" "$(J "d['error']['code']")" "wrongTarget"

# ═══════════════════════════════════════
head_ "12. JSON 모양 — 명령마다 같은 키 · 같은 순서"
new_box shape
custom agents/translator.md "$(agent_text translator 번역 번역가)"$'\n'
KEYS_REF=""
for args in "--plan" "--check" "--backups" "--uninstall --plan" "--origin-hash agents/harness-helper.md" "--bogus"; do
  run $args --json
  K="$(J "list(d.keys())")"
  [ -n "$KEYS_REF" ] || KEYS_REF="$K"
  eq "키가 같다: $args" "$K" "$KEYS_REF"
done
run --json; run --restore "$(J "d['backups'][0]['id']" 2>/dev/null || true)" --json
run --json
BKS="$(ls "$HH/backups" | tail -1)"
run --restore "$BKS" --plan --json; eq "키가 같다: --restore --plan" "$(J "list(d.keys())")" "$KEYS_REF"
eq "계약 번호" "$(J "d['contract']")" "1"
eq "표준 출력은 JSON 한 줄뿐" "$(OUT_LINES="$(CLAUDE_CONFIG_DIR="$CL" CLAUDE_HARNESS_HOME="$HH" bash "$BOX/repo/install.sh" --plan --json 2>/dev/null | wc -l | tr -d ' ')"; echo "$OUT_LINES")" "1"

# ═══════════════════════════════════════
printf '\n통과 %s · 실패 %s\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ]
