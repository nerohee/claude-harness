# 데스크톱 기술 — Tauri 2

## 1. 기본 구성

| 영역 | 고른 것 |
|---|---|
| 앱 틀 | **Tauri 2** — 설치본이 작고(수 MB) 메모리를 적게 쓰며, 앱이 할 수 있는 일을 권한 목록으로 정한다 |
| 화면 | 정적 빌드되는 프런트엔드 — 기본 **Vite + React + TypeScript**. 요구사항이나 사용자 선호가 있으면 따르되, 서버 렌더링이 필요한 프레임워크는 쓰지 않는다 |
| 시스템 쪽 | Rust (`src-tauri/`) — 파일 · DB · OS 기능 · 무거운 계산 |
| 만들기 | `npm create tauri-app@latest` |

Tauri 로 안 되는 일(드라이버, 게임 엔진 수준 그래픽, 화면 녹화 같은 깊은 OS 기능)이 요구사항에 있으면 계획 전에 알리고 함께 정한다. 다른 앱 틀로 바꾸는 것은 사용자 결정이다.

## 2. 개발 환경

대상 OS 에 따라 **어디서 개발할지** 를 P0 에서 정한다.

| 대상 OS | 개발 위치 | 이유 |
|---|---|---|
| Windows 포함 (권장 기본) | 프로젝트를 Windows 폴더(`C:\…`)에 두고 **Windows 의 Claude Code** 에서 진행 (하네스는 `install.ps1` 로 설치) | WSL 에서 띄우면 리눅스 엔진(WebKitGTK)으로 그려져 실제 Windows(WebView2)와 다르게 보이고, Windows 설치본은 Windows 에서만 정식으로 만든다. `\\wsl.localhost` 경로를 Windows 에서 빌드하면 느리고 파일 감시가 깨진다 |
| Linux 만 | WSL 그대로 (WSLg 로 창이 뜬다) | |
| macOS 포함 | macOS 설치본은 Mac 또는 GitHub Actions 에서 | 다른 OS 에서 macOS 설치본을 만들 수 없다 |

여러 OS 에 배포하면 출시 빌드는 GitHub Actions(`tauri-apps/tauri-action`)에서 OS 별로 만든다.

### 도구 확인

프로젝트를 만들기 전에는 `rustc -V`, `cargo -V`, `node -v` 만, 만든 뒤에는 `npm run tauri info` 로 전체를 본다. 없는 것은 설치 명령만 드린다 (설치는 사용자가).

| OS | 필요한 것 |
|---|---|
| Windows | Rust (`winget install Rustlang.Rustup`, MSVC 도구 모음), Visual Studio Build Tools 의 "C++를 사용한 데스크톱 개발", WebView2 (Windows 10 최신 · 11 에는 있음), Node.js |
| Linux (WSL) | Rust (rustup), `sudo apt install libwebkit2gtk-4.1-dev build-essential curl wget file libxdo-dev libssl-dev libayatana-appindicator3-dev librsvg2-dev`, Node.js |
| macOS | Xcode Command Line Tools (`xcode-select --install`), Rust, Node.js |

자세한 목록이 바뀌었을 수 있으니 처음 설정할 때는 Tauri 공식 문서의 Prerequisites 를 확인한다.

## 3. 구조 규칙 (P1 "앱 뼈대" 에서 정한다)

- **앱 식별자** — `tauri.conf.json` 의 `identifier` (`com.<이름>.<앱>`). 데이터 폴더 · 업데이트가 이 값에 묶이므로 P1 에서 정하고 바꾸지 않는다. D-번호로 기록.
- **버전은 한 곳** — `tauri.conf.json` 의 `version` 은 `"../package.json"` 을 가리키게 하고, `Cargo.toml` 버전도 출시 때 같이 맞춘다.
- **IPC 는 한 파일로 모은다** — 화면 코드는 `invoke` 를 직접 부르지 않고 `src/lib/ipc.ts`(예) 의 함수만 쓴다. 그래야 브라우저에서 가짜로 바꿔 화면을 보고 시험할 수 있다 (`testing.md`).
- **명령은 얇게** — `#[tauri::command]` 함수는 입력 확인과 전달만, 실제 로직은 일반 Rust 함수로 빼서 `cargo test` 로 시험한다.
- **오류는 화면까지** — 명령은 `Result<T, E>` 로 돌려주고, `E` 는 직렬화되는 오류 형식으로. `unwrap()` 으로 앱을 죽이지 않는다.
- **무거운 일은 비동기** — 파일 처리 · 큰 계산은 `async` 명령이나 별도 스레드로, 진행 상황은 이벤트로 알린다.
- **상태** — 앱 전체 상태는 `tauri::State` + `Mutex`.

