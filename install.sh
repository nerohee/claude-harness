#!/usr/bin/env bash
# claude-harness 설치 — 이 저장소(+ 내 수정)를 Claude Code 사용자 설정(~/.claude)에 연결한다.
#   ~/.claude/harness           → 이 저장소 (내 수정이 없으면 링크. 있으면 원본 + 내 수정을 합친 복사)
#   ~/.claude/skills/<스킬>      → skills/<스킬> (심볼릭 링크)
#   ~/.claude/agents/<에이전트>  ← agents/*.md + agents/_common/ (합쳐서 복사 — 에이전트 링크는 문서로 보장되지 않아서)
# 다시 돌려도 된다. 에이전트 · 스킬을 고친 뒤에는 다시 돌린다.
#
#   bash install.sh                       설치 (덮어쓰거나 지우기 전에 백업)
#   bash install.sh --plan                설치하지 않고 계획만 — 새로 생김 · 바뀜 · 지워짐 · 건너뜀 · 원본 바뀜 (아무것도 쓰지 않는다)
#   bash install.sh --check               설치하지 않고, 설치된 작업자가 저장소(+ 내 수정)와 같은지만 본다 (다르면 종료 코드 1)
#   bash install.sh --backups             백업 목록
#   bash install.sh --restore <번호>      고른 백업으로 되돌린다 (--plan 과 같이 쓰면 미리보기)
#   bash install.sh --uninstall           하네스가 만든 것을 지운다 (uninstall.sh 와 같다. --plan 으로 미리보기)
#   bash install.sh --origin-hash <경로>  원본 파일의 해시 (내 수정 "통째 바꾸기" 가 남기는 값)
#   --json                                사람용 출력 대신 JSON 한 개를 내보낸다 (모양: shared/app-contract.md)
#
# 위치는 환경 변수로 바꾼다 (시험용으로도 쓴다):
#   CLAUDE_CONFIG_DIR     ~/.claude (기본)
#   CLAUDE_HARNESS_HOME   ~/.claude-harness (기본) — repo/ · custom/ · backups/
# 종료 코드: 0 성공 · 1 --check 에서 다름 · 2 잘못된 사용 · 내 수정 폴더 오류 · 다른 설치 진행 중 · 3 실행 중 실패 (되돌림 시도)
set -u
export LC_ALL=C

CONTRACT=1
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RETIRED="harness-builder harness-builder-deep"  # 이름이 바뀌어 저장소에서 빠진 예전 작업자
MARK='<!-- harness:common -->'
STATE_FILE=".harness-installed"  # 내 수정으로 새로 만든 에이전트 · 스킬 이름 (나중에 지워졌을 때 알아보려고)
TAB=$'\t'

# ── 옵션 ──
CMD=install
JSON=0
DRY=0
RESTORE_ID=""
HASH_PATH=""
ARGERR=""
set_cmd() {
  if [ "$CMD" != install ] && [ "$CMD" != "$1" ]; then ARGERR="옵션이 겹칩니다: $CMD 와 $1"; fi
  CMD="$1"
}
while [ $# -gt 0 ]; do
  case "$1" in
    --plan) DRY=1 ;;
    --json) JSON=1 ;;
    --check) set_cmd check ;;
    --backups) set_cmd backups ;;
    --uninstall) set_cmd uninstall ;;
    --restore)
      set_cmd restore
      if [ $# -lt 2 ]; then ARGERR="--restore 에는 백업 번호가 필요합니다 (--backups 로 본다)"; else RESTORE_ID="$2"; shift; fi ;;
    --origin-hash)
      set_cmd originHash
      if [ $# -lt 2 ]; then ARGERR="--origin-hash 에는 저장소 안 경로가 필요합니다"; else HASH_PATH="$2"; shift; fi ;;
    -h|--help) sed -n '2,/^set -u$/{/^#/p}' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) ARGERR="알 수 없는 옵션: $1" ;;
  esac
  shift
done

