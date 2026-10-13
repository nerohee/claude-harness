#!/usr/bin/env bash
# 작업자 에이전트(harness-*) 전용 PreToolUse 가드 — 에이전트 앞머리 hooks 에서 부른다.
# 막는 것: git 커밋 · 푸시 · 이력 · 브랜치 조작, 배포 · 공개 설정 명령, 앱 서명 · 릴리스, .env · 서명 키 파일 만들기 · 고치기 (.env.example 같은 예시 파일은 허용).
# 막으면 exit 2 + stderr — 작업자는 이유를 보고 멈춰서 보고한다. jq 없이 bash · grep · sed 만 쓴다 (Windows Git Bash 에서도 돈다).

INPUT="$(cat)"

field() {  # field <이름> — 한 줄 JSON 에서 문자열 필드 값을 꺼낸다 (이스케이프는 그대로)
  printf '%s' "$INPUT" | sed -n 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"\(\([^"\\]\|\\.\)*\)".*/\1/p' | head -n 1
}

block() {
  echo "하네스 작업자 규칙으로 막음: $1 — 이 일은 메인 대화(사용자)가 한다. 하지 말고 보고서 \"남은 문제\"에 적어라." >&2
  exit 2
}

is_key_file() {  # 서명 키 · 인증서 (*.key, *.pfx, *.p12, *.p8)
  case "${1##*/}" in
    *.key|*.pfx|*.p12|*.p8) return 0 ;;
  esac
  return 1
}

is_env_file() {  # .env, .env.local, .env.production … (예시 파일 제외)
  local name="${1##*/}"; name="${name##*\\}"
  case "$name" in
    .env.example|.env.sample|.env.template|.env.*.example) return 1 ;;
    .env|.env.*) return 0 ;;
  esac
  return 1
}

TOOL="$(field tool_name)"

case "$TOOL" in
  Bash|PowerShell)
    CMD="$(field command)"
    GIT='(^|[^[:alnum:]_./-])git([[:space:]]+(-C|-c)[[:space:]]+[^[:space:]]+|[[:space:]]+--[a-z-]+(=[^[:space:]]+)?)*[[:space:]]+'
    if printf '%s' "$CMD" | grep -Eq "${GIT}(commit|push|merge|rebase|reset|cherry-pick|revert|tag|am|filter-branch|filter-repo)([[:space:]]|\$)"; then
      block "git 커밋 · 푸시 · 이력 변경"
    fi
    if printf '%s' "$CMD" | grep -Eq "${GIT}(branch[[:space:]]+(-[dDmMcC]|--delete|--move|--copy)|checkout[[:space:]]+(-b|-B|--orphan)|switch[[:space:]]+(-c|-C|--create|--orphan))"; then
      block "git 브랜치 조작"
    fi
    if printf '%s' "$CMD" | grep -Eq '(^|[^[:alnum:]_-])(vercel([[:space:]].*)?([[:space:]]--prod|[[:space:]]deploy)|netlify[[:space:]]+deploy|wrangler[[:space:]]+(deploy|publish|pages[[:space:]]+deploy)|firebase[[:space:]]+deploy|fly[[:space:]]+deploy|(npm|pnpm|yarn|bun)[[:space:]]+publish|gh[[:space:]]+(repo[[:space:]]+(edit|create|delete|rename|archive)|release[[:space:]]+(create|upload|edit)|pr[[:space:]]+merge|workflow[[:space:]]+run)|cargo[[:space:]]+publish)([[:space:]]|$)'; then
      block "배포 · 저장소 설정 변경"
    fi
    if printf '%s' "$CMD" | grep -Eq '(^|[^[:alnum:]_-])(tauri[[:space:]]+signer|signtool(\.exe)?[[:space:]]+sign|codesign|xcrun[[:space:]]+(notarytool|stapler))([[:space:]]|$)'; then
      block "앱 서명 · 공증 · 릴리스"
    fi
    if printf '%s' "$CMD" | grep -Eq '(>|>>|tee([[:space:]]+-a)?|cp([[:space:]]+-[a-zA-Z]+)*[[:space:]]+[^[:space:]]+|mv([[:space:]]+-[a-zA-Z]+)*[[:space:]]+[^[:space:]]+)[[:space:]]*([^[:space:]]*[/\\])?\.env(\.(local|development|production|test|staging)(\.local)?)?([[:space:];|&)]|$)'; then
      block ".env 쓰기"
    fi
    ;;
  Write|Edit|MultiEdit|NotebookEdit)
    FILE="$(field file_path)"; [ -n "$FILE" ] || FILE="$(field notebook_path)"
    if [ -n "$FILE" ] && is_env_file "$FILE"; then
      block ".env 만들기 · 고치기 (.env.example 에 가짜 값만 넣는다)"
    fi
    if [ -n "$FILE" ] && is_key_file "$FILE"; then
      block "서명 키 · 인증서 파일 쓰기"
    fi
    ;;
esac
exit 0
