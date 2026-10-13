# 변경 기록

## 2026-10-13
- 작업자 가드 hook `hooks/builder-guard.sh` — 두 작업자 앞머리 `hooks` 로 연결해 git 커밋 · 푸시 · 브랜치 조작, 배포 · 저장소 설정, `.env` 쓰기를 막음
- Windows 설치 `install.ps1` (링크 → 안 되면 복사, `-Uninstall`), README "Windows" 절
- `harness-setup` — 에이전트 복사본(Windows 복사 설치면 스킬 · shared 도)이 저장소와 같은지 비교
- `dev-plan.md` 틀의 git 규칙을 `commitPolicy` 에 맞게 채우도록, workflow §4 에 틀 채우기 규칙
- `knowledge-capture.md` — WSL ↔ Windows Vault 경로 바꿔 쓰기

## 2026-10-10
- 처음 만듦 — 스킬 `web-full` · `web-lite` · `harness-setup`, 작업자 `harness-builder`(Sonnet · medium) · `harness-builder-deep`(Sonnet · high), 공통 규칙 · 질문 · 문서 틀
