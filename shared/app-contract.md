# 앱과 하네스의 약속 (app-contract)

> **약속 문서 버전: 1** (2026-10-18) — 설치 스크립트 JSON 의 `contract` 값과 같다. 형식을 바꿀 때는 이 문서와 버전을 올리고, 앱도 같이 바꾼다 (Nyanitor D-22).
> 읽는 쪽(Nyanitor 같은 앱)의 규칙은 하나다 — **형식이 깨졌거나 모르는 버전이면 죽지 말고 "읽을 수 없음" 으로 보인다.** 하네스 쪽은 이 문서의 모양을 지킨다.

이 문서가 약속하는 것: (1) 하네스 폴더와 위치 (2) 설치 스크립트 옵션 · JSON · 종료 코드 (3) 내 수정 폴더 `custom/` 의 모양 (4) 백업 (5) 에이전트 · 스킬 앞머리 (6) 프로젝트 문서의 단계 표 · 이어 하기 메모 (7) 질문과 단계 승인 카드의 출력 모양.

## 1. 위치

| 이름 | 기본 위치 | 바꾸는 법 | 뭐가 있나 |
|---|---|---|---|
| 사용자 설정 | `~/.claude` (Windows `%USERPROFILE%\.claude`) | 환경 변수 `CLAUDE_CONFIG_DIR` | 실제로 쓰는 것 — `harness` · `skills/<스킬>` · `agents/<작업자>.md` |
| 하네스 폴더 | `~/.claude-harness` | 환경 변수 `CLAUDE_HARNESS_HOME` | 아래 셋 |
| 원본 | `<하네스 폴더>/repo/` | — | 클론한 claude-harness. 앱이 받고 업데이트만 한다 (아무도 고치지 않는다) |
| 내 수정 | `<하네스 폴더>/custom/` | — | 3절. 로컬 git 저장소 (D-21) |
| 백업 | `<하네스 폴더>/backups/<번호>/` | — | 4절 |

설치 스크립트는 **`~/.claude` 안에서 하네스가 다루는 경로만** 읽고 쓴다: `harness`, `skills/<하네스 스킬 이름>`, `agents/<하네스 작업자 이름>.md`, 그리고 내 수정으로 새로 만든 에이전트 · 스킬, 상태 파일 `.harness-installed`. 설정 · 기록 · 인증 · 플러그인 등 나머지는 읽지도 백업하지도 않는다.

## 2. 설치 스크립트

### 2-1. 부르는 법

| 환경 | 명령 (원본 폴더에서) |
|---|---|
| Linux · WSL · macOS | `bash install.sh [옵션]` |
| Windows | `powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 [옵션]` |

옵션 이름은 두 스크립트가 같다 (`--plan` ↔ `-Plan`). 둘 다 **같은 JSON** 을 낸다 (경로 표기만 OS 에 맞다).

| `install.sh` | `install.ps1` | 하는 일 |
|---|---|---|
| (없음) | (없음) | 설치. 덮어쓰거나 지우기 전에 백업 |
| `--plan` | `-Plan` | 설치 · 되돌리기 · 지우기를 하지 않고 계획만 (`--restore`, `--uninstall` 과도 같이 쓴다). **아무것도 쓰지 않는다** |
| `--check` | `-Check` | 설치된 작업자가 원본(+ 내 수정)과 같은지만 본다. 다르면 종료 코드 1. 작업자 파일만 본다 (스킬 · 복사본까지 보려면 `--plan` 의 `same`) |
| `--backups` | `-Backups` | 백업 목록 |
| `--restore <번호>` | `-Restore <번호>` | 고른 백업으로 되돌린다 |
| `--uninstall` | `-Uninstall` | 하네스가 만든 것을 지운다 (`uninstall.sh` 도 같다) |
| `--origin-hash <경로>` | `-OriginHash <경로>` | 원본 파일의 해시 (3-5절) |
| `--json` | `-Json` | 사람용 출력 대신 JSON **한 줄** 을 표준 출력으로 (UTF-8). 오류도 JSON 의 `error` 로 |