# ── 경로 ──
abs_path() { case "$1" in /*) printf '%s' "$1" ;; *) printf '%s/%s' "$PWD" "$1" ;; esac; }
trim_slash() { local p="$1"; while [ "${#p}" -gt 1 ] && [ "${p%/}" != "$p" ]; do p="${p%/}"; done; printf '%s' "$p"; }
real_path() { (cd "$1" 2>/dev/null && pwd -P) || printf '%s' "$1"; }

CLAUDE_DIR="$(trim_slash "$(abs_path "${CLAUDE_CONFIG_DIR:-${HOME:-/nonexistent}/.claude}")")"
HARNESS_HOME="$(trim_slash "$(abs_path "${CLAUDE_HARNESS_HOME:-${HOME:-/nonexistent}/.claude-harness}")")"
CUSTOM="$HARNESS_HOME/custom"
BACKUPS="$HARNESS_HOME/backups"
LOCKDIR="$CLAUDE_DIR/.harness-install.lock"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/claude-harness.XXXXXX")" || { echo "임시 폴더를 만들 수 없습니다" >&2; exit 3; }
LOCK_HELD=0
BK_ID=""
cleanup() {
  [ "$LOCK_HELD" = 1 ] && rm -rf "$LOCKDIR"
  rm -rf "$WORK"
}
trap cleanup EXIT
trap '[ -n "$BK_ID" ] && echo "중단됨 — 백업 $BK_ID 로 되돌릴 수 있습니다 (bash install.sh --restore $BK_ID)" >&2; exit 130' INT TERM

ITEMS="$WORK/items.tsv"        # 내 수정 — 경로 <TAB> 종류 <TAB> 원본 바뀜(true|false|-)
ORIGINS="$WORK/origins.tsv"    # 원본 바뀜 — 경로 <TAB> 적어 둔 해시 <TAB> 지금 해시(-)
PROBLEMS="$WORK/problems.tsv"  # 막는 문제 — 경로 <TAB> 코드 <TAB> 설명
WARNINGS="$WORK/warnings.tsv"  # 알림 — 경로 <TAB> 코드 <TAB> 설명
OPS="$WORK/ops.tsv"            # 계획 — 동작 <TAB> 종류 <TAB> 경로 <TAB> 덧붙임   (동작: add · change · remove / 종류: file · link · dir)
SKIPS="$WORK/skips.tsv"        # 건너뜀 — 종류 <TAB> 경로 <TAB> 이유
: > "$ITEMS"; : > "$ORIGINS"; : > "$PROBLEMS"; : > "$WARNINGS"; : > "$OPS"; : > "$SKIPS"
mkdir -p "$WORK/files/agents"

SAME=0
MODE=""            # link · copy (이번에 설치할 방식) — 계획을 세우지 않는 명령은 비움
LINK_OK=1          # 0 이면 링크를 못 만드는 환경처럼 복사로 (시험용 CLAUDE_HARNESS_NO_SYMLINK=1)
[ "${CLAUDE_HARNESS_NO_SYMLINK:-}" = 1 ] && LINK_OK=0
SRC="$REPO"        # 내 수정을 합친 원본 폴더 (내 수정이 없으면 저장소 그대로)
CONFIG_SRC=""
ERR_CODE=""
ERR_DETAIL=""
ROLLED_BACK=""
BK_DIR=""
BK_FILES=0
MANIFEST=""
EXITCODE=0
ORIGIN_HASH=""
RESTART=false
EXISTING=""
DEVMODE=false

say() { [ "$JSON" = 1 ] || printf '%s\n' "$*"; }
problem() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$PROBLEMS"; }   # problem <경로> <코드> <설명>
warning() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$WARNINGS"; }  # warning <경로> <코드> <설명>
add_op() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "${4:-}" >> "$OPS"; }
add_skip() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$SKIPS"; }

# ── JSON ──
jesc() { local s="$1"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$TAB/\\t}"; s="${s//$'\r'/\\r}"; printf '%s' "$s"; }
jstr() { printf '"%s"' "$(jesc "$1")"; }
jstr_or_null() { if [ -n "$1" ] && [ "$1" != "-" ]; then jstr "$1"; else printf 'null'; fi; }
jbool() { if [ "$1" = true ] || [ "$1" = 1 ]; then printf 'true'; else printf 'false'; fi; }

# 변경 목록 — 경로 <TAB> 동작 <TAB> 종류 <TAB> 이유(-)  (경로 순)
changes_rows() {
  {
    awk -F'\t' '$2 != "dir" { print $3 "\t" $1 "\t" $2 "\t-" }' "$OPS"
    awk -F'\t' '{ print $2 "\tskip\t" $1 "\t" $3 }' "$SKIPS"
  } | sort
}

emit_json() {
  local ok=true same=true n_add n_change n_remove n_skip rows="$WORK/rows.tsv" dry=false
  [ -s "$PROBLEMS" ] && ok=false
  [ -n "$ERR_CODE" ] && ok=false
  [ "$DRY" = 1 ] && dry=true
  changes_rows > "$rows"
  n_add="$(awk -F'\t' '$2 == "add"' "$rows" | wc -l | tr -d ' ')"
  n_change="$(awk -F'\t' '$2 == "change"' "$rows" | wc -l | tr -d ' ')"
  n_remove="$(awk -F'\t' '$2 == "remove"' "$rows" | wc -l | tr -d ' ')"
  n_skip="$(awk -F'\t' '$2 == "skip"' "$rows" | wc -l | tr -d ' ')"
  [ $((n_add + n_change + n_remove)) -gt 0 ] && same=false

  printf '{"contract":%s,"command":%s,"ok":%s,"exitCode":%s,"dryRun":%s' "$CONTRACT" "$(jstr "$CMD")" "$ok" "$EXITCODE" "$dry"
  printf ',"claudeDir":%s,"harnessHome":%s,"repo":%s' "$(jstr "$CLAUDE_DIR")" "$(jstr "$HARNESS_HOME")" "$(jstr "$REPO")"
  printf ',"mode":%s,"developerMode":%s,"existingSource":%s,"restartNeeded":%s' "$(jstr_or_null "$MODE")" "$(jbool "$DEVMODE")" "$(jstr_or_null "$EXISTING")" "$(jbool "$RESTART")"
  printf ',"custom":{"dir":%s,"items":[' "$(jstr "$CUSTOM")"
  local first=1 path kind origin
  while IFS="$TAB" read -r path kind origin; do
    [ -n "$path" ] || continue
    [ "$first" = 1 ] || printf ','; first=0
    printf '{"path":%s,"kind":%s,"originChanged":%s}' "$(jstr "$path")" "$(jstr "$kind")" "$([ "$origin" = "-" ] && printf null || printf '%s' "$origin")"
  done < <(sort "$ITEMS")
  printf ']},"changes":['
  first=1
  local action type reason
  while IFS="$TAB" read -r path action type reason; do
    [ -n "$path" ] || continue
    [ "$first" = 1 ] || printf ','; first=0
    printf '{"path":%s,"action":%s,"type":%s,"reason":%s}' "$(jstr "$path")" "$(jstr "$action")" "$(jstr "$type")" "$(jstr_or_null "$reason")"
  done < "$rows"
  printf '],"counts":{"add":%s,"change":%s,"remove":%s,"skip":%s,"same":%s},"same":%s' "$n_add" "$n_change" "$n_remove" "$n_skip" "$SAME" "$same"
  printf ',"originChanged":['
  first=1
  local rec cur
  while IFS="$TAB" read -r path rec cur; do
    [ -n "$path" ] || continue
    [ "$first" = 1 ] || printf ','; first=0
    printf '{"path":%s,"recorded":%s,"current":%s}' "$(jstr "$path")" "$(jstr "$rec")" "$(jstr_or_null "$cur")"
  done < <(sort "$ORIGINS")
  local code detail
  printf '],"problems":['
  first=1
  while IFS="$TAB" read -r path code detail; do
    [ -n "$path" ] || continue
    [ "$first" = 1 ] || printf ','; first=0
    printf '{"path":%s,"reason":%s,"detail":%s}' "$(jstr "$path")" "$(jstr "$code")" "$(jstr "$detail")"
  done < <(sort -u "$PROBLEMS")
  printf '],"warnings":['
  first=1
  while IFS="$TAB" read -r path code detail; do
    [ -n "$path" ] || continue
    [ "$first" = 1 ] || printf ','; first=0
    printf '{"path":%s,"reason":%s,"detail":%s}' "$(jstr "$path")" "$(jstr "$code")" "$(jstr "$detail")"
  done < <(sort -u "$WARNINGS")
  printf ']'
  if [ -n "$BK_ID" ]; then
    printf ',"backup":{"id":%s,"dir":%s,"files":%s}' "$(jstr "$BK_ID")" "$(jstr "$BK_DIR")" "$BK_FILES"
  else
    printf ',"backup":null'
  fi
  printf ',"backups":['
  first=1
  local id created command added changed removed files bytes readable
  if [ -f "$WORK/backups.tsv" ]; then
    while IFS="$TAB" read -r id created command added changed removed files bytes readable; do
      [ -n "$id" ] || continue
      [ "$first" = 1 ] || printf ','; first=0
      printf '{"id":%s,"createdAt":%s,"command":%s,"added":%s,"changed":%s,"removed":%s,"files":%s,"bytes":%s,"readable":%s}' \
        "$(jstr "$id")" "$(jstr_or_null "$created")" "$(jstr_or_null "$command")" "$added" "$changed" "$removed" "$files" "$bytes" "$readable"
    done < "$WORK/backups.tsv"
  fi
  printf ']'
  if [ -n "$ORIGIN_HASH" ]; then printf ',"originHash":{"path":%s,"sha256":%s}' "$(jstr "$HASH_PATH")" "$(jstr "$ORIGIN_HASH")"; else printf ',"originHash":null'; fi
  printf ',"rolledBack":%s' "$([ -z "$ROLLED_BACK" ] && printf null || printf '%s' "$ROLLED_BACK")"
  if [ -n "$ERR_CODE" ]; then printf ',"error":{"code":%s,"detail":%s}' "$(jstr "$ERR_CODE")" "$(jstr "$ERR_DETAIL")"; else printf ',"error":null'; fi
  printf '}\n'
}

emit_text_tail() {  # 사람용 — 문제 · 오류를 표준 오류로
  local path code detail
  while IFS="$TAB" read -r path code detail; do
    [ -n "$path" ] || continue
    echo "  오류: $path — $detail" >&2
  done < <(sort -u "$PROBLEMS")
  if [ -n "$ERR_CODE" ]; then echo "오류: $ERR_DETAIL" >&2; fi
  return 0
}

finish() {  # finish <종료 코드> — 결과를 내고 끝낸다
  EXITCODE="$1"
  if [ "$JSON" = 1 ]; then emit_json; else emit_text_tail; fi
  exit "$EXITCODE"
}

fail() {  # fail <종료 코드> <코드> <설명>
  ERR_CODE="$2"; ERR_DETAIL="$3"
  finish "$1"
}

# ── 도구 ──
sha256_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 | cut -d' ' -f1
  else openssl dgst -sha256 | sed 's/^.* //'; fi
}
norm_text() { awk '{ sub(/\r$/, ""); print }' "$1"; }  # 줄 끝 CRLF → LF, 마지막 줄에 줄바꿈을 보장

origin_hash_of() {  # origin_hash_of <저장소 안 경로> — .md 는 줄바꿈을 LF 로 맞춘 뒤 해시
  case "$1" in
    *.md) norm_text "$REPO/$1" | sha256_stdin ;;
    *) sha256_stdin < "$REPO/$1" ;;
  esac
}

kind_of() {  # 지금 있는 것의 종류 — absent · link · dir · file · other
  if [ -L "$1" ]; then echo link
  elif [ -d "$1" ]; then echo dir
  elif [ -f "$1" ]; then echo file
  elif [ -e "$1" ]; then echo other
  else echo absent; fi
}
is_managed_dir() { [ -d "$1" ] && [ ! -L "$1" ] && [ -f "$1/.install-mode" ]; }  # 하네스가 복사로 만든 폴더 (표시 파일이 있다)

existing_source() {  # 지금 ~/.claude/harness 가 가리키는 원본 (없으면 빈 값)
  local h="$CLAUDE_DIR/harness"
  if [ -L "$h" ]; then readlink "$h"
  elif is_managed_dir "$h"; then sed -n 2p "$h/.install-mode" | tr -d '\r'
  fi
}

# ── 잘못된 사용 ──
[ -z "$ARGERR" ] || fail 2 badArgs "$ARGERR"
[ "$CLAUDE_DIR" != "/" ] || fail 2 badArgs "CLAUDE_CONFIG_DIR 가 / 입니다"
[ "$HARNESS_HOME" != "/" ] || fail 2 badArgs "CLAUDE_HARNESS_HOME 가 / 입니다"
[ "$(real_path "$REPO")" != "$(real_path "$HARNESS_HOME/repo")" ] && DEVMODE=true
EXISTING="$(existing_source)"

# ── 원본 해시 ──
if [ "$CMD" = originHash ]; then
  case "$HASH_PATH" in
    ""|/*|..|../*|*/..|*/../*|*"$TAB"*) fail 2 badArgs "저장소 안의 상대 경로여야 합니다: $HASH_PATH" ;;
  esac
  { [ -f "$REPO/$HASH_PATH" ] && [ ! -L "$REPO/$HASH_PATH" ]; } || fail 2 notFound "저장소에 그런 파일이 없습니다: $HASH_PATH"
  ORIGIN_HASH="$(origin_hash_of "$HASH_PATH")"
  if [ "$JSON" = 1 ]; then finish 0; else echo "$ORIGIN_HASH"; exit 0; fi
fi

# ── 백업 목록 ──
BACKUP_ID_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{6}(-[0-9]+)?$'

list_backups() {
  : > "$WORK/backups.tsv"
  local d id mf created command added changed removed files bytes readable
  for d in "$BACKUPS"/*/; do
    [ -d "$d" ] || continue
    id="$(basename "$d")"
    printf '%s' "$id" | grep -Eq "$BACKUP_ID_RE" || continue
    mf="$d/manifest.txt"
    if [ -f "$mf" ]; then
      created="$(sed -n 's/^# createdAt: //p' "$mf" | head -n 1)"
      command="$(sed -n 's/^# command: //p' "$mf" | head -n 1)"
      read -r added changed removed < <(awk -F'\t' '!/^#/ && $2 != "dir" { c[$1]++ } END { print c["add"] + 0, c["change"] + 0, c["remove"] + 0 }' "$mf")
      readable=true
    else
      created="-"; command="-"; added=0; changed=0; removed=0; readable=false
    fi
    files="$(find "$d/files" -type f 2>/dev/null | wc -l | tr -d ' ')"
    bytes="$(find "$d/files" -type f -exec cat {} + 2>/dev/null | wc -c | tr -d ' ')"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "${created:--}" "${command:--}" "$added" "$changed" "$removed" "$files" "$bytes" "$readable"
  done | sort -r >> "$WORK/backups.tsv"
}

