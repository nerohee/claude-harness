# 변경 기록

## 2026-10-22
- 새 스킬 `/thread-draft` — 작업 일지로 스레드 글 초안 2~3안 · 이미지 1~n장(PNG 로 모음) · 공개 전 거르기, 게시는 사용자. `shared/threads/`(writing · filter · images · voice.example), 틀 `thread-draft.md` · `threads-account.md`, 설정 `threads.dir` (말투 `voice.md` 는 계정 폴더에, 저장소 밖)
- `/thread-draft` 묶음 글 — `소개` · `지금까지` · 기간을 받으면 여러 날 일지 · 기획을 훑어 소개 글, 또는 따로 쓸 이야기 목록(프로젝트 README "쓸 이야기") + 그중 하나를 초안으로

## 2026-10-18
- 하네스 폴더 `~/.claude-harness/{repo,custom,backups}` (`CLAUDE_HARNESS_HOME` 으로 위치 변경) — 설치 스크립트가 `custom/`(내 수정)을 원본 위에 겹쳐 설치: 값만 바꾸기(`*.values.yml`) · 끝에 덧붙이기(`*.append.md`) · 새 에이전트 · 스킬 · 파일 통째 바꾸기(`.origin` 에 만들 때의 원본 해시 → 원본이 바뀌면 "원본 바뀜"). 내 수정이 있으면 원본 + 내 수정을 합친 **복사**, 없으면 지금처럼 링크. `config.local.json` 도 `custom/` 으로 (복사 설치가 스킬이 읽는 `~/.claude/harness/config.local.json` 으로 넣는다). 이미 다른 원본을 가리키면 "개발자 모드" 로 표시
- `install.sh` · `install.ps1` 옵션 — `--plan`(미리보기: 새로 생김 · 바뀜 · 지워짐 · 건너뜀 · 원본 바뀜, 아무것도 쓰지 않음) · `--backups` · `--restore <번호>` · `--uninstall` · `--origin-hash <경로>` · `--json`(앱이 읽는 JSON 한 줄, 두 스크립트가 같은 모양). 사람용 출력과 `--check` 는 그대로
- 백업 · 되돌리기 — 덮어쓰거나 지우기 전에 `backups/<날짜시각>/` 에 파일 + 목록(manifest). 하네스가 다루는 경로(`harness` · 하네스 스킬 · 에이전트)만 읽고 백업하고, 설정 · 기록 · 인증은 읽지 않는다. 되돌리면 새로 만든 것은 지우고 덮어쓴 것은 돌려놓는다. 쓰는 중 실패하면 스스로 되돌리고(`rolledBack`) 종료 코드 3. 같은 `~/.claude` 에 설치가 동시에 돌지 못하게 잠금. `uninstall.sh` · `install.ps1 -Uninstall` 도 같은 길(백업 후 지움, 되돌릴 수 있음)
- `shared/app-contract.md` — 앱(Nyanitor)과의 약속 문서(버전 1): 설치 스크립트 옵션 · JSON · 종료 코드, `custom/` 모양, 에이전트 · 스킬 앞머리 필드, `dev-plan.md` 단계 표 · `handoff.md` 상태 줄 읽는 법, 질문은 AskUserQuestion, 단계 승인 카드 4항목(무엇을 · 왜 지금 · 산출물 · 하지 않는 것) 출력 모양(초안). workflow §2 에 승인 질문 모양 한 줄
- 작업자 공통 규칙 — 문서를 PowerShell `Set-Content` · `Out-File` · `Get-Content -Raw` 로 고치지 않기(한글 깨짐), 띄운 개발 서버는 끄고 끝내기, 파일은 LF 로(Windows 파이썬 `newline='\n'`)
- 시험 `tests/install.test.sh` · `tests/install.test.ps1` (임시 폴더에서만 동작, 예전 설치 스크립트와 같은 결과인지 · 내 수정 · 미리보기 = 설치 · 백업 → 되돌리기 · 실패 시 되돌림 · `install.sh` 와 `install.ps1` 의 JSON · 설치 결과가 같은지)

## 2026-10-14
- 커밋 메시지 형식 — 지금까지 써 온 한 줄 `<종류>: <한국어 요약>` (workflow §5). 제안은 `git add` · `git commit -m` 을 따로 된 블록으로, `-C` · `cd` · `&&` 없이, 확인할 게 있을 때만 `git status --short` 와 볼 것 한 줄
- 묻는 형식 — 모든 질문을 선택지 A · B · C … + 기타, 권장안을 A 에, 선택형 질문 도구 우선, 한 묶음 4개까지 (workflow §2)