- 사람용 출력(한국어 줄)은 `--json` 이 없을 때 기본이다. 예전과 같다 — 내 수정이 없는 사람에게는 같은 줄이 나온다 (개발자 모드 한 줄만 더해진다).
- 환경 변수: `CLAUDE_CONFIG_DIR`, `CLAUDE_HARNESS_HOME` (위치). `CLAUDE_HARNESS_NO_SYMLINK=1` 은 링크를 못 만드는 PC 처럼 복사로 동작하게 하는 **시험용** 스위치.
- 같은 `~/.claude` 에 대해 설치 · 되돌리기 · 지우기는 한 번에 하나만 돈다 (`<~/.claude>/.harness-install.lock`). 이미 돌고 있으면 `busy`, 종료 코드 2.

### 2-2. 종료 코드

| 코드 | 뜻 |
|---|---|
| 0 | 성공 (건너뜀 · 원본 바뀜 · 알림이 있어도 0) |
| 1 | `--check` 에서 다름 (JSON 의 `ok` 는 true — 명령은 잘 돌았다) |
| 2 | 잘못된 사용 · 내 수정 폴더에 읽을 수 없는 것이 있음 · 낯선 `harness` 폴더 · 다른 설치가 진행 중 · 없는 백업 · 깨진 백업 목록. **아무것도 쓰지 않았다** |
| 3 | 쓰는 중 실패. 이미 쓴 것을 되돌렸는지 `rolledBack` 으로 알린다. 백업은 남아 있다 |

### 2-3. JSON 모양

모든 명령이 **같은 키 · 같은 순서** 를 낸다 (해당 없는 것은 `null` · `[]`). 경로는 `~/.claude` 기준 상대 경로, `/` 구분.

```json
{"contract":1,"command":"install","ok":true,"exitCode":0,"dryRun":true,
 "claudeDir":"…","harnessHome":"…","repo":"…",
 "mode":"copy","developerMode":false,"existingSource":null,"restartNeeded":false,
 "custom":{"dir":"…/custom","items":[{"path":"agents/harness-builder-ui.md","kind":"values","originChanged":null}]},
 "changes":[{"path":"agents/harness-builder-ui.md","action":"change","type":"file","reason":null}],
 "counts":{"add":0,"change":1,"remove":0,"skip":0,"same":11},"same":false,
 "originChanged":[{"path":"agents/harness-designer.md","recorded":"…64글자…","current":"…64글자…"}],
 "problems":[],"warnings":[{"path":"agents/x.md","reason":"noOriginHash","detail":"…"}],
 "backup":null,"backups":[],"originHash":null,"rolledBack":null,"error":null}
```

