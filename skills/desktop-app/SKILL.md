---
name: desktop-app
description: 요구사항 마크다운을 받아 데스크톱 앱(Tauri 2)을 만든다 — 규모는 요구사항에 맞춰 정한다. 개발 · 디자인 질문 → 개발 환경 확인 → 기획 → 단계별 승인 → 작업자 위임 구현 → 검수 → 설치본 출시. 작업 중 나온 개념은 Vault Raw Import 에 노트로 남긴다. 사용자가 /desktop-app 으로 부를 때만 쓴다.
argument-hint: "[요구사항.md 경로]"
disable-model-invocation: true
model: opus
effort: high
---

# 데스크톱 앱 만들기 (desktop-app)

요구사항: $ARGUMENTS

Tauri 2 로 만든다 — 화면은 웹 기술, 시스템 쪽은 Rust. 질문하고 · 계획을 세우고 · 단계마다 검수를 받으며 만든다.

## 먼저 읽기

아래를 순서대로 읽는다. 경로의 `~` 는 사용자 홈 디렉터리다.

1. `~/.claude/harness/config.local.json` (없으면 `~/.claude/harness/config.example.json`)
2. `~/.claude/harness/shared/workflow.md` — 공통 규칙. **이 스킬의 모든 단계에 적용된다.**
3. `~/.claude/harness/shared/desktop/` 전부 — `questions.md`, `stack.md`, `design.md`, `testing.md`
4. `~/.claude/harness/shared/questions-dev.md` 의 "목적과 사람" · "기능" 표 ("운영" 표는 웹 전용 — 대신 `desktop/questions.md`)
5. `~/.claude/harness/shared/questions-design.md` (데스크톱에서 바뀌는 것은 `desktop/design.md`)
6. `~/.claude/harness/shared/delegation.md`, `knowledge-capture.md`

요구사항 경로가 비었으면 workflow §0-5 (대화로 받아 적기 / 틀 만들어 주기 / 경로 알려 주기). 이미 진행 중인 프로젝트면 workflow §0-4 를 따른다.

## 규모 맞추기

규모를 미리 나누지 않는다. 요구사항을 읽고 **누가 쓰나 · 기능 수 · 데이터와 외부 연동 · OS 연동** 을 보고 아래 범위 안에서 정한다. 첫 보고에서 판단한 규모와 근거를 한 줄로 알린다.

| 항목 | 작은 쪽 (예: 나만 쓰는 트레이 도구) | 큰 쪽 (예: 여러 사람에게 배포하는 업무 앱) |
|---|---|---|
| 질문 | 두 묶음 안 — `항상` 질문 위주 | 필요한 만큼 — `해당하면` 질문까지 |
| 디자인 질문 | ★ 만 | 전부 |
| 결정 기록 | `plan.md` 안 "결정" 절 | `decisions.md` |
| 단계 | 2~4개 | 필요한 만큼 |
| 첫 화면 시안 | 0~2개 (요구사항에 디자인이 분명하면 없이) | 2~3개 |
| 시험 | 정적 검사 · 단위 시험 · 설치본 직접 확인 | + 전체 흐름(E2E) |
| 출시 기록 | 개발 계획 진행 로그 한 줄 | `release.md` |

- 진행 중 요구가 커지거나 줄면 **개발 계획을 먼저 고치고** 승인을 받는다 (workflow §2). 문서는 그때 더한다.
- 개념 노트는 규모와 상관없이 남긴다 (`knowledge-capture.md`, `vault.path` 가 비어 있으면 건너뜀).

## 진행

### P0-1. 요구사항 읽고 첫 보고
- 요구사항을 **한 문단으로 되짚는다** — 무엇을, 누구에게, 어디까지.
- 판단한 규모와 근거 한 줄.
- 요구사항에서 보이는 위험을 먼저 꺼낸다 (`desktop/questions.md` "제작자가 판단해 먼저 꺼낼 것").

### P0-2. 질문 — 개발
`desktop/questions.md` + `questions-dev.md` "목적과 사람" · "기능" 중 요구사항에 답이 없는 것만. **누가 쓰나 · 대상 OS 를 첫 묶음 맨 앞에.** 묻는 형식은 workflow §2 "묻는 형식" — 선택지 A · B · C … + 기타, 권장안을 첫 번째에, 한 묶음 4개까지.

### P0-3. 질문 — 디자인
`questions-design.md` §1 (규모에 맞게) — 바뀌는 질문은 `desktop/design.md` §1. 답을 받으면 방향을 한 단락으로 정리해 되묻는다.

### P0-4. 개발 환경과 프로젝트 폴더
`desktop/stack.md` "개발 환경" 에 따라 대상 OS 에 맞는 개발 위치를 정하고, 도구가 있는지 확인한다. 없는 도구는 설치 명령만 드리고 사용자가 설치한다. **환경이 맞지 않으면 다음으로 넘어가지 않는다.**