if [ "$CMD" = backups ]; then
  list_backups
  if [ "$JSON" != 1 ]; then
    if [ ! -s "$WORK/backups.tsv" ]; then echo "백업이 없습니다 ($BACKUPS)"
    else
      echo "백업 ($BACKUPS)"
      while IFS="$TAB" read -r id created command added changed removed files bytes readable; do
        if [ "$readable" = true ]; then echo "  $id  $command — 새로 $added · 바뀜 $changed · 지움 $removed (백업한 파일 $files개)"
        else echo "  $id  (목록 파일을 읽을 수 없음)"; fi
      done < "$WORK/backups.tsv"
    fi
  fi
  finish 0
fi

# ── 잠금 (설치 · 되돌리기 · 지우기를 동시에 못 돌게) ──
acquire_lock() {
  mkdir -p "$CLAUDE_DIR" || fail 3 writeFailed "$CLAUDE_DIR 를 만들 수 없습니다"
  local tries=0 pid
  while ! mkdir "$LOCKDIR" 2>/dev/null; do
    pid="$(cat "$LOCKDIR/pid" 2>/dev/null || true)"
    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
      rm -rf "$LOCKDIR"  # 죽은 프로세스가 남긴 잠금
    else
      tries=$((tries + 1))
      [ "$tries" -lt 3 ] || fail 2 busy "다른 설치가 진행 중입니다 ($LOCKDIR)"
      sleep 1
    fi
  done
  echo "$$" > "$LOCKDIR/pid"
  LOCK_HELD=1
}

# ── 되돌리기 ──
REV="$WORK/restore.rev"

