# 데스크톱 시험

층을 나눠 시험한다. 아래 층일수록 빠르고 작업자가 돌릴 수 있고, 위로 갈수록 사람이 본다.

| 층 | 무엇을 | 명령 · 도구 | 언제 |
|---|---|---|---|
| 1. 정적 검사 | 타입 · 린트 · 서식 | `npx tsc --noEmit`, `cargo clippy --manifest-path src-tauri/Cargo.toml -- -D warnings`, `cargo fmt --manifest-path src-tauri/Cargo.toml --check` | 모든 작업 |
| 2. 단위 시험 — 화면 | 컴포넌트 · 화면 동작 | Vitest + Testing Library. IPC 는 `@tauri-apps/api/mocks` 의 `mockIPC` 로 가짜 | 화면 작업 |
| 3. 단위 시험 — 시스템 쪽 | 명령 뒤의 로직 · DB · 파일 처리 | `cargo test --manifest-path src-tauri/Cargo.toml` | Rust 작업 |
| 4. 화면 보기 | 화면을 브라우저에서 | `npm run dev` (Vite 만, IPC 는 가짜 모드) — 브라우저 시험 도구로 화면 확인 · 접근성 검사 | 화면 작업 |
| 5. 실행 확인 | 실제 앱 창 | `npm run tauri dev` — **사용자가** 본다 | 화면 · 동작이 바뀐 작업 |
| 6. 전체 흐름 (E2E) | 핵심 흐름을 실제 앱으로 | `tauri-driver` + WebdriverIO (Windows · Linux 만, macOS 안 됨) | 큰 앱, 핵심 흐름이 정해진 뒤 |
| 7. 설치본 확인 | 설치 · 첫 실행 · 업데이트 · 제거 | `npm run tauri build` 후 깨끗한 환경에서 — **사용자가** | 출시 |

- 1~3 은 첫 단계(앱 뼈대)에서 명령을 만들어 둔다 (`package.json` scripts 에 `check`, `test` 로 모으면 지시서가 짧아진다).
- 4 를 위해 IPC 가짜 모드를 만든다 — `ipc.ts` 가 Tauri 밖(브라우저)에서는 가짜 데이터를 돌려주게 (`stack.md` "구조 규칙").
- 6 은 Windows 에서 Edge 버전에 맞는 `msedgedriver` 가 필요하다. 붙이는 비용이 있어서 작은 앱에서는 하지 않는다.

## 실행 확인을 요청할 때

사용자에게 이것만 보낸다:

1. 띄우는 명령 — `npm run tauri dev` (첫 실행은 Rust 빌드로 몇 분 걸린다고 알린다)
2. 볼 것 — 바뀐 창 · 동작을 2~4개 항목으로 (예: "창을 최소 크기로 줄였을 때 목록이 잘리지 않는지")
3. 확인할 OS 동작이 있으면 — 트레이, 단축키, 알림, 창 닫기, 다시 열었을 때 창 위치

## 설치본 확인 (출시)

깨끗한 환경에서 한다 — Windows Sandbox(Windows Pro 이상), 다른 PC, 가상 머신.

| 확인 | 볼 것 |
|---|---|
| 설치 | 경고 문구(서명 안 했으면 예상대로인지), 설치 위치, 시작 메뉴 · 바로가기 |
| 첫 실행 | 데이터 없는 첫 화면, 시작 시간, 권한 요청 |
| 업데이트 | 이전 버전을 깔고 새 버전으로 — 데이터가 남는지 (업데이트가 있는 앱만) |
| 제거 | 프로그램 제거 뒤 남는 것 — 앱 데이터 폴더를 남길지 지울지 정한 대로인지 |

결과는 `release.md` 의 해당 버전에 적는다.
