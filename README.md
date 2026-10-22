# claude-harness

요구사항 마크다운 하나로 웹과 데스크톱 앱을 만들어 가는 Claude Code 하네스입니다. **질문하고 → 계획을 세우고 → 단계마다 검수를 받으며** 만듭니다.

- 계획 · 질문 · 최종 검수: 메인 대화 (Opus · high) — 오케스트레이터
- 디자인 · 구현 · 시험 · 점검: 작업자 에이전트 6종

## 스킬

| 명령 | 언제 | 질문 | 개념 노트(Vault) |
|---|---|---|---|
| `/web-full [요구사항.md]` | 제대로 된 웹사이트 | 개발 + 디자인, 깊게 | 남김 |
| `/web-lite [요구사항.md]` | 핵심 기능 하나 · 랜딩 페이지 | 꼭 필요한 것만 | 남기지 않음 |
| `/desktop-app [요구사항.md]` | 데스크톱 앱 (Tauri 2) — 규모는 요구사항에 맞춰 | 요구사항에 맞게 | 남김 |
| `/thread-draft [날짜]` | 작업 일지로 스레드 글 초안 — 내 말투 · 이미지 추천 · 공개 전 거르기 (게시는 직접) | 이야깃거리 고르기 | - |
| `/harness-resume [프로젝트 폴더]` | 끊긴 작업 이어 하기 (토큰 · 사용량 한도, 새 세션) | - | - |
| `/harness-setup [바꿀 것]` | 하네스 자체 설정 · 수정 | 원하는 변경 | - |

요구사항은 자유 형식 마크다운이면 됩니다. 아직 없으면 경로 없이 스킬을 부르세요 — 대화로 받아 적어 `requirements.md` 를 만들어 주거나, 쓰기 쉬운 틀을 만들어 줍니다.

개발 스킬은 모두 같은 방식으로 진행합니다 — 승인 게이트, 실행 확인(웹은 개발 서버, 앱은 개발 실행) 뒤 시험, 작업 일지 · 개발 계획 · 질의 기록, 커밋 메시지 제안.

## 작업자

| 에이전트 | 담당 표기 | 모델 · 수준 | 한 줄 소개 |
|---|---|---|---|
| 메인 대화 | `직접` | Opus · high | 사용자와 대화하는 유일한 창구 — 기획 · 지휘 · 지시 · 최종 검수 · 기록 |
| `harness-designer` | `designer` | Opus · high | 레퍼런스를 꿰고 있는 아트 디렉터 — 방향 · 토큰 · 시안 · 디자인 검수 |
| `harness-builder-ui` | `ui` | Sonnet · medium | 시안을 그대로 옮기는 화면 구현자 |
| `harness-builder-system` | `system` | Sonnet · high | 의심 많은 시스템 엔지니어 — 보안 · 데이터 · 앱 권한 · 어려운 버그 |
| `harness-tester` | `tester` | Sonnet · medium | 깨뜨리려고 덤비는 시험 작성자 |
| `harness-helper` | `helper` | Haiku · low | 빠르고 정확한 정리 담당 |
| `harness-reviewer` | `reviewer` | Opus · high | 고치지 않고 찾기만 하는 감사관 (읽기 전용) |

계획 단계에서 작업마다 누가 맡을지 정해 개발 계획에 적습니다. 화면은 `designer`(시안) → 사용자 선택 → `ui`(구현) → `designer`(디자인 검수) 순서로 갑니다. 작업자는 사용자와 직접 이야기하지 않고 메인에게만 보고합니다.

### 작업자 프로필