| 키 | 뜻 |
|---|---|
| `contract` | 약속 버전 (이 문서 맨 위). 앱이 아는 것보다 크면 읽을 수 없음으로 |
| `command` | `install` · `check` · `backups` · `restore` · `uninstall` · `originHash` |
| `ok` | 명령이 끝까지 돌았나. `problems` 가 있거나 `error` 가 있으면 false |
| `exitCode` | 프로세스 종료 코드와 같다 |
| `dryRun` | `--plan` 이었나 |
| `claudeDir` · `harnessHome` · `repo` | 이번에 쓴 위치. `repo` 는 이 스크립트가 있는 원본 폴더 |
| `mode` | `link`(링크) · `copy`(원본 + 내 수정을 합친 복사) · `null`(계획을 세우지 않는 명령) |
| `developerMode` | `repo` 가 `<하네스 폴더>/repo` 가 아니다 = 개발자가 자기 클론을 원본으로 쓰는 중 (D-20) |
| `existingSource` | 지금 `~/.claude/harness` 가 가리키는 원본 (링크 대상 또는 복사 표시의 원본). 없으면 null. 이번 `repo` 와 다르면 설치가 원본을 바꾼다 |
| `restartNeeded` | `agents` 폴더가 새로 생겨서 열려 있는 Claude Code 를 다시 시작해야 함 |
| `custom.items` | 읽은 내 수정 (3절). `originChanged`: replace 만 true · false · (해시 없음) null |
| `changes` | **계획 = 실제 설치와 같은 목록**. `action`: `add` 새로 생김 · `change` 바뀜 · `remove` 지워짐 · `skip` 건너뜀(하네스가 만들지 않은 것이 있음, `reason: "notOurs"`). `type`: `file` · `link`. 복사 설치의 `harness/…` 는 파일 하나하나 |
| `counts` · `same` | 개수. `same`(불리언)은 바뀔 것이 없다 (add + change + remove = 0). `counts.same` 은 이미 같은 항목 수 |
| `originChanged` | 통째로 바꾼 내 파일의 원본이 달라졌다 (3-5절). `current` 가 null 이면 원본에서 사라진 것 |
| `problems` | 막는 문제 — 있으면 아무것도 쓰지 않고 종료 코드 2. `reason` 코드는 아래 |
| `warnings` | 막지 않는 알림 |
| `backup` | 설치 · 지우기가 만든 백업, 되돌리기는 쓴 백업: `{id, dir, files}` (`files` = 백업한 파일 수) |
| `backups` | `--backups` 의 목록 (4절) |
| `originHash` | `--origin-hash` 의 결과 `{path, sha256}` |
| `rolledBack` | 쓰는 중 실패했을 때 되돌림을 마쳤나 (true · false), 그 밖에는 null |
| `error` | `{code, detail}` 또는 null. `detail` 은 사람이 읽는 한국어 한 줄 |

`problems[].reason` 코드: `symlinkInCustom` · `badPath` · `unsupported` · `targetMissing` · `badValues` · `badOrigin` · `invalidAgent` · `harnessNotOurs`.
`warnings[].reason` 코드: `noOriginHash` · `originGone` · `orphanOrigin` · `emptyAppend` · `ignored` · `configOnlyInInstall`.
`error.code` 코드: `badArgs` · `notFound` · `noBackup` · `badBackup` · `wrongTarget` · `busy` · `backupFailed` · `writeFailed` · `applyFailed` · `restoreFailed` · `unexpected`.

앱은 모르는 코드가 와도 그대로 보여 주고 죽지 않는다.

### 2-4. 설치 방식

