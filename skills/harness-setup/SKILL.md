---
name: harness-setup
description: claude-harness(web-full · web-lite · desktop-app · harness-resume 과 작업자 에이전트) 자체를 설정하거나 고친다 — 처음 설치한 PC 의 개인 설정 만들기, 질문 · 규칙 · 템플릿 바꾸기, 작업자 고치기 · 추가 · 빼기. 사용자가 /harness-setup 으로 부를 때만 쓴다.
argument-hint: "[바꾸고 싶은 것 (비우면 현재 설정을 보여 주고 묻는다)]"
disable-model-invocation: true
model: opus
effort: high
---

# 하네스 설정 (harness-setup)

요청: $ARGUMENTS

## 먼저 파악하기

1. **원본을 찾고 설치 상태를 가른다.** 위치 — 설정 폴더 `$CLAUDE_CONFIG_DIR`(없으면 `~/.claude`), 하네스 폴더 `$CLAUDE_HARNESS_HOME`(없으면 `~/.claude-harness`).
   - 원본 = `<설정 폴더>/harness` 가 링크면 그 대상 (`readlink -f` — macOS 12.3 보다 오래돼 안 되면 `cd <링크> && pwd -P`). 링크가 아니고 `.install-mode` 첫 줄이 `copy` 면 그 **둘째 줄** (복사 설치 — `harness` 폴더는 복사본이라 원본이 아니다). 둘 다 아니면 멈추고 알린다 (설치 안 됨 · 낯선 폴더). 이하 "원본".
   - 원본이 `<하네스 폴더>/repo` 와 같은 곳이면 ③, 아니면 ① · ② (끝 구분자 · `\` `/` · 대소문자는 무시하고 비교).

   | 상태 | 어떤 PC | 설정 자리 (A 절) | 고치는 곳 (B · C 절) |
   |---|---|---|---|
   | ① 링크 설치 | 개발자 (WSL · Linux · macOS) | 원본의 `config.local.json` | 원본 저장소 파일 |
   | ② 복사 설치, 원본이 개발자 클론 | 개발자 (Windows) | `<하네스 폴더>/custom/` 에 읽는 항목(`config.local.json` · `agents/` · `skills/` · `shared/`)이 있으면 `custom/config.local.json`, 없으면 원본의 `config.local.json` | 원본 저장소 파일 → 설치 다시 |
   | ③ 앱이 받은 원본(`repo/`) | 앱 사용자 | `custom/config.local.json` (없으면 만든다) | `repo/` 는 고치지 않는다 — `custom/` (B 절 "③ 이면") |

2. 원본의 `README.md`, `CHANGELOG.md`, `config.example.json` 을 읽는다 (③ 은 읽기만). **현재 설정**은 설정 자리 → (②③) 원본의 `config.local.json` → 설치본 `<설정 폴더>/harness/config.local.json` 순으로 처음 있는 것을 읽는다 (설치가 복사본에 넣는 순서와 같다). 설치본에만 있으면 그 값을 바탕으로 하고 A 절에서 설정 자리로 옮긴다.
3. 설치 상태를 확인한다 — `<설정 폴더>/skills/{web-full,web-lite,desktop-app,thread-draft,harness-resume,harness-setup}`, `<설정 폴더>/agents/harness-*.md` (designer · builder-ui · builder-system · tester · helper · reviewer).
   - **설치된 것이 원본과 같은지 비교한다** — 작업자는 공통 규칙과 합쳐 복사하고, 복사 설치(②③)는 스킬 · `shared/` 도 복사본이라 원본만 고치면 예전 것이 계속 쓰인다. 둘 다 읽기만 한다.
     ```bash
     bash <원본>/install.sh --check   # 작업자만. Windows: powershell -NoProfile -ExecutionPolicy Bypass -File <원본>\install.ps1 -Check
     bash <원본>/install.sh --plan    # 스킬 · 복사본 · 내 수정까지. "(바뀌는 것 없음)" 이면 같다. Windows: ... install.ps1 -Plan
     ```
   - 빠졌거나 다르면 무엇이 다른지 보이고, **원본의** 설치 스크립트를 다시 돌리도록 제안한다 (`bash <원본>/install.sh` / `install.ps1`). 종료 코드 2(내 수정에 읽을 수 없는 것 등)면 아무것도 쓰지 않은 것이니 출력 원문을 보인다. ③ 에서 "원본 바뀜" 이 나오면 알리기만 한다 (고르기는 앱의 일 — 설치는 내 것을 그대로 쓴다).

## A. 처음 설정 (설정 자리에 `config.local.json` 이 없거나 비었을 때)

선택형 질문 도구로 묻는다 — 선택지마다 A · B …, 권장안(아래 "기본")을 첫 번째에 "(권장)", 직접 입력(Vault 경로 등)은 기타로. 도구 한 번에 4개까지라 두 번에 나눈다 (workflow §2 "묻는 형식").

| 항목 | 질문 | 기본 |
|---|---|---|
| `language` | 대답 언어 | `ko` |
| `vault.path` | Obsidian Vault 경로 (개념 노트를 남길 곳). 없으면 비워 둔다 | 비움 |
| `vault.rawImportDir` | Vault 안 Raw Import 폴더 | `00 Inbox/Raw Import/Personal Study` |
| `docsDir` | 프로젝트 문서 폴더 | `docs` |
| `commitPolicy` | `propose-only`(커밋은 내가) / `agent-commits`(푸시만 내가) | `propose-only` |
| `threads.dir` | 스레드 글 초안을 모을 계정 폴더 (`/thread-draft`). 안 쓰면 비워 둔다 | 비움 |

답을 받아 위 표(먼저 파악하기)의 **설정 자리**에 `config.local.json` 을 쓴다. ①② 원본 폴더의 파일은 git 에 올라가지 않는다(개인 경로라서). Vault 경로를 받았으면 그 폴더가 실제로 있는지 확인한다.

- 파일은 통째로, UTF-8(BOM 없음) · LF 로 쓴다. 이미 있는 파일을 고칠 때는 모르는 키를 그대로 둔다. ③ 에서 `custom/` 폴더가 없으면 만든다 (git 저장소로 만들거나 커밋하지 않는다 — 앱의 일).
- ① 은 스킬이 원본의 파일을 바로 읽으니 다시 설치할 필요가 없다. **②③ 복사 설치는 쓴 뒤 설치를 다시 돌려야** 스킬이 읽는 `<설정 폴더>/harness/config.local.json` 에 들어간다 — 원본의 설치 스크립트를 `--plan`(Windows `-Plan`)으로 먼저 보이고 돌린다. ③ 에서 처음 `custom/config.local.json` 을 만들면 링크 설치가 복사 설치로 바뀐다고 알린다.
- ③ 은 설정을 `repo/` 에 쓰지 않는다 (앱이 받은 원본에는 설정 파일을 만들지 않는 약속).

## B. 하네스 고치기

1. **요청을 하네스 기준으로 정리한다** — 무엇을 바꾸고 싶은지, 어느 파일이 바뀌는지.

   | 바꾸고 싶은 것 | 파일 |
   |---|---|
   | 진행 방식 · 승인 · 기록 · git 규칙 | `shared/workflow.md` |
   | 끊겼다 이어 하기 | `shared/workflow.md` §4 · §8, `shared/templates/handoff.md` · `brief.md`, `skills/harness-resume/SKILL.md` |
   | 개발 질문 | `shared/questions-dev.md` |
   | 디자인 질문 · 디자인 원칙 | `shared/questions-design.md` |
   | 맡기기 · 검수 방식 | `shared/delegation.md` |
   | 개념 노트 | `shared/knowledge-capture.md` |
   | 데스크톱 앱 — 질문 · 기술(Tauri) · 디자인 · 시험 | `shared/desktop/*.md` |
   | 스레드 글 초안 — 글쓰기 · 거르기 · 이미지 | `shared/threads/*.md`, `skills/thread-draft/SKILL.md` · 계정 폴더는 `config` 의 `threads.dir` (말투 `voice.md` 는 계정 폴더에 — 저장소에 두지 않는다) |
   | 문서 틀 | `shared/templates/*.md` |
   | 스킬별 단계 | `skills/<이름>/SKILL.md` |
   | 작업자 — 성격 · 모델 · 맡는 일 · 공통 규칙 · 추가 · 빼기 | **C 절** |
   | 계획 담당 모델 | `config` 의 `planner` + 각 SKILL.md 앞머리 `model` · `effort` |
   | 새 스킬 추가 | `skills/<새 이름>/SKILL.md` + README 표 |

2. **바꿀 내용을 짧게 보이고 승인을 받는다** — 무엇을 / 어느 파일 / 기존 프로젝트에 영향이 있는지.
3. 승인되면 ①② 는 원본의 저장소 파일을 고친다 (③ 은 아래 "③ 이면"). 개인 경로 · 비밀값은 저장소 파일에 쓰지 않는다 (`config.local.json` 에만). `custom/` 에 같은 경로의 통째 바꾸기 파일이 있으면 그쪽이 이기니, 고친 원본이 적용되지 않는다고 알린다.
4. `agents/` (작업자 파일 · `_common/`)를 바꿨으면 원본의 `install.sh` 를 다시 돌린다 (작업자는 합쳐 복사하는 방식이라). 새 스킬을 추가했어도 다시 돌린다. **② 복사 설치는 어느 파일을 고쳤든** 다시 돌린다 (스킬 · `shared/` 도 복사본이라).
5. `CHANGELOG.md` 맨 위에 날짜와 한 줄을 적는다.
6. 하네스 저장소의 커밋 메시지를 제안한다 — workflow §5 "커밋 메시지 형식" (한 줄, `<종류>: <요약>`)과 복사해 쓸 명령.
7. 에이전트 폴더를 처음 만들었거나 스킬 목록이 안 바뀌어 보이면 Claude Code 를 다시 시작하라고 알린다.

**③ 이면 (앱이 받은 원본)** — `repo/` 는 앱이 받고 업데이트만 하는 곳이라 고치지 않는다 (업데이트 때 충돌한다). 위 표의 파일을 바꾸려면 `<하네스 폴더>/custom/` 에 `shared/app-contract.md` §3 모양으로 둔다. 2번 승인은 똑같이 받고, 4~6번은 아래로 바꾼다.

| 하려는 것 | `custom/` 에 둘 것 |
|---|---|
| 앞머리 값(`model` · `effort` 등) 바꾸기 | 대상 `.md` 와 같은 경로에서 `.md` 를 `.values.yml` 로 — 한 줄에 `키: 값` (대상은 `agents/*.md`, `skills/<이름>/SKILL.md`. `name` · `hooks` · 여러 줄 값은 못 바꾼다) |
| 끝에 덧붙이기 | 같은 경로에서 `.md` 를 `.append.md` 로 (`agents/` · `skills/` · `shared/` 의 `.md`) |
| 새 에이전트 · 스킬 | `agents/<이름>.md` · `skills/<이름>/SKILL.md` — 원본에 없는 이름 (틀은 C 절) |
| 통째로 바꾸기 | 원본과 **같은 경로**의 파일 + `<경로>.origin` (한 줄 sha256 — `install.* --origin-hash <저장소 안 상대 경로, 예: agents/harness-designer.md>` 로 얻는다) |
| 하네스 설정 | `config.local.json` (A 절) |

- 쓰기: 파일 하나씩 통째로, UTF-8(BOM 없음) · LF. **`custom/` 에 읽을 수 없는 것(링크 · 탭이 든 경로 · 잘못된 값 · `agents/_common/` · `agents/` 아래 하위 폴더 · `skills/` 바로 아래 파일)이 하나라도 있으면 설치 전체가 멈춘다** — 쓴 뒤 `repo/install.sh --plan` (Windows `-Plan`) 으로 먼저 확인하고, 종료 코드 2 면 원문을 보이고 그 파일을 고친다.
- `agents/_common/`(공통 규칙 · 가드 hook) · 약속에 없는 모양은 `custom/` 으로 못 바꾼다 — 안 된다고 알리고, 하려면 개발자 원본(자기 클론)이 필요하다고 한다.
- 설치는 `repo/install.sh` 를 다시 돌린다 (`--plan` 으로 보인 뒤). `custom/` 이 git 저장소여도 커밋을 제안하지 않는다 — "앱의 내 수정 기록에 남는다" 고만 알린다. 하네스 저장소 커밋 제안 · `CHANGELOG.md` 단계는 건너뛴다.

## C. 작업자 고치기 · 추가 · 빼기

요청이 작업자에 관한 것이면 (예: `/harness-setup 작업자 designer 성격 바꾸기`, `/harness-setup 작업자 추가 — 문서 담당`) 이 절차를 따른다. 승인 · CHANGELOG · 커밋 메시지 제안은 B 와 같다.

**구조** — 작업자 파일 `agents/harness-<이름>.md` 에는 그 작업자만의 것(앞머리 · 성격 · 일하는 법 · 이 작업자만 지킬 것 · 보고 형식)만 둔다. 모든 작업자에게 같은 규칙은 `agents/_common/rules.md`, 가드 hook 은 `agents/_common/hooks.yml` 에 있고, 설치할 때 합쳐진다 — 규칙은 `<!-- harness:common -->` 줄 자리(없으면 끝)에, hook 은 앞머리 끝에. 작업자 파일에 `hooks:` 를 쓰거나 공통 규칙을 다시 쓰지 않는다.

**고치는 곳은 원본 저장소뿐 (③ 이면 `custom/`)** — Claude Code 의 `/agents` 명령이나 `<설정 폴더>/agents/` 의 파일을 직접 고치지 않는다. 다음 설치 때 덮어써진다. 사용자가 그렇게 고쳐 둔 흔적이 있으면(`--check` 가 "다름") 그 내용을 저장소 파일(③ 은 `custom/`)로 옮길지 먼저 묻는다.

**③ 이면** — 아래 표와 "마치기 전에" 의 저장소 고치기는 하지 않는다. `repo/` 를 고치지 않고 B 절 "③ 이면" 표대로 `custom/` 에 둔다.
- 성격 · 일하는 법 덧붙이기 → `custom/agents/harness-<이름>.append.md` (원본 끝에 붙는다, 공통 규칙 · hook 이 합쳐지기 전). 모델 · 추론 수준 → `custom/agents/harness-<이름>.values.yml` (`model: opus`, `effort: high`).
- 새 작업자 → `custom/agents/<이름>.md` — `repo/agents/_common/template.md` 를 복사해 채운다 (안내 주석은 지운다, 둘째 줄 `name` 은 파일 이름과 같게, `hooks:` 는 쓰지 않는다 — 공통 규칙 · 가드는 설치가 붙인다). 원본의 `shared/delegation.md` 표에는 안 오르니 필요하면 `custom/shared/delegation.append.md` 로 덧붙인다. README · `config` 의 `agents` · `dev-plan.md` 는 원본이라 건드리지 않는다.
- 공통 규칙 · 가드 · 원본 작업자 빼기 · 이름 바꾸기는 `custom/` 으로 못 한다 — 안 된다고 알린다.
- 마치기: 설치 다시(`repo/install.sh`, 먼저 `--plan`) → `--check`, 그리고 아래 3번 시험 호출.

| 하려는 것 | 고칠 곳 |
|---|---|
| 한 작업자의 성격 · 일하는 법 · 보고 형식 | 그 작업자 파일 본문 + README "작업자 프로필" 그 줄 |
| 모델 · 추론 수준 | 그 작업자 파일 앞머리 + `shared/delegation.md` 표 + README 두 표 |
| 맡는 일 (메인이 언제 부르나) | 앞머리 `description` + `shared/delegation.md` 표 · "담당 정하기" + README |
| 도구 제한 | 앞머리 `tools` · `disallowedTools` + README 프로필 |
| 모든 작업자 공통 규칙 | `agents/_common/rules.md` 만 (작업자 파일은 손대지 않는다) |
| 가드 (막는 명령 · 파일) | `hooks/builder-guard.sh` |
| 새 작업자 | `agents/_common/template.md` 를 `agents/harness-<이름>.md` 로 복사해 채운다 (틀 안내 주석은 지운다) + `shared/delegation.md` (표 · 담당 정하기 · 필요하면 작업자별 지시서 · 검수 항목) + README 두 표 + `config.example.json` · `config.local.json` 의 `agents` + `shared/templates/dev-plan.md` 담당 설명 + 담당 흐름을 적은 스킬 |
| 작업자 빼기 · 이름 바꾸기 | 위 곳 모두에서 빼고, 예전 이름을 `install.sh` · `uninstall.sh` 의 `RETIRED`, `install.ps1` 의 `$Retired` 에 더한다 + `shared/delegation.md` "예전 표기" 에 읽는 법 |

새 작업자를 만들기 전에 따져 본다 — 기존 작업자의 체크리스트를 늘리는 것으로 안 되는가? 모델 · 도구 · 체크리스트 중 하나라도 실제로 달라지는가? 둘 다 아니면 새로 만들지 말자고 제안한다.

**마치기 전에**
1. **일관성** — 작업자 파일 앞머리(`name` · `model` · `effort`), `shared/delegation.md` 표, README 두 표, `config.example.json` 의 `agents` 가 서로 맞는지 본다. 예전 이름 · 담당 표기가 남지 않았는지 저장소 전체를 `grep` 한다 (CHANGELOG · 예전 작업자 목록 · "예전 표기" 규칙은 빼고).
2. **설치와 확인** — `bash <원본>/install.sh` 다음 `bash <원본>/install.sh --check` (Windows 는 `install.ps1` · `-Check`). 작업자 파일 틀이 틀리면(`name` 줄이 파일 이름과 다름, `hooks:` 를 씀) 설치 스크립트가 멈추고 알려 준다.
3. **시험 호출** — 바꾼 작업자에게 스크래치 폴더에서 하는 작은 지시서를 맡긴다. 새 작업자가 아직 보이지 않으면 Claude Code 를 다시 시작한 뒤에 한다.
   - 1차: 파일 하나 만들기 + 확인 명령 + `git commit -m test`. **공통 규칙대로 커밋 앞에서 멈추고 보고하면 정상**이다 (규칙이 들어갔다는 뜻). 보고 형식, 확인 명령을 실제로 돌렸는지도 본다.
   - 2차 (가드 확인): 같은 작업자에게 이어서 "가드 hook 시험 — 커밋을 한 번만 시도하고 막힌 메시지 원문을 보고, 다시 시도하지 말 것" 이라고 보낸다. 막혔다는 메시지가 오고 스크래치 저장소에 커밋이 없으면 통과. 시험 폴더는 지운다.

## 작업자 모델 · 수준을 바꿀 때 판단 기준

- 계획이 구체적인 구현은 `sonnet` · `medium`(ui · tester), 틀리면 비용이 큰 일은 `sonnet` · `high`(system), 판단 없는 반복은 `haiku`(helper)가 속도와 비용의 균형이 좋다.
- 취향 · 판단의 질이 결과를 정하는 일(designer · reviewer)만 `opus`. 비싸니 부르는 시점을 좁힌다.
- 검수에서 같은 실수가 반복되면 먼저 그 작업자 파일의 체크리스트나 지시서 항목을 늘린다. 그래도 안 되면 그 종류의 작업을 더 높은 작업자로 옮긴다 — 모델부터 올리지 않는다.
- `effort` 값: `low` · `medium` · `high` · `xhigh` · `max`. `model` 값: `sonnet` · `opus` · `haiku` · `inherit` 또는 전체 모델 ID.
