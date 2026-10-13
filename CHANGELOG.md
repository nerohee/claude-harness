# 변경 기록

## 2026-10-13
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
