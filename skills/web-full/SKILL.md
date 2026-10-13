---
name: web-full
description: 요구사항 마크다운을 받아 제대로 된 웹사이트를 만든다 — 개발 · 디자인 질문 → 기획 → 단계별 승인 → 작업자 위임 구현 → 검수. 작업 중 나온 개념은 Vault Raw Import 에 노트로 남긴다. 사용자가 /web-full 로 부를 때만 쓴다.
argument-hint: "[요구사항.md 경로]"
disable-model-invocation: true
model: opus
effort: high
---

# 정식 웹 만들기 (web-full)

요구사항: $ARGUMENTS

질문하고 · 계획을 세우고 · 단계마다 검수를 받으며 만든다.

## 먼저 읽기

아래를 순서대로 읽는다. 경로의 `~` 는 사용자 홈 디렉터리다.

1. `~/.claude/harness/config.local.json` (없으면 `~/.claude/harness/config.example.json`)
2. `~/.claude/harness/shared/workflow.md` — 공통 규칙. **이 스킬의 모든 단계에 적용된다.**
3. `~/.claude/harness/shared/questions-dev.md`, `questions-design.md`
4. `~/.claude/harness/shared/delegation.md`
5. `~/.claude/harness/shared/knowledge-capture.md`

요구사항 경로가 비었으면 workflow §0-5 (대화로 받아 적기 / 틀 만들어 주기 / 경로 알려 주기). 이미 진행 중인 프로젝트면 workflow §0-4 를 따른다.

## 진행

### P0-1. 요구사항 읽고 첫 보고
- 요구사항을 읽고 **한 문단으로 되짚는다** — 무엇을, 누구에게, 어디까지.
- 요구사항에서 보이는 위험을 먼저 꺼낸다 (questions-dev "제작자가 판단해 먼저 꺼낼 것").
- 프로젝트 폴더 위치를 확인한다 (지금 폴더 / 새 폴더).

### P0-2. 질문 — 개발
questions-dev 의 `full` 질문 중 요구사항에 답이 없는 것만. 묶음당 5~7개, 선택지는 권장안 먼저.

### P0-3. 질문 — 디자인
questions-design §1 전부. 답을 받으면 방향을 한 단락으로 정리해 되묻는다. 레퍼런스 보드 · 시안은 기획 승인 뒤 첫 화면 단계에서 `designer` 에게 맡긴다.

### P0-4. 문서 골격과 질의 기록
승인을 받고 `docs/` 를 만든다 (틀: `~/.claude/harness/shared/templates/`).
- `docs/README.md`, `01-planning/plan.md`, `01-planning/decisions.md`, `02-development/dev-plan.md` · `handoff.md` · `briefs/`, `03-worklog/`, `04-communication/`
- 프로젝트 루트 `CLAUDE.md` 에 이어 하기 안내를 넣을지 묻는다 (workflow §4 "이어 하기 준비").
- 지금까지의 질의응답을 `04-communication/YYYY-MM-DD-requirements-clarification.md` 로.
- 저장소를 공개한다고 했고 `docs/` 는 비공개로 하기로 했으면, `.gitignore` 에 `/docs/` 를 넣고 비공개 백업 방법을 제안한다.

### P0-5. 기획
- `plan.md` — 무엇을 · 범위 밖 · 사람 · 기능 · 구조와 기술 · 화면 · 디자인 방향 · 위험.
- `decisions.md` — 기술 선택마다 D-번호.
- `dev-plan.md` — 단계(P1…)마다 목표 · 작업 · 완료 기준 · 확인 명령 · **담당(designer / ui / system / tester / helper / reviewer / 직접)** — delegation.md "담당 정하기".
- 디자인은 시안이 필요한 화면을 단계 안에 표시한다 (첫 화면은 보통 시안 2~3개).

### P0-6. 기획 검수
기획을 짧게 요약해 승인을 받는다. 고칠 점이 나오면 문서를 고치고 다시. **승인 전에는 코드를 쓰지 않는다.**

### P1~. 단계 실행 (반복)
1. 다음 단계를 workflow §2 의 네 가지로 소개 → 승인.
2. delegation.md 에 따라 작업 지시서를 써서 맡긴다 → 직접 검수. 화면은 `designer` → 사용자 선택 → `ui` → `designer` 디자인 검수 순서.
3. 화면 작업이면 개발 서버 확인을 요청 → 의견 반영 → 괜찮다고 하면 전체 시험.
4. 진행 로그 · 작업 일지 · 결정 기록 · `handoff.md` 를 갱신한다 (workflow §4).
5. 커밋 메시지를 제안한다 (저장소 이름과 함께).
6. 그사이 설명한 개념은 knowledge-capture 에 따라 노트로 남긴다.

### 마감 (공개 전)
- 보안 · 비밀값 · 개인정보 (이력 전체), 접근성, 휴대폰 화면, 성능, 검색 노출(사이트맵 · 정식 주소 · 메타) 점검 — `reviewer` 에게 맡기고, 찾은 것을 직접 확인한다.
- 루트 `README.md` — 무엇인가 · 화면 · 구조 · 실행 방법 · 기술. 회사 · 고객 내부 사정은 쓰지 않는다.
- 남은 일을 개발 계획 끝에 "공개 이후 남은 일"로.