- **링크** (내 수정이 없을 때, 링크를 만들 수 있을 때): `~/.claude/harness → 원본`, `~/.claude/skills/<스킬> → 원본/skills/<스킬>`. 예전과 같다.
- **복사** (내 수정이 있을 때, 또는 Windows 에서 링크 권한이 없을 때): `~/.claude/harness` 는 **원본 + 내 수정을 합친 복사본**, 안에 표시 파일 `.install-mode` (첫 줄 `copy`, 둘째 줄 원본 위치). 스킬은 복사본 안(`harness/skills/<스킬>`)으로 링크 (링크가 안 되면 폴더째 복사 + 같은 표시 파일).
- 에이전트는 어느 방식이든 `agents/*.md` + 공통 규칙(`agents/_common/rules.md`) + 가드 hook(`hooks.yml`)을 합쳐 `~/.claude/agents/` 로 복사한다.
- **개발자 모드**: 이미 `~/.claude/harness` 가 다른 원본 저장소를 가리키면(`existingSource` 가 `<하네스 폴더>/repo` 가 아님) 앱은 클론하지 않고 **그 원본의 `install.*`** 를 돌린다. 스크립트는 이를 `developerMode` 로 알린다.
- 하네스 설정 `config.local.json`: 스킬은 `~/.claude/harness/config.local.json` 을 읽는다. 링크 설치는 원본 폴더의 파일(예전 그대로, 없으면 예전처럼 예시에서 만들어 준다 — 개발자 모드일 때만), **복사 설치는 `custom/config.local.json` → 원본의 `config.local.json` → 지금 설치본에 있는 것 순으로** 복사본에 넣는다 (셋 다 없고 내 수정도 없는 개발자 모드의 복사 설치는 마지막으로 `config.example.json`). 앱이 받은 원본(`<하네스 폴더>/repo`)에는 설정 파일을 만들지 않는다 — 설정이 없으면 스킬이 예시 기본값으로 돌고 `/harness-setup` 을 권한다. 설정을 바꾸는 쪽(앱 · `/harness-setup`)은 복사 설치에서 `custom/config.local.json` 을 고치고 다시 설치해야 한다 (설치본만 고치면 `configOnlyInInstall` 알림, 다음 설치까지 그대로 두지만 `custom/` 에는 없다).
- 작업자 가드 hook(`hooks/builder-guard.sh`)은 bash 로 돈다 — **Windows 는 Git Bash 가 있어야 한다** (앱의 git 확인과 이어진다). 설치 스크립트는 막지 않고 한 줄 안내만 한다.
- **원본 찾기** — `<설정 폴더>/harness` 가 링크면 링크 대상, 링크가 아니고 `.install-mode` 첫 줄이 `copy` 면 둘째 줄. 그 원본이 `<하네스 폴더>/repo` 와 같으면 앱이 받은 원본, 아니면 개발자 원본(`developerMode`). 앱 · `/harness-setup` 이 이 규칙으로 판별한다.
- 링크 설치 상태에서 `custom/` 에 읽는 항목(`config.local.json` 포함)이 처음 생기면 다음 설치가 **복사 설치로 바뀐다** (`--plan` 에 `harness` 가 지워지고 파일로 생김이 보인다).

### 2-5. 앱이 업데이트를 받는 흐름 (권장)

1. 앱이 `<하네스 폴더>/repo` 에서 `git fetch` — 바뀐 커밋 · 파일을 미리 보인다 (git 은 앱이 부른다. 스크립트는 git 을 쓰지 않는다).
2. 사용자가 받기를 누르면 `git pull --ff-only`.
3. `install.* --plan --json` → `changes` · `originChanged` 를 보인다 (원본 바뀜이 있으면 3-5절 선택).
4. 사용자가 설치를 누르면 `install.* --json`. 실패(3)면 `rolledBack` 을 알리고 `--restore` 를 권한다.

## 3. 내 수정 `custom/` 의 모양

`<하네스 폴더>/custom/` 은 앱(또는 사용자)이 쓰고, 설치 스크립트가 읽는다. 쓸 때의 규칙: **UTF-8(BOM 없음) · 줄바꿈 LF · 파일 하나씩 통째로 새로 쓰기**. 읽는 쪽은 CRLF 도 LF 로 맞춰 읽지만 앱은 LF 로 쓴다.

```
custom/
  config.local.json                    하네스 설정 (D-20) — 파일 통째로 쓴다. 모르는 키는 그대로 둔다
  agent-cats.json                      앱 전용 (에이전트 ↔ 고양이 연결) — 설치 스크립트는 읽지 않는다
  .git/ .gitignore                     앱이 만드는 로컬 git (D-21) — 읽지 않는다
  agents/
    harness-builder-ui.values.yml      ① 값만 바꾸기
    harness-builder-ui.append.md       ② 원본 끝에 덧붙이기
    harness-designer.md                ③ 통째 바꾸기 (원본에 있는 이름)
    harness-designer.md.origin         ③ 의 "만들 때의 원본 해시"
    translator.md                      ④ 새 에이전트 (원본에 없는 이름)
  skills/
    web-full/SKILL.append.md           스킬도 같은 규칙
    translate-docs/SKILL.md            ④ 새 스킬 — 폴더째 (그 안의 다른 파일도 같이 간다)
  shared/
    workflow.append.md                 공통 문서도 같은 규칙
```