under_link() {  # under_link <상대 경로> — 복사본(harness · skills/<이름>) 안의 경로인데 그 안쪽 위 폴더가 링크면 0. 링크를 따라가 저장소 같은 바깥을 건드리지 않으려고
  local rel="$1" slot rest acc="" part oldifs="$IFS"
  case "$rel" in
    harness/*) slot=harness ;;
    skills/*/*) rest="${rel#skills/}"; slot="skills/${rest%%/*}" ;;
    *) return 1 ;;
  esac
  rest="${rel%/*}"
  set -f; IFS=/
  for part in $rest; do
    acc="${acc:+$acc/}$part"
    case "$acc" in
      "$slot"|"$slot"/*) if [ -L "$CLAUDE_DIR/$acc" ]; then IFS="$oldifs"; set +f; return 0; fi ;;
    esac
  done
  IFS="$oldifs"; set +f
  return 1
}

safe_rel() {  # safe_rel <경로> <종류> — 백업 목록의 경로가 하네스가 다루는 자리 안인지 본다 (agents · skills 폴더 자체는 새로 만들었던 폴더로만)
  case "$1" in
    ""|/*|..|../*|*/..|*/../*|*"$TAB"*) return 1 ;;
    harness|harness/*|skills/*|agents/*|"$STATE_FILE") return 0 ;;
    agents|skills) [ "$2" = dir ] && return 0 ;;
  esac
  return 1
}

restore_need() {  # restore_need <동작> <종류> <경로> <덧붙임> — 되돌릴 일이 있으면 0
  local act="$1" type="$2" p="$3" extra="$4" cur="$CLAUDE_DIR/$3"
  if under_link "$p"; then [ "$act" = remove ] || [ "$act" = change ]; return; fi  # 링크 아래에는 아무것도 없는 셈 — 돌려놓을 것만 남는다
  case "$act:$type" in
    add:file) [ -f "$cur" ] || [ -L "$cur" ] ;;
    add:link) [ -L "$cur" ] ;;
    remove:file|change:file) [ ! -f "$BK_DIR/files/$p" ] || [ -L "$cur" ] || [ ! -f "$cur" ] || ! cmp -s "$BK_DIR/files/$p" "$cur" ;;
    remove:link|change:link) [ ! -L "$cur" ] || [ "$(readlink "$cur")" != "$extra" ] ;;
    *) return 1 ;;
  esac
}

restore_prepare() {  # restore_prepare <번호> — 목록을 검사하고 되돌릴 계획(OPS)을 세운다
  local id="$1" act type p extra want
  printf '%s' "$id" | grep -Eq "$BACKUP_ID_RE" || fail 2 badArgs "백업 번호 모양이 틀립니다: $id"
  BK_DIR="$BACKUPS/$id"; MANIFEST="$BK_DIR/manifest.txt"
  [ -f "$MANIFEST" ] || fail 2 noBackup "그런 백업이 없습니다: $id (--backups 로 본다)"
  want="$(sed -n 's/^# claudeDir: //p' "$MANIFEST" | head -n 1)"
  [ "$want" = "$CLAUDE_DIR" ] || fail 2 wrongTarget "이 백업은 다른 곳($want)의 것입니다 — 지금 대상은 $CLAUDE_DIR"
  grep -v '^#' "$MANIFEST" | awk '{ a[NR] = $0 } END { for (i = NR; i > 0; i--) print a[i] }' > "$REV"
  while IFS="$TAB" read -r act type p extra; do
    [ -n "$act" ] || continue
    case "$act" in add|change|remove) ;; *) fail 2 badBackup "백업 목록이 깨졌습니다 (동작: $act)" ;; esac
    case "$type" in file|link|dir) ;; *) fail 2 badBackup "백업 목록이 깨졌습니다 (종류: $type)" ;; esac
    safe_rel "$p" "$type" || fail 2 badBackup "백업 목록에 하네스가 다루지 않는 경로가 있습니다: $p"
  done < "$REV"
  BK_ID="$id"
  BK_FILES="$(find "$BK_DIR/files" -type f 2>/dev/null | wc -l | tr -d ' ')"
  : > "$OPS"; SAME=0
  while IFS="$TAB" read -r act type p extra; do
    [ -n "$act" ] || continue
    [ "$type" = dir ] && continue
    if restore_need "$act" "$type" "$p" "$extra"; then
      case "$act" in add) add_op remove "$type" "$p" ;; remove) add_op add "$type" "$p" "$extra" ;; change) add_op change "$type" "$p" "$extra" ;; esac
    else SAME=$((SAME + 1)); fi
  done < "$REV"
}

restore_exec() {  # 되돌린다 — 1) 설치가 새로 만든 파일 · 링크 지우기  2) 새로 만든 빈 폴더 지우기  3) 덮어쓴 것 · 지운 것 돌려놓기. 하나라도 못 하면 1
  local act type p extra tmp failed=0
  while IFS="$TAB" read -r act type p extra; do
    [ "$act" = add ] || continue
    under_link "$p" && continue
    case "$type" in
      file) if [ -f "$CLAUDE_DIR/$p" ] || [ -L "$CLAUDE_DIR/$p" ]; then rm -f "$CLAUDE_DIR/$p" || failed=1; fi ;;
      link) if [ -L "$CLAUDE_DIR/$p" ]; then rm -f "$CLAUDE_DIR/$p" || failed=1; fi ;;
    esac
  done < "$REV"
  while IFS="$TAB" read -r act type p extra; do
    if [ "$act" = add ] && [ "$type" = dir ] && ! under_link "$p"; then rmdir "$CLAUDE_DIR/$p" 2>/dev/null || true; fi
  done < "$REV"
  while IFS="$TAB" read -r act type p extra; do
    [ -n "$act" ] || continue
    [ "$act" = add ] && continue
    if under_link "$p"; then failed=1; continue; fi
    if [ "$type" != dir ] && ! restore_need "$act" "$type" "$p" "$extra"; then continue; fi  # 이미 같다
    case "$type" in
      dir) mkdir -p "$CLAUDE_DIR/$p" || failed=1 ;;
      file)
        if [ ! -f "$BK_DIR/files/$p" ]; then failed=1; continue; fi
        mkdir -p "$(dirname "$CLAUDE_DIR/$p")" || { failed=1; continue; }
        tmp="$CLAUDE_DIR/$p.harness-tmp.$$"
        if cp -p "$BK_DIR/files/$p" "$tmp" && mv -f "$tmp" "$CLAUDE_DIR/$p"; then :; else rm -f "$tmp"; failed=1; fi ;;
      link)
        mkdir -p "$(dirname "$CLAUDE_DIR/$p")" || { failed=1; continue; }
        if [ -L "$CLAUDE_DIR/$p" ]; then rm -f "$CLAUDE_DIR/$p"; fi
        ln -s "$extra" "$CLAUDE_DIR/$p" || failed=1 ;;
    esac
  done < "$REV"
  [ "$failed" = 0 ]
}

cmd_restore() {
  if [ "$DRY" = 1 ]; then
    restore_prepare "$RESTORE_ID"
    if [ "$JSON" != 1 ]; then
      echo "백업 $RESTORE_ID 로 되돌리면 (미리보기 — 아무것도 쓰지 않았습니다)"
      awk -F'\t' '{ print "  " ($1 == "add" ? "다시 만듦" : ($1 == "remove" ? "지움" : "돌려놓음")) ": " $3 }' "$OPS"
      [ -s "$OPS" ] || echo "  (바뀌는 것 없음)"
    fi
    finish 0
  fi
  acquire_lock
  restore_prepare "$RESTORE_ID"
  if restore_exec; then
    say "백업 $RESTORE_ID 로 되돌렸습니다 ($BK_DIR)"
    awk -F'\t' '{ print "  " ($1 == "add" ? "다시 만듦" : ($1 == "remove" ? "지움" : "돌려놓음")) ": " $3 }' "$OPS" | { [ "$JSON" = 1 ] && cat >/dev/null || cat; }
    finish 0
  fi
  fail 3 restoreFailed "일부를 되돌리지 못했습니다 — 백업 목록: $MANIFEST"
}

# ── 내 수정 읽기 (custom/) ──
parse_values() {  # parse_values <값 파일> — "키<TAB>값" 줄을 낸다. 모양이 틀리면 설명을 $WORK/awk.err 에 쓰고 1
  rm -f "$WORK/awk.err"
  ERRF="$WORK/awk.err" awk '
    { sub(/\r$/, "") }
    /^[ \t]*$/ { next }
    /^[ \t]*#/ { next }
    {
      i = index($0, ":")
      if (i < 2) { print NR "번째 줄이 \"키: 값\" 모양이 아니다" > ENVIRON["ERRF"]; exit 1 }
      k = substr($0, 1, i - 1); v = substr($0, i + 1)
      gsub(/^[ \t]+|[ \t]+$/, "", v)
      if (k !~ /^[A-Za-z][A-Za-z0-9_-]*$/) { print NR "번째 줄의 키가 올바르지 않다: " k > ENVIRON["ERRF"]; exit 1 }
      if (k == "name" || k == "hooks") { print NR "번째 줄: " k " 는 바꿀 수 없다" > ENVIRON["ERRF"]; exit 1 }
      if (v == "") { print NR "번째 줄: " k " 의 값이 비었다" > ENVIRON["ERRF"]; exit 1 }
      if (v ~ /\t/) { print NR "번째 줄: " k " 의 값에 탭이 있다" > ENVIRON["ERRF"]; exit 1 }
      if (k in seen) { print NR "번째 줄: " k " 가 두 번 나온다" > ENVIRON["ERRF"]; exit 1 }
      seen[k] = 1
      print k "\t" v
    }
  ' "$1"
  [ ! -s "$WORK/awk.err" ]
}

apply_values() {  # apply_values <대상 파일> <값 파일> — 앞머리(---)에 값을 넣는다. 안 되면 설명을 $WORK/awk.err 에 쓰고 1
  local tgt="$1" tmp="$WORK/values.out"
  parse_values "$2" > "$WORK/values.tsv" || return 1
  rm -f "$WORK/awk.err"
  VFILE="$WORK/values.tsv" ERRF="$WORK/awk.err" awk '
    BEGIN {
      vf = ENVIRON["VFILE"]
      while ((getline l < vf) > 0) { i = index(l, "\t"); n++; key[n] = substr(l, 1, i - 1); val[n] = substr(l, i + 1) }
      close(vf)
    }
    NR == 1 { if ($0 != "---") { print "앞머리(---)가 없다" > ENVIRON["ERRF"]; bad = 1; exit 1 } fm = 1; print; next }
    fm && $0 == "---" {
      for (j = 1; j <= n; j++) if (!used[j]) print key[j] ": " val[j]
      fm = 0; closed = 1; print; next
    }
    fm {
      if (prev && ($0 ~ /^[ \t]/ || $0 ~ /^- /)) { print key[prev] " 의 값이 여러 줄이라 값 바꾸기로 바꿀 수 없다" > ENVIRON["ERRF"]; bad = 1; exit 1 }
      prev = 0
      for (j = 1; j <= n; j++) {
        if (index($0, key[j] ":") == 1) { print key[j] ": " val[j]; used[j] = 1; prev = j; next }
      }
      print; next
    }
    { print }
    END { if (!closed && !bad) print "앞머리(---)가 닫히지 않았다" > ENVIRON["ERRF"] }
  ' "$tgt" > "$tmp"
  [ ! -s "$WORK/awk.err" ] || return 1
  mv -f "$tmp" "$tgt"
}

apply_append() {  # apply_append <대상 파일> <덧붙일 파일> — 원본 끝에 빈 줄 하나를 두고 덧붙인다
  local tmp="$WORK/append.out"
  { norm_text "$1"; printf '\n'; norm_text "$2"; } > "$tmp" && mv -f "$tmp" "$1"
}

classify_custom() {  # classify_custom <내 수정 폴더 안 상대 경로>
  local rel="$1" top rest kind target sidecar rec cur origin
  case "$rel" in *"$TAB"*|*$'\r'*) problem "$rel" badPath "경로에 탭 · 줄바꿈 글자를 쓸 수 없다"; return ;; esac
  if [ -L "$CUSTOM/$rel" ]; then problem "$rel" symlinkInCustom "내 수정 폴더 안에는 링크를 둘 수 없다"; return; fi
  [ -f "$CUSTOM/$rel" ] || { problem "$rel" badPath "경로를 읽을 수 없다"; return; }
  case "$rel" in */*) ;; *) problem "$rel" unsupported "$rel 는 파일이 아니라 폴더여야 한다"; return ;; esac
  top="${rel%%/*}"; rest="${rel#*/}"
  case "$rel" in agents/_common/*) problem "$rel" unsupported "공통 규칙 · 가드 hook(agents/_common)은 내 수정으로 바꿀 수 없다"; return ;; esac
  case "$top" in
    agents) case "$rest" in */*) problem "$rel" unsupported "agents 안에는 하위 폴더를 둘 수 없다"; return ;; esac ;;
    skills) case "$rest" in */*) ;; *) problem "$rel" unsupported "skills 안에는 폴더만 둔다 (skills/<이름>/SKILL.md)"; return ;; esac ;;
  esac
  kind=""; target="$rel"
  case "$rel" in
    *.origin) printf '%s\n' "${rel%.origin}" >> "$WORK/sidecars.txt"; return ;;
    *.values.yml) kind=values; target="${rel%.values.yml}.md" ;;
    *.append.md) kind=append; target="${rel%.append.md}.md" ;;
  esac
  if [ -n "$kind" ]; then
    { [ -f "$REPO/$target" ] && [ ! -L "$REPO/$target" ]; } || { problem "$rel" targetMissing "고칠 원본 파일($target)이 저장소에 없다"; return; }
    if [ "$kind" = values ]; then
      parse_values "$CUSTOM/$rel" > /dev/null || { problem "$rel" badValues "$(cat "$WORK/awk.err")"; return; }
    elif ! grep -q '[^[:space:]]' "$CUSTOM/$rel"; then
      warning "$rel" emptyAppend "덧붙일 내용이 비어 있어 건너뛴다"; return
    fi
    printf '%s\t%s\t-\n' "$target" "$kind" >> "$ITEMS"
    return
  fi
  sidecar="$CUSTOM/$rel.origin"
  rec=""
  if [ -f "$sidecar" ]; then
    rec="$(tr -d ' \t\r\n' < "$sidecar" | tr 'A-F' 'a-f')"
    printf '%s' "$rec" | grep -Eq '^[0-9a-f]{64}$' || { problem "$rel.origin" badOrigin "원본 해시는 sha256 16진수 64글자여야 한다"; return; }
  fi
  if [ -f "$REPO/$rel" ] && [ ! -L "$REPO/$rel" ]; then
    kind=replace
    cur="$(origin_hash_of "$rel")"
    if [ -n "$rec" ]; then
      if [ "$rec" = "$cur" ]; then origin=false; else origin=true; printf '%s\t%s\t%s\n' "$rel" "$rec" "$cur" >> "$ORIGINS"; fi
    else
      origin="-"
      warning "$rel" noOriginHash "만들 때의 원본 해시가 없어 원본이 바뀌었는지 알 수 없다"
    fi
  elif [ -n "$rec" ]; then  # 원본에서 사라진 파일을 통째로 바꿔 둔 경우
    kind=replace; origin=true
    printf '%s\t%s\t-\n' "$rel" "$rec" >> "$ORIGINS"
    warning "$rel" originGone "통째로 바꾼 파일의 원본이 저장소에서 사라졌다"
  else
    kind=new; origin="-"
  fi
  printf '%s\t%s\t%s\n' "$rel" "$kind" "$origin" >> "$ITEMS"
}

scan_custom() {
  : > "$WORK/sidecars.txt"
  [ -d "$CUSTOM" ] || return 0
  local e name f
  for e in "$CUSTOM"/* "$CUSTOM"/.[!.]*; do
    { [ -e "$e" ] || [ -L "$e" ]; } || continue
    name="$(basename "$e")"
    case "$name" in
      config.local.json)
        if [ -L "$e" ]; then problem "$name" symlinkInCustom "내 수정 폴더 안에는 링크를 둘 수 없다"
        elif [ -f "$e" ]; then printf '%s\tconfig\t-\n' "$name" >> "$ITEMS"
        else problem "$name" unsupported "config.local.json 이 파일이 아니다"; fi ;;
      agent-cats.json|.git|.gitignore) ;;  # 앱 · git 이 쓰는 것 — 설치는 읽지 않는다
      agents|skills|shared)
        while IFS= read -r f; do classify_custom "${f#"$CUSTOM"/}"; done < <(find "$e" \( -type f -o -type l \) -print | sort) ;;
      *) warning "$name" ignored "내 수정 폴더에서 설치가 읽지 않는 항목" ;;
    esac
  done
  local s
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    awk -F'\t' -v p="$s" '$2 == "replace" && $1 == p { found = 1 } END { exit !found }' "$ITEMS" || warning "$s.origin" orphanOrigin "짝이 되는 통째로 바꾼 파일이 없다"
  done < "$WORK/sidecars.txt"
}

# ── 합치기 (원본 + 내 수정) ──
put_custom() {  # put_custom <내 파일> <대상> — .md 는 줄바꿈을 LF 로 맞춘다
  case "$1" in *.md) norm_text "$1" > "$2" ;; *) cp "$1" "$2" ;; esac
}

stage_source() {
  if ! awk -F'\t' '$2 != "config" { found = 1 } END { exit !found }' "$ITEMS"; then SRC="$REPO"; return 0; fi
  SRC="$WORK/src"
  mkdir -p "$SRC"
  local f rel path kind origin
  while IFS= read -r f; do
    rel="${f#./}"
    mkdir -p "$SRC/$(dirname "$rel")" && cp -p "$REPO/$rel" "$SRC/$rel"
  done < <(cd "$REPO" && find . -path ./.git -prune -o -type f -print | sort)
  while IFS="$TAB" read -r path kind origin; do
    case "$kind" in replace|new) mkdir -p "$SRC/$(dirname "$path")" && put_custom "$CUSTOM/$path" "$SRC/$path" ;; esac
  done < "$ITEMS"
  while IFS="$TAB" read -r path kind origin; do
    if [ "$kind" = values ]; then
      apply_values "$SRC/$path" "$CUSTOM/${path%.md}.values.yml" || problem "$path" badValues "$(cat "$WORK/awk.err")"
    fi
  done < "$ITEMS"
  while IFS="$TAB" read -r path kind origin; do
    if [ "$kind" = append ]; then apply_append "$SRC/$path" "$CUSTOM/${path%.md}.append.md"; fi
  done < "$ITEMS"
}

check_agent() {  # check_agent <합친 원본> <이름.md> — 틀이 맞는지 본다. 틀리면 설명을 출력하고 1
  local f="$1" base; base="$(basename "$2" .md)"
  if [ "$(sed -n 2p "$f")" != "name: $base" ]; then
    echo "두 번째 줄이 'name: $base' 이어야 한다"; return 1
  fi
  if sed -n '2,/^---$/p' "$f" | grep -q '^hooks:'; then
    echo "hooks 는 쓰지 않는다 (설치할 때 agents/_common/hooks.yml 이 붙는다)"; return 1
  fi
}

build_agent() {  # build_agent <원본> — 앞머리 끝에 hooks.yml, 표시 줄 자리(없으면 끝)에 rules.md 를 넣어 출력한다
  local common="$SRC/agents/_common"
  awk -v hooks="$common/hooks.yml" -v rules="$common/rules.md" -v mark="$MARK" '
    function put(f,  l) { while ((getline l < f) > 0) print l; close(f) }
    NR == 1 && $0 == "---" { fm = 1; print; next }
    fm && $0 == "---"      { put(hooks); print; fm = 0; next }
    $0 == mark             { put(rules); done = 1; next }
                           { print }
    END { if (!done) { print ""; put(rules) } }
  ' "$1"
}

stage_agents() {
  : > "$WORK/agents.list"
  local f name err
  for f in "$SRC"/agents/*.md; do
    [ -f "$f" ] || continue
    name="$(basename "$f")"
    if ! err="$(check_agent "$f" "$name")"; then problem "agents/$name" invalidAgent "$err"; continue; fi
    build_agent "$f" > "$WORK/files/agents/$name"
    echo "$name" >> "$WORK/agents.list"
  done
}

decide_mode() {
  MODE=link
  if awk -F'\t' '{ found = 1 } END { exit !found }' "$ITEMS" || [ "$LINK_OK" = 0 ]; then MODE=copy; fi
}

# 하네스 폴더(복사 방식)에 들어갈 파일 목록 — 상대 경로 <TAB> 원본 파일
slot_list() {  # slot_list <이름> <원본 폴더> <표시 파일에 적을 원본> <설정 파일 넣기:0|1>
  local id="$1" dir="$2" mark_src="$3" with_config="$4" f rel out="$WORK/slot.$1"
  printf 'copy\n%s\n' "$mark_src" > "$WORK/files/marker.$id"
  {
    while IFS= read -r f; do
      rel="${f#./}"
      if [ "$with_config" = 1 ] && [ "$rel" = "config.local.json" ]; then continue; fi
      printf '%s\t%s\n' "$rel" "$dir/$rel"
    done < <(cd "$dir" && find . -path ./.git -prune -o -type f -print)
    if [ "$with_config" = 1 ] && [ -n "$CONFIG_SRC" ]; then printf 'config.local.json\t%s\n' "$CONFIG_SRC"; fi
    printf '.install-mode\t%s\n' "$WORK/files/marker.$id"
  } | sort > "$out"
}

choose_config() {  # 복사 방식일 때 ~/.claude/harness/config.local.json 으로 들어갈 설정 — 내 수정 > 저장소 > 지금 설치에 있는 것 > (예전 방식) 예시
  CONFIG_SRC=""
  [ "$MODE" = copy ] || return 0
  if awk -F'\t' '$2 == "config" { found = 1 } END { exit !found }' "$ITEMS"; then CONFIG_SRC="$CUSTOM/config.local.json"
  elif [ -f "$REPO/config.local.json" ]; then CONFIG_SRC="$REPO/config.local.json"
  elif is_managed_dir "$CLAUDE_DIR/harness" && [ -f "$CLAUDE_DIR/harness/config.local.json" ] && [ ! -L "$CLAUDE_DIR/harness/config.local.json" ]; then
    CONFIG_SRC="$CLAUDE_DIR/harness/config.local.json"
    warning "config.local.json" configOnlyInInstall "설정이 내 수정 폴더(custom/)가 아니라 설치본에만 있다 — 다음 설치까지는 그대로 둔다"
  elif [ ! -s "$ITEMS" ] && [ "$DEVMODE" = true ] && [ -f "$REPO/config.example.json" ]; then
    CONFIG_SRC="$REPO/config.example.json"  # 예전처럼 저장소에 설정 파일을 만들어 주는 사람 — 복사본에도 같은 내용
  fi
}

stage_slots() {
  choose_config
  if [ "$MODE" = copy ]; then slot_list harness "$SRC" "$REPO" 1; fi
  : > "$WORK/skills.list"
  local d n
  for d in "$SRC"/skills/*/; do
    [ -d "$d" ] || continue
    n="$(basename "$d")"
    echo "$n" >> "$WORK/skills.list"
    if [ "$LINK_OK" = 0 ]; then slot_list "skill.$n" "${d%/}" "$REPO/skills/$n" 0; fi
  done
  # 내 수정으로 새로 만든 에이전트 · 스킬 (원본에 없는 이름)
  : > "$WORK/state.desired"
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    [ -f "$REPO/agents/$n" ] || echo "agent $n" >> "$WORK/state.desired"
  done < "$WORK/agents.list"
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    [ -d "$REPO/skills/$n" ] || echo "skill $n" >> "$WORK/state.desired"
  done < "$WORK/skills.list"
  sort -o "$WORK/state.desired" "$WORK/state.desired"
}