| | 성격 | 잘하는 것 | 원칙 | 하지 않는 것 |
|---|---|---|---|---|
| designer | 취향이 분명하고 과감함. 무난한 안보다 기억에 남는 안 | 레퍼런스 조사(HIG · Fluent 2 · Material 3 · Linear · Stripe …), 콘셉트 · 토큰, 서로 다른 시안, 스크린샷 비교 | 레퍼런스는 링크와 "가져온 것"까지. 기준(대비 · 글자 크기 · 키보드) 위에서 창의적으로 | 베끼기(로고 · 그림 · 문구), "AI 티" 디자인, 사용자에게 직접 질문, 서비스 로직 |
| ui | 꼼꼼하고 시안에 충실함 | 컴포넌트, 화면 상태(빈 · 로딩 · 오류), 반응형 · 최소 창 크기, 키보드 · 접근성 | 토큰만 쓴다. 시안 없는 화면은 기존 패턴대로 | 디자인을 새로 정하기, 앱 권한 건드리기 |
| system | 의심이 많음 — "중간에 실패하면? 두 번 누르면?" | API · DB · 인증 · 결제 · 데이터 이전 · Rust · 앱 권한 · 업데이트 · 어려운 버그 · 성능 | 끝까지 읽고 실패 경우부터. 버그는 재현으로 원인 확인. 권한은 최소로 | 지시서에 없는 권한 · 구조 변경 |
| tester | 앱을 깨뜨리고 싶어 함 | 단위 · 화면 · 전체 흐름 시험, 버그 재현 시험 | 경계 · 실패부터. 실패하면 앱 쪽 버그로 보고 | 앱 코드 고치기, 시험 건너뛰기 · 지우기 |
| helper | 빠르고 기계적이고 정확함 | 문서 정리, 이름 바꾸기, 반복 수정 | 판단이 필요하면 바로 멈추고 보고 | 지시서에 없는 정리 · 개선 |
| reviewer | 냉정하고 근거 중시 | 보안 · 비밀값 · 앱 권한 · 데이터 손실 · 접근성 · 성능 · 시험 공백 | 심각도 순, "어떤 상황에서 무엇이 틀리나"와 함께. 확실 / 가능성 구분 | 고치기(읽기 전용), 취향 · 문체 지적 |

designer 는 웹 검색 · 브라우저 스크린샷을 기본으로 쓰고, 연결돼 있으면 Figma, 설치돼 있으면 디자인 스킬도 씁니다. 자세한 지시는 `agents/harness-*.md`.

### 작업자 고치기 · 늘리기

`/harness-setup 작업자 …` 로 합니다 (예: `/harness-setup 작업자 designer 성격 바꾸기`). 작업자 하나를 바꾸면 delegation.md · README · 설정까지 같이 바뀌어서, 한 곳에서 체크리스트대로 고칩니다.

- 작업자 파일에는 그 작업자만의 것만 있습니다. 모든 작업자에게 같은 규칙(`agents/_common/rules.md`)과 가드 hook(`agents/_common/hooks.yml`)은 설치할 때 붙습니다.
- Claude Code 의 `/agents` 나 `~/.claude/agents/` 에서 직접 고치지 마세요 — 다음 설치 때 덮어써집니다. `bash install.sh --check` 로 설치본이 저장소와 같은지 볼 수 있습니다.

작업자에게는 가드 hook(`hooks/builder-guard.sh`)이 걸려 있어 git 커밋 · 푸시 · 브랜치 조작, 배포 · 저장소 설정 명령, 앱 서명 · 릴리스 공개, `.env` · 서명 키 파일 쓰기를 막습니다 (`.env.example` 은 허용). 메인 대화에는 걸리지 않습니다.

## 끊겼을 때 이어 하기

토큰이나 사용량 한도로 작업이 멈춰도, 진행 상태가 대화가 아니라 파일에 남아 있어 그대로 이어 갑니다.

- `docs/02-development/handoff.md` — 이어 하기 메모. 메인이 작업을 **맡기기 직전**, 돌아온 직후, 사용자 답을 기다릴 때, 단계가 끝날 때 갱신합니다.
- `docs/02-development/briefs/` — 작업 지시서 파일. 작업자가 항목을 끝낼 때마다 `[x]` 로 표시해서, 일하던 중에 끊겨도 어디까지 했는지 남습니다.
- 새 세션에서 `/harness-resume` → 어느 스킬의 어느 단계였는지, 작업자가 어디까지 했는지 확인하고 다음 할 일을 보고합니다.
- 프로젝트 `CLAUDE.md` 에 안내 두 줄을 넣어 두면(처음에 묻습니다) "이어서 하자" 만으로도 이어집니다.
- 단계가 끝날 때마다 새 세션으로 시작해도 됩니다 — 잃는 것이 없고 토큰을 덜 씁니다.

## 설치

```bash
git clone https://github.com/nerohee/claude-harness.git ~/project/claude-harness
bash ~/project/claude-harness/install.sh
```

