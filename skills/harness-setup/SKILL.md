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

1. `~/.claude/harness` 가 가리키는 실제 저장소 위치를 확인한다 (`readlink -f ~/.claude/harness` — macOS 12.3 보다 오래돼 안 되면 `cd ~/.claude/harness && pwd -P`). 이하 "저장소".
2. 저장소의 `README.md`, `CHANGELOG.md`, `config.example.json`, `config.local.json`(있으면) 을 읽는다.
3. 설치 상태를 확인한다 — `~/.claude/skills/{web-full,web-lite,desktop-app,thread-draft,harness-resume,harness-setup}` 링크, `~/.claude/agents/harness-*.md` (designer · builder-ui · builder-system · tester · helper · reviewer).
   - **설치된 작업자가 저장소와 같은지 비교한다** — 작업자는 공통 규칙과 합쳐 복사하는 방식이라 저장소만 고치면 예전 것이 계속 쓰인다.
     ```bash
     bash <저장소>/install.sh --check      # Windows: install.ps1 -Check
     ```
   - Windows 에 복사 방식으로 설치했으면(`~/.claude/harness/.install-mode` 가 `copy`) 스킬 · `shared/` 도 같은 식으로 저장소와 비교한다.
   - 빠졌거나 다르면 무엇이 다른지 보이고, 설치 스크립트를 다시 돌리도록 제안한다 (WSL · Linux · macOS: `bash <저장소>/install.sh`, Windows: `install.ps1` — README "Windows" 절).

## A. 처음 설정 (config.local.json 이 없거나 비었을 때)

선택형 질문 도구로 묻는다 — 선택지마다 A · B …, 권장안(아래 "기본")을 첫 번째에 "(권장)", 직접 입력(Vault 경로 등)은 기타로. 도구 한 번에 4개까지라 두 번에 나눈다 (workflow §2 "묻는 형식").

| 항목 | 질문 | 기본 |
|---|---|---|
| `language` | 대답 언어 | `ko` |
| `vault.path` | Obsidian Vault 경로 (개념 노트를 남길 곳). 없으면 비워 둔다 | 비움 |
| `vault.rawImportDir` | Vault 안 Raw Import 폴더 | `00 Inbox/Raw Import/Personal Study` |
| `docsDir` | 프로젝트 문서 폴더 | `docs` |
| `commitPolicy` | `propose-only`(커밋은 내가) / `agent-commits`(푸시만 내가) | `propose-only` |
| `threads.dir` | 스레드 글 초안을 모을 계정 폴더 (`/thread-draft`). 안 쓰면 비워 둔다 | 비움 |

답을 받아 `config.local.json` 을 쓴다. 이 파일은 git 에 올라가지 않는다(개인 경로라서). Vault 경로를 받았으면 그 폴더가 실제로 있는지 확인한다.

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
3. 승인되면 저장소 파일을 고친다. 개인 경로 · 비밀값은 저장소 파일에 쓰지 않는다 (`config.local.json` 에만).
4. `agents/` (작업자 파일 · `_common/`)를 바꿨으면 `install.sh` 를 다시 돌린다 (작업자는 합쳐 복사하는 방식이라). 새 스킬을 추가했어도 다시 돌린다.
5. `CHANGELOG.md` 맨 위에 날짜와 한 줄을 적는다.
6. 하네스 저장소의 커밋 메시지를 제안한다 — workflow §5 "커밋 메시지 형식" (한 줄, `<종류>: <요약>`)과 복사해 쓸 명령.
7. 에이전트 폴더를 처음 만들었거나 스킬 목록이 안 바뀌어 보이면 Claude Code 를 다시 시작하라고 알린다.

## C. 작업자 고치기 · 추가 · 빼기

요청이 작업자에 관한 것이면 (예: `/harness-setup 작업자 designer 성격 바꾸기`, `/harness-setup 작업자 추가 — 문서 담당`) 이 절차를 따른다. 승인 · CHANGELOG · 커밋 메시지 제안은 B 와 같다.

**구조** — 작업자 파일 `agents/harness-<이름>.md` 에는 그 작업자만의 것(앞머리 · 성격 · 일하는 법 · 이 작업자만 지킬 것 · 보고 형식)만 둔다. 모든 작업자에게 같은 규칙은 `agents/_common/rules.md`, 가드 hook 은 `agents/_common/hooks.yml` 에 있고, 설치할 때 합쳐진다 — 규칙은 `<!-- harness:common -->` 줄 자리(없으면 끝)에, hook 은 앞머리 끝에. 작업자 파일에 `hooks:` 를 쓰거나 공통 규칙을 다시 쓰지 않는다.

**고치는 곳은 저장소뿐** — Claude Code 의 `/agents` 명령이나 `~/.claude/agents/` 의 파일을 직접 고치지 않는다. 다음 설치 때 덮어써진다. 사용자가 그렇게 고쳐 둔 흔적이 있으면(`--check` 가 "다름") 그 내용을 저장소 파일로 옮길지 먼저 묻는다.

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
2. **설치와 확인** — `bash <저장소>/install.sh` 다음 `bash <저장소>/install.sh --check`. 작업자 파일 틀이 틀리면(`name` 줄이 파일 이름과 다름, `hooks:` 를 씀) 설치 스크립트가 멈추고 알려 준다.
3. **시험 호출** — 바꾼 작업자에게 스크래치 폴더에서 하는 작은 지시서를 맡긴다. 새 작업자가 아직 보이지 않으면 Claude Code 를 다시 시작한 뒤에 한다.
   - 1차: 파일 하나 만들기 + 확인 명령 + `git commit -m test`. **공통 규칙대로 커밋 앞에서 멈추고 보고하면 정상**이다 (규칙이 들어갔다는 뜻). 보고 형식, 확인 명령을 실제로 돌렸는지도 본다.
   - 2차 (가드 확인): 같은 작업자에게 이어서 "가드 hook 시험 — 커밋을 한 번만 시도하고 막힌 메시지 원문을 보고, 다시 시도하지 말 것" 이라고 보낸다. 막혔다는 메시지가 오고 스크래치 저장소에 커밋이 없으면 통과. 시험 폴더는 지운다.

## 작업자 모델 · 수준을 바꿀 때 판단 기준

- 계획이 구체적인 구현은 `sonnet` · `medium`(ui · tester), 틀리면 비용이 큰 일은 `sonnet` · `high`(system), 판단 없는 반복은 `haiku`(helper)가 속도와 비용의 균형이 좋다.
- 취향 · 판단의 질이 결과를 정하는 일(designer · reviewer)만 `opus`. 비싸니 부르는 시점을 좁힌다.
- 검수에서 같은 실수가 반복되면 먼저 그 작업자 파일의 체크리스트나 지시서 항목을 늘린다. 그래도 안 되면 그 종류의 작업을 더 높은 작업자로 옮긴다 — 모델부터 올리지 않는다.
- `effort` 값: `low` · `medium` · `high` · `xhigh` · `max`. `model` 값: `sonnet` · `opus` · `haiku` · `inherit` 또는 전체 모델 ID.