`agents/` · `skills/` · `shared/` 안에서만 읽는다. 그 밖의 파일은 `ignored` 알림으로 건너뛴다. 아래는 **허용하지 않아서 `problems` 로 멈추는** 것: 링크(`symlinkInCustom`), 탭 · 줄바꿈이 든 경로(`badPath`), `agents/_common/`(공통 규칙 · 가드는 못 바꾼다), `agents/` 아래 하위 폴더, `skills/` 바로 아래 파일(`unsupported`).

### 3-1. 값만 바꾸기 — `<파일 이름>.values.yml`

대상 `<파일 이름>.md`(원본에 있어야 한다 — 없으면 `targetMissing`)의 **앞머리**(`---` 사이)에 한 줄 값을 넣는다. 파일 모양: 한 줄에 `키: 값`, 빈 줄과 `#` 줄은 무시.

```yaml
# 값만 바꾼다
effort: high
model: opus
```

- 있는 키는 그 줄을 바꾸고, 없는 키는 앞머리 끝(닫는 `---` 앞)에 더한다.
- 키는 `[A-Za-z][A-Za-z0-9_-]*`, 값은 한 줄 · 비어 있지 않음. `name`(파일 이름과 맞아야 한다) · `hooks`(설치가 붙인다)는 못 바꾼다. 같은 키 두 번 · 값이 여러 줄인 키(`tools:` 아래 목록 등)는 `badValues`.
- 대상 파일: `agents/*.md`, `skills/<스킬>/SKILL.md` (앞머리가 있는 `.md`).

### 3-2. 덧붙이기 — `<파일 이름>.append.md`

대상 `<파일 이름>.md` 맨 끝에 빈 줄 하나를 두고 덧붙인다 (에이전트는 공통 규칙 · hook 이 합쳐지기 전, 원본 끝). 내용이 비어 있으면 `emptyAppend` 알림으로 건너뛴다.

### 3-3. 새 에이전트 · 새 스킬 — 겹치지 않는 새 파일

- `agents/<이름>.md` — 원본에 없는 이름. 틀은 원본 작업자와 같다 (5절): 둘째 줄 `name: <이름>`, `hooks:` 는 쓰지 않는다 (틀이 틀리면 `invalidAgent`). 공통 규칙 · 가드 hook 이 설치할 때 붙는다.
- `skills/<이름>/SKILL.md` (+ 같은 폴더의 다른 파일).
- 설치는 새로 만든 이름을 `~/.claude/.harness-installed` 에 적어 둔다 (`agent <이름>.md` · `skill <이름>` 줄). 나중에 `custom/` 에서 지우면 다음 설치가 `~/.claude` 에서도 지운다 (이 파일에 적힌 것만).
- 같은 이름의 **사용자 자신의 파일**이 이미 `~/.claude` 에 있으면 덮어쓰지 않고 `skip`(`notOurs`) 한다.

### 3-4. 통째 바꾸기 — 같은 경로의 파일

원본에 있는 경로(`agents/harness-designer.md`, `shared/workflow.md` …)와 **같은 경로**에 파일을 두면 그 파일로 통째로 바꾼다. 값 바꾸기 · 덧붙이기를 같이 쓸 수도 있다 (바꾼 내용 위에 적용).

### 3-5. 원본 바뀜 (통째 바꾼 파일만)

통째 바꾸기는 만들 때의 원본 해시를 **`<경로>.origin`** 파일(한 줄, sha256 16진수 64글자)에 남긴다. 해시를 얻는 법: **`install.* --origin-hash <경로>`** (원본 폴더의 그 파일 — `.md` 는 줄바꿈을 LF 로 맞춘 뒤의 sha256, 다른 파일은 바이트 그대로). 앱이 직접 계산하려면 같은 규칙을 지킨다.

