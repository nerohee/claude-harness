# claude-harness

요구사항 마크다운 하나로 웹을 만들어 가는 Claude Code 하네스입니다. **질문하고 → 계획을 세우고 → 단계마다 검수를 받으며** 만듭니다.

- 계획 · 질문 · 검수: 메인 대화 (Opus · high)
- 구현: 작업자 에이전트 (Sonnet · medium / high)

## 스킬

| 명령 | 언제 | 질문 | 개념 노트(Vault) |
|---|---|---|---|
| `/web-full <요구사항.md>` | 제대로 된 웹사이트 | 개발 + 디자인, 깊게 | 남김 |
| `/web-lite <요구사항.md>` | 핵심 기능 하나 · 랜딩 페이지 | 꼭 필요한 것만 | 남기지 않음 |
| `/harness-setup [바꿀 것]` | 하네스 자체 설정 · 수정 | 원하는 변경 | - |

두 개발 스킬은 같은 방식으로 진행합니다 — 승인 게이트, 개발 서버 확인 뒤 시험, 작업 일지 · 개발 계획 · 질의 기록, 커밋 메시지 제안.

## 작업자

| 에이전트 | 모델 · 수준 | 맡는 일 |
|---|---|---|
| `harness-builder` | Sonnet · medium | 계획이 구체적인 구현 |
| `harness-builder-deep` | Sonnet · high | 인증 · 결제 · 데이터 이전 · 어려운 버그 |

계획 단계에서 작업마다 누가 맡을지 정해 개발 계획에 적습니다.

## 설치

```bash
git clone <이 저장소> ~/project/claude-harness
bash ~/project/claude-harness/install.sh
```

그다음 Claude Code 에서 `/harness-setup` 으로 개인 설정(대답 언어, Vault 경로 등)을 만듭니다. 설정은 `config.local.json` 에 저장되고 git 에 올라가지 않습니다.

- 세션 모델은 **Opus · 추론 high** 로 두고 쓰세요 (`/model`). 스킬이 시작할 때 확인합니다.
- `~/.claude/agents` 폴더가 처음 생겼다면 Claude Code 를 다시 시작해야 작업자가 보입니다.
- 지우기: `bash uninstall.sh` (링크와 복사한 에이전트만 지웁니다)

## 구조

```
skills/            web-full · web-lite · harness-setup
agents/            작업자 정의 (install.sh 가 ~/.claude/agents 로 복사)
shared/
  workflow.md          공통 진행 규칙 — 승인 · 실행 · 기록 · git · 공개 저장소
  questions-dev.md     개발 질문 (full / lite)
  questions-design.md  디자인 — 비전문가에게 묻는 법, 제작자가 정하는 것
  delegation.md        작업 지시서와 검수
  knowledge-capture.md 개념 노트 (web-full)
  templates/           docs 문서 틀
config.example.json  개인 설정 예시
```

## 프로젝트에 만들어지는 문서

```
docs/
  README.md
  01-planning/     plan.md · decisions.md
  02-development/  dev-plan.md (단계 · 담당 · 진행 로그)
  03-worklog/      YYYY-MM-DD.md
  04-communication/ 질의응답 · 검수 기록
```

저장소를 공개할 때는 `docs/` 를 올릴지 처음에 정합니다. 기본 권장은 코드만 공개입니다.