read_state() {  # 지난번 설치가 남긴, 내 수정으로 새로 만든 에이전트 · 스킬 이름
  : > "$WORK/state.prev"
  if [ -f "$CLAUDE_DIR/$STATE_FILE" ] && [ ! -L "$CLAUDE_DIR/$STATE_FILE" ]; then
    grep -E '^(agent [A-Za-z0-9][A-Za-z0-9._-]*\.md|skill [A-Za-z0-9][A-Za-z0-9._-]*)$' "$CLAUDE_DIR/$STATE_FILE" | sort -u > "$WORK/state.prev" || true
  fi
}
in_state() { grep -Fxq -- "$1" "$WORK/state.prev"; }
in_list() { grep -Fxq -- "$2" "$1"; }

# ── 계획 (지금 ~/.claude 와 비교) ──
file_compare() {  # file_compare <경로> <새 내용 파일>
  local p="$1" src="$2" cur="$CLAUDE_DIR/$1" k
  k="$(kind_of "$cur")"
  case "$k" in
    absent) add_op add file "$p" "$src" ;;
    file) if cmp -s "$src" "$cur"; then SAME=$((SAME + 1)); else add_op change file "$p" "$src"; fi ;;
    *) add_skip file "$p" notOurs ;;
  esac
}

remove_tree() {  # remove_tree <경로> — 복사로 만든 폴더 전체를 지운다 (파일 · 링크 → 폴더 깊은 것부터)
  local p="$1" cur="$CLAUDE_DIR/$1" rel
  while IFS= read -r rel; do
    rel="${rel#./}"
    if [ -L "$cur/$rel" ]; then add_op remove link "$p/$rel" "$(readlink "$cur/$rel")"; else add_op remove file "$p/$rel"; fi
  done < <(cd "$cur" && find . \( -type f -o -type l \) -print | sort)
  while IFS= read -r rel; do
    if [ "$rel" = "." ]; then add_op remove dir "$p"; else add_op remove dir "$p/${rel#./}"; fi
  done < <(cd "$cur" && find . -type d -print | sort -r)
}