## 4. 권한과 보안

| 무엇 | 규칙 |
|---|---|
| 권한 (capabilities) | `src-tauri/capabilities/*.json` 에 **필요한 것만** 연다. 파일 접근은 앱 폴더 등 범위(scope)를 좁혀서. 창마다 따로 줄 수 있으면 따로 |
| 명령 | 받은 값을 Rust 에서 다시 확인한다 (경로는 정해진 폴더 안인지). "아무 경로나 읽기" · "명령 실행" 같은 만능 명령을 만들지 않는다 |
| CSP | `tauri.conf.json` 의 `app.security.csp` 를 정한다. 원격 웹 페이지를 앱 창에 불러오지 않는다 |
| 외부 링크 | opener 플러그인으로 기본 브라우저에서 연다. 허용할 주소 범위를 정한다 |
| 비밀값 | 앱 안(화면 · Rust 코드 · 설정)에 API 키를 넣지 않는다 — 설치본에서 꺼낼 수 있다 |

검수할 때 권한 파일 변경은 따로 본다 — 지시서에 없는 권한이 열렸으면 되돌린다.

## 5. 데이터

- 위치는 Tauri 경로 API 의 앱 데이터 폴더 (Windows 는 `%APPDATA%\<식별자>`). 실행 파일 옆이나 문서 폴더에 몰래 쓰지 않는다.
- 설정 값 몇 개는 store 플러그인, 목록 · 기록 같은 데이터는 SQLite (sql 플러그인 또는 Rust 의 `rusqlite`).
- **DB 구조 변경(마이그레이션)은 처음부터 번호를 붙여** 둔다 — 출시 뒤 바꿀 때 기존 사용자 데이터를 살린다.
- 중요한 데이터면 내보내기 · 자동 백업을 기능 목록에 넣는다.

## 6. 자주 쓰는 플러그인

| 필요 | 플러그인 |
|---|---|
| 파일 열기 · 저장 대화상자 | `dialog` |
| 파일 읽기 · 쓰기 | `fs` (범위 지정) |
| 설정 저장 | `store` |
| SQLite | `sql` |
| 알림 | `notification` |
| 전역 단축키 | `global-shortcut` |
| 자동 실행 | `autostart` |
| 한 번만 실행 · 두 번째 실행 시 기존 창 | `single-instance` |
| 창 크기 · 위치 기억 | `window-state` |
| 링크로 앱 열기 | `deep-link` |
| 기본 브라우저 · 파일 탐색기로 열기 | `opener` |
| 로그 | `log` |
| 자동 업데이트 | `updater` (+ `process` 로 재시작) |

트레이 아이콘은 플러그인이 아니라 Tauri 기본 기능(`tray-icon`)이다. 플러그인을 더할 때마다 권한 파일도 같이 바뀐다.

## 7. 설치본 · 서명 · 업데이트

- 설치본: `npm run tauri build` — Windows `nsis`(권장) · `msi`, macOS `dmg`, Linux `AppImage` · `deb`.
- 아이콘: 1024px 정사각 PNG 하나에서 `npm run tauri icon <파일>` 로 모든 크기를 만든다.
- **서명** — 누가 쓰나에 따라 (`questions.md` 표). Windows 는 코드 서명 인증서 또는 클라우드 서명 서비스, macOS 는 Apple 개발자 계정으로 서명 + 공증. 서명 · 공증 명령은 사용자가 실행한다.
- **업데이트** — updater 플러그인. 서명 키는 `npm run tauri signer generate` 로 **사용자가** 만든다.
  - 공개 키는 `tauri.conf.json` 에, 비밀 키는 저장소 밖에 두고 빌드 때 환경 변수(`TAURI_SIGNING_PRIVATE_KEY`, 비밀번호는 `TAURI_SIGNING_PRIVATE_KEY_PASSWORD`)로만 쓴다. CI 에서는 저장소 비밀값(Secrets)으로.
  - 비밀 키를 잃어버리면 이미 설치된 앱을 업데이트할 수 없다 — 백업을 두 곳에 두도록 안내한다.
  - 배포 주소는 보통 GitHub Releases. 릴리스를 공개하는 것은 사용자가 한다.
- 출시 결과는 `docs/02-development/release.md` 에 (틀: `templates/release.md`).