Linux · WSL · macOS 모두 같은 명령입니다 (macOS 기본 bash 로 됩니다).

그다음 Claude Code 에서 `/harness-setup` 으로 개인 설정(대답 언어, Vault 경로 등)을 만듭니다. 설정은 `config.local.json` 에 저장되고 git 에 올라가지 않습니다.

- 세션 모델은 **Opus · 추론 high** 로 두고 쓰세요 (`/model`). 스킬이 시작할 때 확인합니다.
- `~/.claude/agents` 폴더가 처음 생겼다면 Claude Code 를 다시 시작해야 작업자가 보입니다.
- 지우기: `bash uninstall.sh` (하네스가 만든 링크 · 복사본 · 복사한 에이전트만 지웁니다 — 지우기 전에 백업을 남깁니다)

### 옵션 · 미리보기 · 백업

`install.sh` 는 덮어쓰거나 지우기 전에 `~/.claude-harness/backups/<날짜시각>/` 에 그 파일들과 목록(manifest)을 남깁니다. 하네스와 상관없는 `~/.claude` 파일(설정 · 기록 · 인증 · 플러그인 등)은 읽지도 백업하지도 않습니다.

| 명령 | 하는 일 |
|---|---|
| `bash install.sh --plan` | 설치하지 않고 계획만 — 새로 생김 · 바뀜 · 지워짐 · 건너뜀(하네스가 만들지 않은 것이 있음) · 원본 바뀜. 아무것도 쓰지 않습니다 |
| `bash install.sh --check` | 설치된 작업자가 저장소(+ 내 수정)와 같은지만 봅니다 (다르면 종료 코드 1) |
| `bash install.sh --backups` | 백업 목록 |
| `bash install.sh --restore <번호>` | 고른 백업으로 되돌립니다 (설치가 새로 만든 것은 지우고, 덮어쓴 것은 돌려놓습니다). `--plan` 을 붙이면 미리보기 |
| `bash install.sh --uninstall` | `uninstall.sh` 와 같습니다 (`--plan` 으로 미리보기, 되돌릴 수 있음) |
| `--json` | 사람용 출력 대신 JSON 한 줄 — 앱이 읽습니다 (모양 · 종료 코드: [shared/app-contract.md](shared/app-contract.md)) |

위치는 환경 변수로 바꿉니다: `CLAUDE_CONFIG_DIR`(기본 `~/.claude`), `CLAUDE_HARNESS_HOME`(기본 `~/.claude-harness` — `repo/` 원본 · `custom/` 내 수정 · `backups/`). 이미 `~/.claude/harness` 가 다른 저장소를 가리키고 있으면 출력에 "개발자 모드" 로 표시합니다 (그 저장소가 원본).

### 내 수정 (`~/.claude-harness/custom/`)

원본(이 저장소)은 고치지 않고, 바꾸고 싶은 것을 `custom/` 에 둡니다. 설치가 원본 위에 겹쳐서 `~/.claude` 에 만듭니다 — 내 수정이 하나라도 있으면 **원본 + 내 수정을 합친 복사**로, 없으면 지금처럼 링크로 설치합니다.

| 하고 싶은 것 | 어떻게 |
|---|---|
| 모델 · 수준만 바꾸기 | `custom/agents/harness-builder-ui.values.yml` — `effort: high` 처럼 한 줄씩 |
| 지시를 덧붙이기 | `custom/agents/harness-builder-ui.append.md` — 원본 끝에 붙습니다 |
| 새 에이전트 · 스킬 | `custom/agents/<이름>.md`, `custom/skills/<이름>/SKILL.md` |
| 파일 통째로 바꾸기 | 같은 경로에 파일 + `<파일>.origin` (만들 때의 원본 해시 — `install.sh --origin-hash <경로>`). 원본이 바뀌면 "원본 바뀜" 으로 알립니다 |
| 하네스 설정 | `custom/config.local.json` (복사 설치는 이것을 `~/.claude/harness/config.local.json` 으로 넣습니다) |

자세한 모양과 규칙은 [shared/app-contract.md](shared/app-contract.md). 내 수정 폴더에 읽을 수 없는 것이 있으면 아무것도 쓰지 않고 멈춥니다.

