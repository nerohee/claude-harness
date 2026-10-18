#!/usr/bin/env bash
# claude-harness 제거 — install.sh 가 만든 링크 · 복사본 · 복사한 에이전트만 지운다 (내 수정으로 만든 에이전트 · 스킬 포함).
# 저장소 · 내 수정 폴더 · 프로젝트 문서는 그대로. 지우기 전에 백업을 남긴다 (되돌리기: bash install.sh --restore <번호>).
#   bash uninstall.sh [--plan] [--json]     (install.sh --uninstall 과 같다)
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/install.sh" --uninstall "$@"