slot_link() {  # slot_link <경로> <링크 대상> — 링크로 둔다
  local p="$1" t="$2" cur="$CLAUDE_DIR/$1" k
  k="$(kind_of "$cur")"
  case "$k" in
    absent) add_op add link "$p" "$t" ;;
    link) if [ "$(readlink "$cur")" = "$t" ]; then SAME=$((SAME + 1)); else add_op change link "$p" "$t"; fi ;;
    dir) if is_managed_dir "$cur"; then remove_tree "$p"; add_op add link "$p" "$t"; else add_skip link "$p" notOurs; fi ;;
    *) add_skip link "$p" notOurs ;;
  esac
}

copy_slot() {  # copy_slot <목록 이름> <경로> — 복사로 둔다
  local id="$1" p="$2" cur="$CLAUDE_DIR/$2" k fresh=0 rel srcf
  k="$(kind_of "$cur")"
  case "$k" in
    absent) fresh=1 ;;
    link) add_op remove link "$p" "$(readlink "$cur")"; fresh=1 ;;
    dir)
      if is_managed_dir "$cur"; then
        cut -f1 "$WORK/slot.$id" > "$WORK/slot.$id.rels"
        while IFS= read -r rel; do
          rel="${rel#./}"
          in_list "$WORK/slot.$id.rels" "$rel" && continue
          if [ -L "$cur/$rel" ]; then add_op remove link "$p/$rel" "$(readlink "$cur/$rel")"; else add_op remove file "$p/$rel"; fi
        done < <(cd "$cur" && find . \( -type f -o -type l \) -print | sort)
      else
        add_skip dir "$p" notOurs
        [ "$p" = harness ] && problem harness harnessNotOurs "$CLAUDE_DIR/harness 에 하네스가 만들지 않은 폴더가 있다 — 직접 확인해야 한다"
        return 0
      fi ;;
    *) add_skip dir "$p" notOurs
       [ "$p" = harness ] && problem harness harnessNotOurs "$CLAUDE_DIR/harness 에 하네스가 만들지 않은 파일이 있다 — 직접 확인해야 한다"
       return 0 ;;
  esac
  while IFS="$TAB" read -r rel srcf; do
    [ -n "$rel" ] || continue
    if [ "$fresh" = 1 ]; then add_op add file "$p/$rel" "$srcf"; else file_compare "$p/$rel" "$srcf"; fi
  done < "$WORK/slot.$id"
}

build_plan() {
  : > "$OPS"; : > "$SKIPS"; SAME=0
  read_state
  local n r f cur target
  if [ "$MODE" = link ]; then slot_link harness "$REPO"; else copy_slot harness harness; fi
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    cur="$CLAUDE_DIR/skills/$n"
    if [ ! -d "$REPO/skills/$n" ] && ! in_state "skill $n" && { [ -e "$cur" ] || [ -L "$cur" ]; }; then add_skip link "skills/$n" notOurs; continue; fi
    if [ "$LINK_OK" = 0 ]; then copy_slot "skill.$n" "skills/$n"
    else
      if [ "$MODE" = copy ]; then target="$CLAUDE_DIR/harness/skills/$n"; else target="$REPO/skills/$n"; fi
      slot_link "skills/$n" "$target"
    fi
  done < "$WORK/skills.list"
  for r in $RETIRED; do
    cur="$CLAUDE_DIR/agents/$r.md"
    if [ -L "$cur" ]; then add_op remove link "agents/$r.md" "$(readlink "$cur")"
    elif [ -f "$cur" ]; then add_op remove file "agents/$r.md"; fi
  done
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    cur="$CLAUDE_DIR/agents/$f"
    if [ ! -f "$REPO/agents/$f" ] && ! in_state "agent $f" && { [ -e "$cur" ] || [ -L "$cur" ]; }; then add_skip file "agents/$f" notOurs; continue; fi
    file_compare "agents/$f" "$WORK/files/agents/$f"
  done < "$WORK/agents.list"
  # 상태 파일 (내 수정으로 새로 만든 것이 있을 때만)
  if [ -s "$WORK/state.desired" ]; then file_compare "$STATE_FILE" "$WORK/state.desired"
  elif [ -f "$CLAUDE_DIR/$STATE_FILE" ] && [ ! -L "$CLAUDE_DIR/$STATE_FILE" ]; then add_op remove file "$STATE_FILE"; fi
  # 내 수정에서 빠진 에이전트 · 스킬
  while IFS=' ' read -r kind n; do
    [ -n "$n" ] || continue
    if [ "$kind" = agent ]; then
      in_list "$WORK/agents.list" "$n" && continue
      cur="$CLAUDE_DIR/agents/$n"
      if [ -L "$cur" ]; then add_op remove link "agents/$n" "$(readlink "$cur")"
      elif [ -f "$cur" ]; then add_op remove file "agents/$n"; fi
    else
      in_list "$WORK/skills.list" "$n" && continue
      cur="$CLAUDE_DIR/skills/$n"
      case "$(kind_of "$cur")" in
        link) add_op remove link "skills/$n" "$(readlink "$cur")" ;;
        dir) if is_managed_dir "$cur"; then remove_tree "skills/$n"; else add_skip link "skills/$n" notOurs; fi ;;
      esac
    fi
  done < "$WORK/state.prev"
}

