---
name: harness-resume
description: claude-harness(web-full · web-lite · desktop-app)로 진행하던 프로젝트를 끊긴 곳에서 이어 간다 — 토큰 · 사용량 한도로 멈춘 뒤, 새 세션에서, 대화가 요약된 뒤. docs/02-development/handoff.md 를 읽고 어느 스킬의 어느 단계였는지, 작업자가 어디까지 했는지 확인한 뒤 다음 할 일을 보고하고 승인을 기다린다. 사용자가 /harness-resume 으로 부를 때만 쓴다.
argument-hint: "[프로젝트 폴더 (비우면 지금 폴더)]"
disable-model-invocation: true
model: opus
effort: high
---

# 이어 하기 (harness-resume)

대상 폴더: $ARGUMENTS (비었으면 지금 폴더)

진행 상태는 대화가 아니라 파일에 있다 — `handoff.md`, 지시서(`briefs/`), `dev-plan.md`, 작업 일지. 이 파일들만 보고 이어 간다.

## 1. 찾기

`~/.claude/harness/config.local.json` 의 `docsDir`(기본 `docs`) 아래 `02-development/handoff.md` 를 찾는다.

- **있으면** — 스킬 · 요구사항 · 단계 · 상태 · 진행 중인 작업 · 기다리는 것을 읽는다.
- **없고 `dev-plan.md` 만 있으면** — 이어 하기 메모가 생기기 전에 시작한 프로젝트다. 진행 로그 · 최근 작업 일지로 상태를 짐작해 보고하고, 승인을 받으면 `handoff.md` 를 만든다 (틀: `~/.claude/harness/shared/templates/handoff.md`). 스킬을 모르겠으면 묻는다.
- **둘 다 없으면** — 하네스로 진행한 프로젝트가 아니다. 프로젝트 폴더를 묻는다.

## 2. 규칙 다시 읽기

새 세션이거나 대화가 요약돼서 규칙이 빠져 있을 수 있다. `handoff.md` 의 스킬 → `~/.claude/harness/skills/<스킬>/SKILL.md` 를 읽고, 그 "먼저 읽기" 의 파일들을 그대로 읽는다. 모델 확인(workflow §0-2)도 한다.

## 3. 끊긴 지점 확인

`~/.claude/harness/shared/workflow.md` §8 "이어 갈 때" 를 따른다 — 상태별로 지시서 체크 표시 · git 상태 · 확인 명령을 보고, `handoff.md` 와 실제가 다르면 짐작하지 않고 묻는다.

## 4. 보고하고 기다리기

짧게:

- 프로젝트 · 스킬 · 단계
- 끊긴 지점과 확인한 것 (예: "목록 화면 작업이 5개 항목 중 3개까지 됨, 타입 검사 통과")
- 다음 할 일 — 고를 것이 있으면 권장안을 첫 번째에

승인을 받으면 그 스킬의 진행을 그대로 이어 간다. 스킬을 다시 부를 필요는 없다.