- 설치 · 미리보기는 지금 원본의 해시와 `.origin` 을 비교한다. 다르면 `custom.items[].originChanged: true` + `originChanged[]` 에 `{path, recorded, current}`. **설치는 내 것을 그대로 쓰고 끝난다** (원본으로 덮지 않는다) — 고르는 것은 앱의 일이다.
- 고르기 (D-05): **내 것 유지** = `.origin` 을 새 원본 해시(`--origin-hash`)로 다시 쓴다. **원본으로** = `custom/` 의 그 파일과 `.origin` 을 지운다. **비교** = 앱이 `repo/<경로>` 와 `custom/<경로>` 를 나란히 보인다.
- `.origin` 이 없으면 알 수 없음(`originChanged: null`, `noOriginHash` 알림). 원본에서 파일이 사라졌는데 `.origin` 이 있으면 `originChanged: true`, `current: null`, `originGone` 알림 (그 파일은 새 파일처럼 설치된다). `.origin` 모양이 틀리면 `badOrigin` 으로 멈춘다.

### 3-6. 앱이 보는 종류 (시제품의 "값 바꿈 · 덧붙임 · 통째 · 원본 바뀜")

| `custom.items[].kind` | 앱 표시 | 파일 |
|---|---|---|
| `values` | 값 바꿈 | `*.values.yml` |
| `append` | 덧붙임 | `*.append.md` |
| `replace` | 통째 (+ `originChanged` 로 원본 바뀜) | 같은 경로 파일 |
| `new` | 내가 만든 파일 | 원본에 없는 경로 |
| `config` | 하네스 설정 | `config.local.json` |

## 4. 백업 · 되돌리기 (D-04)

설치 · 지우기는 `~/.claude` 의 하네스 경로를 **덮어쓰거나 지우기 전에** `backups/<번호>/` 를 만든다. 바뀌는 것이 없으면 만들지 않는다. 번호는 `YYYY-MM-DD_HHMMSS` (같은 초면 `-2` …).

```
backups/2026-10-18_143205/
  manifest.txt      목록 (아래)
  files/<경로>      덮어쓰거나 지운 파일의 원래 내용 (~/.claude 기준 같은 경로)
```

`manifest.txt` — UTF-8 · LF. `# 키: 값` 머리 줄(`id` · `createdAt` · `command` · `claudeDir` · `repo`) 다음에 줄마다 `동작<TAB>종류<TAB>경로<TAB>덧붙임`:
`add`(설치가 새로 만듦) · `change`(덮어씀, 원래 내용은 `files/`) · `remove`(지움, 원래 내용은 `files/`) × `file` · `link`(덧붙임에 링크 대상) · `dir`(폴더). 설치가 쓰기 전에 먼저 쓰므로, 중간에 끊겨도 되돌릴 수 있다.

- `--backups` 는 `{id, createdAt, command, added, changed, removed, files, bytes, readable}` 목록 (최신이 앞). `readable: false` 는 목록 파일이 없거나 읽을 수 없는 폴더.
- `--restore <번호>`: 설치가 새로 만든 것은 지우고(비게 된 새 폴더도), 덮어쓴 것은 돌려놓고, 지운 것은 다시 만든다. 이미 같은 것은 건드리지 않아 **두 번 해도 같다**. 목록이 **하네스가 다루지 않는 경로**(`..` · 설정 · 기록 …)를 가리키거나 다른 `claudeDir` 의 것이면 아무것도 하지 않고 거부한다 (`badBackup` · `wrongTarget`). 복사본 안의 경로는 링크를 따라가지 않는다 (원본 저장소를 건드리지 않는다).
- 되돌리기는 백업을 새로 만들지 않고 지우지도 않는다. 오래된 백업을 정리하는 것은 앱의 몫 (폴더째 지우면 된다).
- 쓰는 중 실패하면 스크립트가 스스로 같은 방법으로 되돌린다 (`rolledBack`).

## 5. 에이전트 · 스킬 앞머리 (앱이 읽는 필드)