# ── 쓰기 (백업 → 실행 → 확인) ──
mk_parent() {  # mk_parent <상대 경로> — 위쪽 폴더를 만든다 (새로 만든 폴더는 되돌릴 수 있게 목록에 남긴다)
  local rel="$1" rest acc="" part oldifs="$IFS"
  rest="${1%/*}"
  [ "$rest" != "$1" ] || return 0
  set -f; IFS=/
  for part in $rest; do
    acc="${acc:+$acc/}$part"
    if [ ! -e "$CLAUDE_DIR/$acc" ] && [ ! -L "$CLAUDE_DIR/$acc" ]; then
      if ! mkdir "$CLAUDE_DIR/$acc"; then IFS="$oldifs"; set +f; return 1; fi
      printf 'add\tdir\t%s\t\n' "$acc" >> "$MANIFEST"
    fi
  done
  IFS="$oldifs"; set +f
}

put_file() {  # put_file <새 내용 파일> <상대 경로> — 임시 파일에 쓴 뒤 옮겨서 반쯤 쓴 파일이 남지 않게
  local dst="$CLAUDE_DIR/$2" tmp="$CLAUDE_DIR/$2.harness-tmp.$$"
  if cp "$1" "$tmp" && mv -f "$tmp" "$dst"; then return 0; fi
  rm -f "$tmp"; return 1
}

has_changes() { awk -F'\t' '$2 != "dir" { found = 1 } END { exit !found }' "$OPS"; }

apply_ops() {  # 계획(OPS)대로 — 백업을 남기고 실행한다. 실패하면 되돌리고 종료한다
  local ordered="$WORK/ops.ordered" act type p extra old n base err="" applied_same
  has_changes || return 0
  : > "$ordered"
  for act in remove change add; do awk -F'\t' -v a="$act" '$1 == a' "$OPS" >> "$ordered"; done
  mkdir -p "$BACKUPS" || fail 3 backupFailed "백업 폴더를 만들 수 없습니다: $BACKUPS"
  base="$(date +%Y-%m-%d_%H%M%S)"; BK_ID="$base"; n=1
  while ! mkdir "$BACKUPS/$BK_ID" 2>/dev/null; do
    n=$((n + 1)); BK_ID="$base-$n"
    [ "$n" -lt 100 ] || { BK_ID=""; fail 3 backupFailed "백업 폴더를 만들 수 없습니다: $BACKUPS"; }
  done
  BK_DIR="$BACKUPS/$BK_ID"; MANIFEST="$BK_DIR/manifest.txt"; BK_FILES=0
  mkdir -p "$BK_DIR/files" || { BK_ID=""; fail 3 backupFailed "백업 폴더를 만들 수 없습니다: $BK_DIR"; }
  {
    echo "# claude-harness backup v1"
    echo "# id: $BK_ID"
    echo "# createdAt: $(date +%Y-%m-%dT%H:%M:%S%z)"
    echo "# command: $CMD"
    echo "# claudeDir: $CLAUDE_DIR"
    echo "# repo: $REPO"
  } > "$MANIFEST" || { BK_ID=""; fail 3 backupFailed "백업 목록을 쓸 수 없습니다"; }
  # 1) 덮어쓰거나 지울 것을 백업하고 목록에 적는다 (아직 아무것도 바꾸지 않았다)
  while IFS="$TAB" read -r act type p extra; do
    case "$type" in
      file)
        if [ "$act" != add ]; then
          if ! { mkdir -p "$BK_DIR/files/$(dirname "$p")" && cp -p "$CLAUDE_DIR/$p" "$BK_DIR/files/$p"; }; then
            rm -rf "$BK_DIR"; BK_ID=""; fail 3 backupFailed "백업하지 못했습니다: $p — 아무것도 바꾸지 않았습니다"
          fi
          BK_FILES=$((BK_FILES + 1))
        fi
        printf '%s\tfile\t%s\t\n' "$act" "$p" >> "$MANIFEST" ;;
      link)
        if [ "$act" = add ]; then printf 'add\tlink\t%s\t%s\n' "$p" "$extra" >> "$MANIFEST"
        else printf '%s\tlink\t%s\t%s\n' "$act" "$p" "$(readlink "$CLAUDE_DIR/$p")" >> "$MANIFEST"; fi ;;
      dir) printf '%s\tdir\t%s\t\n' "$act" "$p" >> "$MANIFEST" ;;
    esac
  done < "$ordered"
  # 2) 실행
  while IFS="$TAB" read -r act type p extra; do
    if under_link "$p"; then err="$act $type $p (링크 아래)"; break; fi
    case "$act:$type" in
      remove:file|remove:link) rm -f "$CLAUDE_DIR/$p" ;;
      remove:dir) rmdir "$CLAUDE_DIR/$p" ;;
      change:file|add:file) mk_parent "$p" && put_file "$extra" "$p" ;;
      change:link) rm -f "$CLAUDE_DIR/$p" && ln -s "$extra" "$CLAUDE_DIR/$p" ;;
      add:link) mk_parent "$p" && ln -s "$extra" "$CLAUDE_DIR/$p" ;;
    esac || { err="$act $type $p"; break; }
  done < "$ordered"
  # 3) 확인 — 다시 계획을 세워 바뀔 것이 남아 있으면 실패
  if [ -z "$err" ]; then
    cp "$OPS" "$WORK/ops.applied"; cp "$SKIPS" "$WORK/skips.applied"; applied_same="$SAME"
    build_plan
    if has_changes; then err="확인 실패 — 설치 뒤에도 달라지는 것이 있다"; fi
    cp "$WORK/ops.applied" "$OPS"; cp "$WORK/skips.applied" "$SKIPS"; SAME="$applied_same"
  fi
  if [ -n "$err" ]; then
    grep -v '^#' "$MANIFEST" | awk '{ a[NR] = $0 } END { for (i = NR; i > 0; i--) print a[i] }' > "$REV"
    if restore_exec; then ROLLED_BACK=true; else ROLLED_BACK=false; fi
    fail 3 applyFailed "쓰는 중 실패했습니다 ($err) — 이미 쓴 것을 되돌렸는지: $ROLLED_BACK. 백업: $BK_DIR"
  fi
}

# ── 사람용 출력 ──
CHANGE_LABELS_DONE=0
print_plan_text() {  # 미리보기
  local path action type reason
  say "claude-harness 설치 미리보기 ($REPO) — 아무것도 쓰지 않았습니다"
  say "  방식: $([ "$MODE" = link ] && echo "링크" || echo "복사 (원본 + 내 수정)")$([ "$DEVMODE" = true ] && echo " · 개발자 모드 (원본: $REPO)")"
  while IFS="$TAB" read -r path action type reason; do
    [ -n "$path" ] || continue
    case "$action" in
      add) say "  새로 생김: $path" ;;
      change) say "  바뀜: $path" ;;
      remove) say "  지워짐: $path" ;;
      skip) say "  건너뜀: $path — 하네스가 만들지 않은 것이 있음 (직접 확인하세요)" ;;
    esac
  done < <(changes_rows)
  while IFS="$TAB" read -r path rec cur; do
    [ -n "$path" ] || continue
    say "  원본 바뀜: $path — 통째로 바꾼 파일의 원본이 달라졌습니다 (내 것을 그대로 쓰는 중)"
  done < <(sort "$ORIGINS")
  has_changes || say "  (바뀌는 것 없음)"
}