### Windows (Claude 데스크톱 앱 · 네이티브 Claude Code)

WSL 과 Windows 의 Claude Code 는 설정 폴더가 따로입니다 (`~/.claude` ↔ `%USERPROFILE%\.claude`). Windows 에서도 쓰려면 WSL 에 받은 저장소를 그대로 Windows 에 설치합니다.

```powershell
powershell -ExecutionPolicy Bypass -File \\wsl.localhost\Ubuntu-24.04\home\<사용자>\project\claude-harness\install.ps1
```

- 개발자 모드가 켜져 있으면 링크로, 아니면 **복사**로 설치합니다. 복사로 설치했으면 저장소를 고친 뒤 다시 돌려야 합니다 — `/harness-setup` 이 달라진 것을 알려 줍니다.
- 설정(`config.local.json`)은 WSL 과 같은 파일을 씁니다. Vault 경로는 환경에 맞게 바꿔 씁니다 (`/mnt/c/…` ↔ `C:/…`).
- 작업자 가드 hook 은 bash 로 돌아서 Git Bash 가 있어야 합니다.
- Windows 용 데스크톱 앱(`/desktop-app`)은 Windows 쪽에서 만드는 것을 권장합니다 — WSL 에서는 화면이 실제와 다르게 보이고 Windows 설치본을 만들 수 없습니다 (`shared/desktop/stack.md`).
- 지우기: 같은 명령 끝에 `-Uninstall`
- 옵션은 `install.sh` 와 같은 이름입니다 (`--plan` ↔ `-Plan`, `--check` ↔ `-Check`, `--backups` ↔ `-Backups`, `--restore <번호>` ↔ `-Restore <번호>`, `--json` ↔ `-Json`, `--origin-hash` ↔ `-OriginHash`). 내 수정 · 백업 · JSON 도 같습니다.
- 내 수정이 있으면 링크가 되는 PC 에서도 복사로 설치합니다 (원본 + 내 수정을 합친 것).

## 구조

```
skills/            web-full · web-lite · desktop-app · thread-draft · harness-resume · harness-setup
agents/            작업자 정의 — install.sh · install.ps1 이 공통 규칙과 합쳐 ~/.claude/agents 로 복사
  _common/           rules.md (공통 규칙) · hooks.yml (가드 hook) · template.md (새 작업자 틀)
hooks/             builder-guard.sh — 작업자 가드 (git · 배포 · 서명 · .env)
shared/
  workflow.md          공통 진행 규칙 — 승인 · 실행 · 기록 · git · 공개 저장소
  questions-dev.md     개발 질문 (full / lite)
  questions-design.md  디자인 — 비전문가에게 묻는 법, 제작자가 정하는 것
  delegation.md        작업자 표 · 담당 정하기 · 작업 지시서 · 검수
  knowledge-capture.md 개념 노트 (web-full · desktop-app)
  desktop/             데스크톱 앱 — 질문 · 기술(Tauri 2) · 디자인 · 시험
  threads/             스레드 글 — 글쓰기 · 공개 전 거르기 · 이미지 고르기 · 말투 틀
  templates/           docs 문서 틀
  app-contract.md      앱(Nyanitor)과의 약속 — 설치 스크립트 옵션 · JSON, custom/ 모양, 앞머리 · 프로젝트 문서 형식
install.sh · install.ps1 · uninstall.sh   설치 · 미리보기 · 백업 · 되돌리기 · 지우기
tests/             설치 스크립트 시험 — bash tests/install.test.sh · powershell -File tests\install.test.ps1 (임시 폴더에서만 돈다)
config.example.json  개인 설정 예시
```

## 프로젝트에 만들어지는 문서

```
docs/
  README.md
  01-planning/     plan.md · decisions.md · design-references.md (레퍼런스 보드) · design/ (시안 스크린샷)
  02-development/  dev-plan.md (단계 · 담당 · 진행 로그) · handoff.md (이어 하기 메모) · briefs/ (작업 지시서) · release.md (앱 출시)
  03-worklog/      YYYY-MM-DD.md
  04-communication/ 질의응답 · 검수 기록
```

저장소를 공개할 때는 `docs/` 를 올릴지 처음에 정합니다. 기본 권장은 코드만 공개입니다.

## 라이선스

MIT — [LICENSE](LICENSE)