작업자 파일 `agents/harness-<이름>.md` 와 설치된 `~/.claude/agents/*.md` 의 앞머리(첫 줄 `---` ~ 다음 `---`), 한 줄에 `키: 값`:

| 필드 | 뜻 | 값 |
|---|---|---|
| `name` | 이름 — **파일 이름(확장자 뺀 것)과 같아야 한다** (둘째 줄에 둔다) | `harness-designer` |
| `description` | 메인이 언제 부르는지 · 앱이 보이는 한 줄 소개 | 한 줄 글 |
| `model` | 모델 | `sonnet` · `opus` · `haiku` · `inherit` 또는 전체 모델 ID |
| `effort` | 추론 수준 | `low` · `medium` · `high` · `xhigh` · `max` |
| `color` | 표시 색 | 색 이름 |
| `disallowedTools` | 못 쓰게 한 도구 (읽기 전용 감사관) | 쉼표로 나눈 이름 |
| `hooks` | **원본에는 쓰지 않는다** — 설치가 가드 hook 을 붙인다 | (설치본에만) |

스킬 `skills/<이름>/SKILL.md` 앞머리: `name` · `description` · `argument-hint` · `disable-model-invocation` · `model` · `effort`.

오케스트레이터(메인 대화)의 모델 · 수준은 앞머리가 아니라 `config.local.json` 의 `planner`(`model` · `effort`)이고, 역할과 작업자 이름의 대응은 `agents`(`designer` · `ui` · `system` · `tester` · `helper` · `reviewer`) 이다.

앞머리를 읽을 수 없거나(`---` 가 없음 · `name` 이 파일 이름과 다름) 필드가 비면 앱은 그 에이전트를 "읽을 수 없음" 으로 보이고 나머지는 그대로 보인다.

## 6. 프로젝트 문서 (앱의 진행 보기가 읽는다 — 지금 틀 기준)

틀은 `shared/templates/dev-plan.md` · `handoff.md`. 사람이 고치는 파일이라 **앱은 모르는 줄을 건너뛰고, 못 읽는 곳만 "읽을 수 없음"** 으로 보인다.

### 6-1. `docs/02-development/dev-plan.md` — 단계 표

- 표를 찾는 법: `## 단계 개요` 제목 아래 첫 표. 머리 줄 `| 단계 | 내용 | 담당 | 승인 게이트 | 상태 |` (열 이름이 같아야 한다 — 다르면 읽을 수 없음).
- 행: `| P<번호> | 내용 | 담당 | 승인 게이트 | 상태 |`. 첫 칸이 `P0`, `P1` … 인 줄이 단계다. **끝의 `|` 는 없어도 된다** (사람이 빼먹는다). 칸 안의 `**` 는 지우고 읽는다.
- `담당` 값: `designer` · `ui` · `system` · `tester` · `helper` · `reviewer` · `직접`. 여러 담당은 `system → tester → reviewer` · `ui · system` 처럼 `→` 로 순서, `·` 로 함께. 모르는 말은 글 그대로 보인다.
- `상태` 칸: 비어 있으면 **대기**. 글이 `완료` 로 시작하면 **완료**, `진행 중` 으로 시작하면 **진행 중**. 그 밖의 글은 그대로 보이고 상태는 "알 수 없음". 날짜 · 설명은 뒤에 붙여도 된다 (`완료 (2026-10-18) — 요약`).
- 단계 상세(`## P1. 이름` 절의 `목표` · `작업` · `완료 기준` · `확인 명령`)와 `## 진행 로그` 표(`| 날짜 | 단계 | 한 일 | 결과 |`)도 같은 규칙으로 읽는다. 앱이 필요로 하는 것은 이름 · 목표 한 줄까지이고 나머지는 글로 보인다.

### 6-2. `docs/02-development/handoff.md` — 이어 하기 메모

머리의 목록(`- 스킬:` · `- 요구사항:` · `- 저장소:` · `- 지금 단계:` · `- 마지막 갱신: YYYY-MM-DD HH:MM`)은 `- 키: 값` 줄이다. 키 이름이 같아야 읽는다. 아래 절:

