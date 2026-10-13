---
name: web-lite
description: 요구사항 마크다운을 받아 핵심 기능 하나짜리 간단한 웹이나 랜딩 페이지를 만든다 — 꼭 필요한 개발 · 디자인 질문 → 짧은 기획 → 단계별 승인 → 구현 → 검수. 개념 노트(Raw Import)는 남기지 않는다. 사용자가 /web-lite 로 부를 때만 쓴다.
argument-hint: "[요구사항.md 경로]"
disable-model-invocation: true
model: opus
effort: high
---

# 간단한 웹 만들기 (web-lite)

요구사항: $ARGUMENTS

랜딩 페이지, 신청 양식, 계산기처럼 **핵심 기능 하나**에 집중한 작은 웹. 진행 방식은 web-full 과 같고, 질문 · 문서 · 시안이 가볍다.

## 먼저 읽기

1. `~/.claude/harness/config.local.json` (없으면 `config.example.json`)
2. `~/.claude/harness/shared/workflow.md` — 공통 규칙. **모든 단계에 적용된다.**
3. `~/.claude/harness/shared/questions-dev.md` 의 `lite` 질문, `questions-design.md` 의 ★ 질문
4. `~/.claude/harness/shared/delegation.md`

**하지 않는 것** — `knowledge-capture.md` 의 개념 노트. 사용자가 개념을 물으면 답만 하고 Vault 에는 남기지 않는다.

## 진행

### P0. 질문과 기획 (한 번에)
1. 요구사항을 한 문단으로 되짚고, 위험이 있으면 먼저 꺼낸다.
2. 개발 `lite` 질문 + 디자인 ★ 질문 — **두 묶음 안에** 끝낸다. 요구사항에 답이 있으면 건너뛴다.
3. 승인을 받고 문서를 만든다 (틀: `~/.claude/harness/shared/templates/`).
   - `docs/README.md`
   - `docs/01-planning/plan.md` — 결정은 이 안의 "결정" 절에 (decisions.md 는 만들지 않는다)
   - `docs/02-development/dev-plan.md` — 단계는 보통 2~4개
   - `docs/03-worklog/`, `docs/04-communication/` (질의 기록)
4. 기획을 짧게 요약해 승인을 받는다. **승인 전에는 코드를 쓰지 않는다.**

### P1~. 단계 실행
web-full 과 같다 — 소개 → 승인 → 맡기기 · 검수 → 개발 서버 확인 → 시험 → 기록 → 커밋 메시지 제안.

- 첫 화면 시안은 **2개까지.** 요구사항에 디자인이 분명하면 시안 없이 바로.
- 작업자는 대부분 `ui` 로 충분하다. 시안이 필요하면 `designer`(2개까지), 결제 · 외부 연동은 `system`, 단순 정리는 `helper`.
- `reviewer` 는 결제 · 개인정보를 다룰 때만 마감 점검에.
- 시험은 프로젝트 크기에 맞게 — 빌드, 휴대폰 폭 화면, 접근성 기본(대비 · 키보드 · 대체 글).

### 마감
비밀값 · 개인정보 점검, 휴대폰 화면 확인, 짧은 README.