## 2026-10-13
- 요구사항이 없을 때 — 스킬을 경로 없이 부르면 대화로 받아 적기 / 틀 만들어 주기 / 경로 알려 주기 (workflow §0-5), 가벼운 틀 `templates/requirements.md`. 요구사항은 자유 형식이 기본
- 끊겼다 이어 하기 — 새 스킬 `/harness-resume`, 이어 하기 메모 `handoff.md` · 작업 지시서 파일 `briefs/` 틀. 맡기기 직전 · 돌아온 직후에 기록(workflow §4 · §8), 작업자는 지시서 항목을 끝낼 때마다 `[x]`, 지시서는 한 번에 끝낼 크기로, 단계 끝 새 세션 안내, 프로젝트 `CLAUDE.md` 이어 하기 안내(P0 에서 물음)
- macOS — 가드 hook 의 필드 꺼내기를 `sed -E` 로 (GNU 전용 `\|` 때문에 BSD sed 에서 도구 이름을 못 꺼내 전부 통과될 수 있었음), `harness-setup` 에 `readlink -f` 대신 쓸 길, README 에 macOS 설치
- 작업자 공통 규칙 · 가드 hook 을 `agents/_common/`(rules.md · hooks.yml)으로 빼고, 설치 스크립트가 합쳐서 설치 — 작업자 파일에는 그 작업자만의 것만. 새 작업자 틀 `template.md`. `install.sh --check` · `install.ps1 -Check` 로 설치본 비교, 틀이 틀린 작업자 파일은 설치 중단
- `harness-setup` C 절 — 작업자 고치기 · 추가 · 빼기 체크리스트, 일관성 검사, 시험 호출
- 공통 규칙 — 확인 명령은 반드시 실제로 돌리고 출력을 적는다 (시험 호출에서 helper 가 짐작으로 보고한 것을 보고 더함)
- 작업자 6종으로 재편 — `harness-designer`(Opus · high, 레퍼런스 · 시안 · 디자인 검수) · `harness-builder-ui` · `harness-builder-system` · `harness-tester` · `harness-helper`(Haiku) · `harness-reviewer`(Opus · 읽기 전용). `harness-builder` · `harness-builder-deep` 은 없앰 (설치 스크립트가 예전 복사본을 지움, 예전 담당 표기 `builder` · `deep` 은 delegation.md 규칙으로 읽음)
- delegation.md — 담당 정하기 · 작업자별 지시서 · 검수 항목, README "작업자 프로필", 화면 흐름 designer → ui → designer, 마감 점검은 reviewer
- 새 스킬 `desktop-app` — Tauri 2 데스크톱 앱. 규모를 나누지 않고 요구사항에 맞춰 질문 · 문서 · 시험을 조절. `shared/desktop/`(질문 · 기술 · 디자인 · 시험), 출시 기록 틀 `templates/release.md`
- 공통 문서 · 문서 틀의 "개발 서버 확인" → "실행 확인"(웹 · 앱), workflow §6 에 서명 키 · 앱 안 비밀값 규칙
- 작업자 가드 hook — 앱 서명 · 공증 · 릴리스 올리기 · `gh workflow run` · `cargo publish`, 서명 키 · 인증서 파일 쓰기도 막음. 작업자 설명에 데스크톱 규칙
- 작업자 가드 hook `hooks/builder-guard.sh` — 두 작업자 앞머리 `hooks` 로 연결해 git 커밋 · 푸시 · 브랜치 조작, 배포 · 저장소 설정, `.env` 쓰기를 막음
- Windows 설치 `install.ps1` (링크 → 안 되면 복사, `-Uninstall`), README "Windows" 절
- `harness-setup` — 에이전트 복사본(Windows 복사 설치면 스킬 · shared 도)이 저장소와 같은지 비교
- `dev-plan.md` 틀의 git 규칙을 `commitPolicy` 에 맞게 채우도록, workflow §4 에 틀 채우기 규칙
- `knowledge-capture.md` — WSL ↔ Windows Vault 경로 바꿔 쓰기

## 2026-10-10
- 처음 만듦 — 스킬 `web-full` · `web-lite` · `harness-setup`, 작업자 `harness-builder`(Sonnet · medium) · `harness-builder-deep`(Sonnet · high), 공통 규칙 · 질문 · 문서 틀