| 절 | 읽는 법 |
|---|---|
| `## 지금 상태` | 첫 글머리. 틀의 값은 `작업자 일하는 중` · `검수 중` · `사용자 답 기다림` · `실행 확인 기다림` · `단계 사이` 중 하나. **이 낱말로 시작하면 상태로 읽고**, 아니면 글 그대로 보이고 상태는 "알 수 없음" (실제 파일은 날짜 · 설명이 붙는다) |
| `## 진행 중인 작업` | 표 `\| 지시서 \| 담당 \| 상태 \| 맡길 때 git \| 보고 \|`. 상태: `맡김` → `돌아옴` → `검수 통과` / `다시 맡김` (뒤에 붙는 글은 설명) |
| `## 사용자에게 기다리는 것` | 글머리 목록. `없음` 이면 비었다 |
| `## 다음 할 일` | 번호 목록 |

지시서 `docs/02-development/briefs/*.md` 의 작업 항목은 `- [ ]` / `- [x]` 줄이다 (진행률 = `[x]` 수 / 전체).

## 7. 질문 · 단계 승인 카드

### 7-1. 질문은 AskUserQuestion

사용자에게 묻는 것은 모두 **선택형 질문 도구(Claude Code 의 `AskUserQuestion`)** 로 한다 (workflow §2 "묻는 형식", D-14). 한 번에 질문 4개까지, 질문마다 선택지 2~4개, 짧은 머리말(12자 이내), 권장안은 첫 번째 선택지에 "(권장)". "기타(직접 입력)" 는 도구가 붙인다. 앱은 이 도구 호출을 선택 카드로 보인다. 도구가 없는 환경의 글 모양(`**1. 질문** — …` / `- A) …`)은 앱이 읽지 않는다.

### 7-2. 단계 승인 카드 — 출력 모양 (초안, P6 에서 확정)

모든 작업은 시작 전 승인을 받는다 (workflow §2). 승인을 물을 때는 `AskUserQuestion` 의 **질문 글(`question`)** 을 아래 모양으로 쓴다. 앱은 `- 무엇을:` · `- 왜 지금:` · `- 산출물:` · `- 하지 않는 것:` 네 줄을 찾아 카드의 네 칸으로 보인다. 네 줄이 다 있으면 승인 카드, 아니면 보통 선택 카드로 보인다.

```
단계 승인 — P4 하네스 설치 · 업데이트
- 무엇을: 앱에서 하네스를 받아 설치하고 원본 업데이트를 미리 본다
- 왜 지금: 고양이 집(P5)이 에이전트 목록을 읽기 전에 하네스가 설치돼 있어야 한다
- 산출물: 설치 화면, 미리보기, 백업 · 되돌리기
- 하지 않는 것: 에이전트 · 스킬 편집 화면 (P9)
```

- 첫 줄은 `단계 승인 — P<번호> <이름>` (머리말 `header` 는 `단계 승인`).
- 선택지: `승인`(권장) · `고쳐서 다시`(범위를 바꾸자) · (기타: 직접 적기). 이름은 같게 둔다.
- 네 줄은 한 줄씩, 줄마다 `- 항목:` 로 시작한다 (칸 안 줄바꿈 없음). 하나라도 빠졌거나 순서가 달라도 찾아 읽지만, 빠진 칸은 "읽을 수 없음" 으로 비워 둔다.

## 8. 바꾼 기록

- **1** (2026-10-18) — 처음. 설치 스크립트 옵션 · JSON · 종료 코드, `custom/` 모양, 백업, 앞머리 필드, 단계 표 · 이어 하기 메모 읽는 법, 질문 · 승인 카드 초안.
- **1** (2026-10-22 보충) — 원본 찾기 규칙 · 링크 → 복사 전환을 명시. 형식 변화 없음.