### P0-5. 문서 골격과 질의 기록
승인을 받고 `docs/` 를 만든다 (틀: `~/.claude/harness/shared/templates/`).
- `docs/README.md`, `01-planning/plan.md`, `02-development/dev-plan.md` · `handoff.md` · `briefs/`, `03-worklog/`, `04-communication/`
- 프로젝트 루트 `CLAUDE.md` 에 이어 하기 안내를 넣을지 묻는다 (workflow §4 "이어 하기 준비").
- 큰 쪽이면 `01-planning/decisions.md`, 배포하는 앱이면 `02-development/release.md` 도.
- 지금까지의 질의응답을 `04-communication/YYYY-MM-DD-requirements-clarification.md` 로.
- 저장소를 공개한다고 했고 `docs/` 는 비공개로 하기로 했으면, `.gitignore` 에 `/docs/` 를 넣고 비공개 백업 방법을 제안한다.

### P0-6. 기획
- `plan.md` — 무엇을 · 범위 밖 · 사람 · 기능 · 구조와 기술 · 창 · 디자인 방향 · 위험.
  - 구조와 기술에 **앱 식별자 · 데이터 위치 · 여는 권한 · 서명과 업데이트 방식** 을 적는다 (`desktop/stack.md`).
- 결정마다 D-번호.
- `dev-plan.md` — 단계(P1…)마다 목표 · 작업 · 완료 기준 · 확인 명령 · **담당(designer / ui / system / tester / helper / reviewer / 직접)** — delegation.md "담당 정하기".
  - P1 은 보통 "앱 뼈대" — 프로젝트 만들기, 식별자, 검사 명령, 최소 권한, IPC 한 곳 모으기 (`desktop/stack.md` "구조 규칙").
  - 배포하는 앱이면 마지막 단계는 "출시" — 설치본 · 서명 · 업데이트 · 설치 시험.
- 시안이 필요한 창을 단계 안에 표시한다.

### P0-7. 기획 검수
기획을 짧게 요약해 승인을 받는다. 고칠 점이 나오면 문서를 고치고 다시. **승인 전에는 코드를 쓰지 않는다.**

### P1~. 단계 실행 (반복)
1. 다음 단계를 workflow §2 의 네 가지로 소개 → 승인. **권한(capabilities)을 새로 여는 단계면 무엇을 왜 여는지 함께 보인다.**
2. delegation.md 에 따라 작업 지시서를 써서 맡긴다 → 직접 검수 (권한 · 시스템 호출 변경은 `desktop/stack.md` "권한과 보안" 기준으로 따로 본다). 화면은 `designer` → 사용자 선택 → `ui` → `designer` 디자인 검수 순서, 앱 권한 · 업데이트를 바꾼 단계 뒤에는 `reviewer`.
3. 화면 · 동작이 바뀌는 작업이면 실행 확인을 요청한다 — 띄우는 명령(`npm run tauri dev`), 볼 것 → 의견 반영 → 괜찮다고 하면 전체 시험 (`desktop/testing.md`).
4. 진행 로그 · 작업 일지 · 결정 기록 · `handoff.md` 를 갱신한다 (workflow §4).
5. 커밋 메시지를 제안한다 (저장소 이름과 함께).
6. 그사이 설명한 개념은 knowledge-capture 에 따라 노트로 남긴다.

### 출시 (배포하는 앱)
`desktop/stack.md` "설치본 · 서명 · 업데이트" 와 `desktop/testing.md` "설치본 확인" 을 따른다.
- 버전을 올리고, 설치본을 만들고, **깨끗한 환경에서 설치 · 첫 실행 · 업데이트 · 제거** 를 사용자가 확인한다.
- 서명 · 업데이트 서명 키 · GitHub 릴리스 공개는 사용자가 한다. 명령과 순서만 드린다.
- 결과를 `release.md` 에 남긴다.

### 마감 (공개 전)
- 아래 점검은 `reviewer` 에게 맡기고, 찾은 것을 직접 확인한다.
- 보안 — 열린 권한이 쓰는 기능과 맞는가, CSP, 앱 안에 비밀값이 없는가, 저장소 이력 전체 (workflow §6).
- 접근성 — 키보드만으로 전부, 대비, 화면 배율 150% · 200%.
- 성능 — 시작 시간, 메모리, 설치본 크기, 무거운 일 중 화면 멈춤.
- 데이터 — 저장 위치, 앱을 지운 뒤 남는 것, 백업 · 내보내기.
- 루트 `README.md` — 무엇인가 · 화면 · 설치 · 개발 실행 · 빌드 방법 · 기술. 회사 · 고객 내부 사정은 쓰지 않는다.
- 남은 일을 개발 계획 끝에 "공개 이후 남은 일"로.