report_install() {
  local n r f skipline cur
  say "claude-harness 설치 ($REPO)"
  [ "$DEVMODE" = true ] && say "  개발자 모드 — 원본: $REPO (~/.claude-harness/repo 가 아님)"
  if [ "$MODE" = copy ]; then
    say "  내 수정 $(awk -F'\t' 'END { print NR }' "$ITEMS")개를 합쳐서 복사합니다"
  fi
  if grep -q "^dir${TAB}harness${TAB}\|^link${TAB}harness${TAB}" "$SKIPS"; then
    say "  건너뜀: $CLAUDE_DIR/harness — 링크가 아닌 파일이 이미 있음 (직접 확인하세요)"
  elif [ "$MODE" = link ]; then say "  연결: $CLAUDE_DIR/harness → $REPO"
  else say "  복사: $CLAUDE_DIR/harness ← $REPO (파일 $(awk 'END { print NR }' "$WORK/slot.harness")개)"; fi
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    if grep -q "^[a-z]*${TAB}skills/$n${TAB}" "$SKIPS"; then
      say "  건너뜀: $CLAUDE_DIR/skills/$n — 링크가 아닌 파일이 이미 있음 (직접 확인하세요)"
    elif [ "$LINK_OK" = 0 ]; then say "  복사: $CLAUDE_DIR/skills/$n ← $REPO/skills/$n (링크 권한 없음)"
    elif [ "$MODE" = copy ]; then say "  연결: $CLAUDE_DIR/skills/$n → $CLAUDE_DIR/harness/skills/$n"
    else say "  연결: $CLAUDE_DIR/skills/$n → $REPO/skills/$n"; fi
  done < "$WORK/skills.list"
  for r in $RETIRED; do
    if awk -F'\t' -v p="agents/$r.md" '$1 == "remove" && $3 == p { found = 1 } END { exit !found }' "$OPS"; then
      say "  지움 (예전 작업자): $CLAUDE_DIR/agents/$r.md"
    fi
  done
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if grep -q "^file${TAB}agents/$f${TAB}" "$SKIPS"; then say "  건너뜀: $CLAUDE_DIR/agents/$f — 하네스가 만들지 않은 파일이 이미 있음 (직접 확인하세요)"
    else say "  설치: $CLAUDE_DIR/agents/$f (+ 공통 규칙 · 가드 hook)"; fi
  done < "$WORK/agents.list"
  awk -F'\t' '$1 == "remove" && $2 != "dir" && ($3 ~ /^agents\// || $3 ~ /^skills\/[^\/]+$/ || $3 == "'"$STATE_FILE"'") { print $3 }' "$OPS" | while IFS= read -r cur; do
    case "$cur" in
      agents/harness-builder.md|agents/harness-builder-deep.md) ;;
      *) say "  지움 (내 수정에서 빠진 것): $CLAUDE_DIR/$cur" ;;
    esac
  done
  while IFS="$TAB" read -r path rec cur; do
    [ -n "$path" ] || continue
    say "  원본 바뀜: $path — 통째로 바꾼 파일의 원본이 달라졌습니다. 내 것을 그대로 쓰고 있습니다 (앱이나 /harness-setup 에서 고르세요)"
  done < <(sort "$ORIGINS")
  [ -n "$BK_ID" ] && [ "$BK_FILES" -gt 0 ] && say "  백업: $BK_DIR (덮어쓰거나 지운 파일 ${BK_FILES}개 — 되돌리기: bash install.sh --restore $BK_ID)"
  return 0
}

# ── 명령 ──
prepare_install() {  # 내 수정 읽기 → 합치기 → 계획. 문제가 있으면 여기서 끝낸다
  scan_custom
  [ ! -s "$PROBLEMS" ] || finish 2
  decide_mode
  stage_source
  [ ! -s "$PROBLEMS" ] || finish 2
  stage_agents
  [ ! -s "$PROBLEMS" ] || finish 2
  stage_slots
}

cmd_install() {
  prepare_install
  [ -d "$CLAUDE_DIR/agents" ] || RESTART=true
  build_plan
  [ ! -s "$PROBLEMS" ] || finish 2
  if [ "$DRY" = 1 ]; then print_plan_text; finish 0; fi
  acquire_lock
  RESTART=false; [ -d "$CLAUDE_DIR/agents" ] || RESTART=true
  build_plan  # 잠근 뒤 다시 — 그사이 바뀌었을 수 있다
  [ ! -s "$PROBLEMS" ] || finish 2
  apply_ops
  report_install
  if [ ! -s "$ITEMS" ] && [ "$DEVMODE" = true ] && [ ! -f "$REPO/config.local.json" ]; then
    if cp "$REPO/config.example.json" "$REPO/config.local.json"; then
      say "  설정 파일을 만들었습니다: $REPO/config.local.json — /harness-setup 으로 채우세요"
    fi
  fi
  say "완료. 스킬: /web-full · /web-lite · /desktop-app · /harness-resume · /harness-setup"
  if [ "$RESTART" = true ]; then
    say "※ 에이전트 폴더를 새로 만들었습니다. 열려 있는 Claude Code 를 다시 시작해야 작업자 에이전트가 보입니다."
  fi
  finish 0
}

cmd_check() {  # 설치된 작업자가 저장소(+ 내 수정)와 같은지만 본다
  prepare_install
  local diff=0 f t r
  : > "$OPS"; SAME=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    t="$CLAUDE_DIR/agents/$f"
    if [ ! -f "$t" ]; then say "빠짐: $f"; add_op add file "agents/$f"; diff=1
    elif ! cmp -s "$WORK/files/agents/$f" "$t"; then say "다름: $f"; add_op change file "agents/$f"; diff=1
    else SAME=$((SAME + 1)); fi
  done < "$WORK/agents.list"
  for r in $RETIRED; do
    if [ -f "$CLAUDE_DIR/agents/$r.md" ]; then say "남음 (예전 작업자): $r.md"; add_op remove file "agents/$r.md"; diff=1; fi
  done
  [ "$diff" = 0 ] && say "작업자: 저장소와 같음"
  finish "$diff"
}

cmd_uninstall() {
  : > "$ITEMS"
  local n f r cur names
  uninstall_plan() {
    : > "$OPS"; : > "$SKIPS"; SAME=0
    read_state
    # 하네스 폴더
    case "$(kind_of "$CLAUDE_DIR/harness")" in
      link) add_op remove link harness "$(readlink "$CLAUDE_DIR/harness")" ;;
      dir) if is_managed_dir "$CLAUDE_DIR/harness"; then remove_tree harness; else add_skip dir harness notOurs; fi ;;
      absent) ;;
      *) add_skip file harness notOurs ;;
    esac
    # 스킬 (저장소의 것 + 내 수정으로 만든 것)
    { for d in "$REPO"/skills/*/; do [ -d "$d" ] && basename "$d"; done; sed -n 's/^skill //p' "$WORK/state.prev"; } | sort -u > "$WORK/uninstall.skills"
    while IFS= read -r n; do
      [ -n "$n" ] || continue
      cur="$CLAUDE_DIR/skills/$n"
      case "$(kind_of "$cur")" in
        link) add_op remove link "skills/$n" "$(readlink "$cur")" ;;
        dir) if is_managed_dir "$cur"; then remove_tree "skills/$n"; else add_skip link "skills/$n" notOurs; fi ;;
      esac
    done < "$WORK/uninstall.skills"
    # 에이전트
    { for f in "$REPO"/agents/*.md; do [ -f "$f" ] && basename "$f"; done; sed -n 's/^agent //p' "$WORK/state.prev"; for r in $RETIRED; do echo "$r.md"; done; } | sort -u > "$WORK/uninstall.agents"
    while IFS= read -r n; do
      [ -n "$n" ] || continue
      cur="$CLAUDE_DIR/agents/$n"
      case "$(kind_of "$cur")" in
        link) add_op remove link "agents/$n" "$(readlink "$cur")" ;;
        file) add_op remove file "agents/$n" ;;
        absent) ;;
        *) add_skip file "agents/$n" notOurs ;;
      esac
    done < "$WORK/uninstall.agents"
    if [ -f "$CLAUDE_DIR/$STATE_FILE" ] && [ ! -L "$CLAUDE_DIR/$STATE_FILE" ]; then add_op remove file "$STATE_FILE"; fi
  }
  uninstall_report() {  # 예전 uninstall.sh 와 같은 순서 — 스킬 · 작업자 · 예전 작업자 · 하네스
    local path action type reason
    while IFS="$TAB" read -r path action type reason; do
      [ -n "$path" ] || continue
      case "$action" in
        remove) say "  지움: $CLAUDE_DIR/$path" ;;
        skip) say "  건너뜀: $CLAUDE_DIR/$path — 하네스가 만들지 않은 것이 있음 (직접 확인하세요)" ;;
      esac
    done < <(changes_rows | awk -F'\t' '
      $1 ~ /^(harness|skills\/[^\/]+)\/./ { next }
      { r = 4
        if ($1 ~ /^skills\//) r = 1
        else if ($1 ~ /^agents\/harness-builder(-deep)?\.md$/) r = 3
        else if ($1 ~ /^agents\//) r = 2
        else if ($1 == "harness") r = 5
        print r "\t" $0 }' | sort -t"$TAB" -k1,1n -k2,2 | cut -f2-)
  }
  if [ "$DRY" = 1 ]; then
    uninstall_plan
    if [ "$JSON" != 1 ]; then
      echo "claude-harness 지우기 미리보기 — 아무것도 쓰지 않았습니다"
      uninstall_report
      has_changes || echo "  (지울 것 없음)"
    fi
    finish 0
  fi
  acquire_lock
  uninstall_plan
  apply_ops
  uninstall_report
  [ -n "$BK_ID" ] && [ "$BK_FILES" -gt 0 ] && say "  백업: $BK_DIR (되돌리기: bash install.sh --restore $BK_ID)"
  say "완료."
  finish 0
}

case "$CMD" in
  restore) cmd_restore ;;
  uninstall) cmd_uninstall ;;
  check) cmd_check ;;
  install) cmd_install ;;
esac
