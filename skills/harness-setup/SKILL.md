---
name: harness-setup
description: claude-harness(web-full · web-lite 와 작업자 에이전트) 자체를 설정하거나 고친다 — 처음 설치한 PC 의 개인 설정 만들기, 질문 · 규칙 · 템플릿 · 작업자 모델과 추론 수준 바꾸기. 사용자가 /harness-setup 으로 부를 때만 쓴다.
argument-hint: "[바꾸고 싶은 것 (비우면 현재 설정을 보여 주고 묻는다)]"
disable-model-invocation: true
model: opus
effort: high
---

# 하네스 설정 (harness-setup)

요청: $ARGUMENTS

## 먼저 파악하기

1. `~/.claude/harness` 가 가리키는 실제 저장소 위치를 확인한다 (`readlink -f ~/.claude/harness`). 이하 "저장소".
2. 저장소의 `README.md`, `CHANGELOG.md`, `config.example.json`, `config.local.json`(있으면) 을 읽는다.
3. 설치 상태를 확인한다 — `~/.claude/skills/{web-full,web-lite,harness-setup}` 링크, `~/.claude/agents/harness-builder*.md`.
   - 빠졌거나 저장소 쪽이 더 새것이면 `bash <저장소>/install.sh` 를 다시 돌리도록 제안한다.

## A. 처음 설정 (config.local.json 이 없거나 비었을 때)

한 묶음으로 묻는다. 권장안을 먼저.

| 항목 | 질문 | 기본 |
|---|---|---|
| `language` | 대답 언어 | `ko` |
| `vault.path` | Obsidian Vault 경로 (개념 노트를 남길 곳). 없으면 비워 둔다 | 비움 |
| `vault.rawImportDir` | Vault 안 Raw Import 폴더 | `00 Inbox/Raw Import/Personal Study` |
| `docsDir` | 프로젝트 문서 폴더 | `docs` |
| `commitPolicy` | `propose-only`(커밋은 내가) / `agent-commits`(푸시만 내가) | `propose-only` |

답을 받아 `config.local.json` 을 쓴다. 이 파일은 git 에 올라가지 않는다(개인 경로라서). Vault 경로를 받았으면 그 폴더가 실제로 있는지 확인한다.

## B. 하네스 고치기

1. **요청을 하네스 기준으로 정리한다** — 무엇을 바꾸고 싶은지, 어느 파일이 바뀌는지.

   | 바꾸고 싶은 것 | 파일 |
   |---|---|
   | 진행 방식 · 승인 · 기록 · git 규칙 | `shared/workflow.md` |
   | 개발 질문 | `shared/questions-dev.md` |
   | 디자인 질문 · 디자인 원칙 | `shared/questions-design.md` |
   | 맡기기 · 검수 방식 | `shared/delegation.md` |
   | 개념 노트 | `shared/knowledge-capture.md` |
   | 문서 틀 | `shared/templates/*.md` |
   | 스킬별 단계 | `skills/<이름>/SKILL.md` |
   | 작업자 모델 · 추론 수준 · 역할 | `agents/harness-builder*.md` 앞머리(`model`, `effort`) |
   | 계획 담당 모델 | `config` 의 `planner` + 각 SKILL.md 앞머리 `model` · `effort` |
   | 새 스킬 추가 | `skills/<새 이름>/SKILL.md` + README 표 |

2. **바꿀 내용을 짧게 보이고 승인을 받는다** — 무엇을 / 어느 파일 / 기존 프로젝트에 영향이 있는지.
3. 승인되면 저장소 파일을 고친다. 개인 경로 · 비밀값은 저장소 파일에 쓰지 않는다 (`config.local.json` 에만).
4. 에이전트 파일을 바꿨으면 `install.sh` 를 다시 돌린다 (에이전트는 복사 방식이라). 새 스킬을 추가했어도 다시 돌린다.
5. `CHANGELOG.md` 맨 위에 날짜와 한 줄을 적는다.
6. 하네스 저장소의 커밋 메시지를 제안한다 (workflow §5).
7. 에이전트 폴더를 처음 만들었거나 스킬 목록이 안 바뀌어 보이면 Claude Code 를 다시 시작하라고 알린다.

## 작업자 모델 · 수준을 바꿀 때 판단 기준

- 계획이 구체적인 구현이 대부분이면 `harness-builder` = `sonnet` · `medium` 이 속도와 비용의 균형이 좋다.
- 검수에서 같은 실수가 반복되면 그 종류의 작업을 `deep`(`high`)으로 옮기거나, 지시서 항목을 늘린다 — 모델부터 올리지 않는다.
- `effort` 값: `low` · `medium` · `high` · `xhigh` · `max`. `model` 값: `sonnet` · `opus` · `haiku` · `inherit` 또는 전체 모델 ID.
