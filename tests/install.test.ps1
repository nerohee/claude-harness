# install.ps1 시험 — 임시 폴더를 %USERPROFILE%\.claude · 하네스 폴더로 돌린다. 실제 ~/.claude · ~/.claude-harness 는 건드리지 않는다.
#   powershell -ExecutionPolicy Bypass -File tests\install.test.ps1      (저장소가 \\wsl.localhost\... 에 있어도 된다)
# 하는 일: 예전 install.ps1 과 같은 결과인지, 내 수정 겹치기 · 미리보기 = 설치 · 백업 → 되돌리기 · 실패하면 되돌림 ·
#   install.sh 와 JSON · 설치 결과가 같은지 (WSL 이 있을 때. 환경 변수 HARNESS_TEST_WSL_DISTRO 로 배포판 이름, 기본 Ubuntu-24.04).
# 이 PC 가 심볼릭 링크 권한이 없으면 복사 설치(예전 Windows 방식)를 시험한다. 링크가 되는 환경에서는 링크도 시험한다.
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
$Repo = Split-Path $Here -Parent
$Utf8 = New-Object System.Text.UTF8Encoding $false
[Console]::OutputEncoding = $Utf8
$Tmp = Join-Path ([IO.Path]::GetTempPath()) ('harness-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
[void][IO.Directory]::CreateDirectory($Tmp)
$env:USERPROFILE = Join-Path $Tmp 'userprofile'   # 어디서든 기본 위치로 새어 나가도 실제 ~/.claude 가 아니게
[void][IO.Directory]::CreateDirectory($env:USERPROFILE)
Remove-Item Env:CLAUDE_CONFIG_DIR, Env:CLAUDE_HARNESS_HOME, Env:CLAUDE_HARNESS_NO_SYMLINK -ErrorAction SilentlyContinue
$Distro = if ($env:HARNESS_TEST_WSL_DISTRO) { $env:HARNESS_TEST_WSL_DISTRO } else { 'Ubuntu-24.04' }

$script:Pass = 0; $script:Fail = 0
function Ok([string]$n) { $script:Pass++; Write-Host "  통과: $n" }
function Bad([string]$n, [string]$d = '') { $script:Fail++; Write-Host "  실패: $n"; if ($d) { Write-Host "        $d" } }
function Eq([string]$n, $actual, $expected) { if ("$actual" -ceq "$expected") { Ok $n } else { Bad $n "기대 [$expected] 실제 [$actual]" } }
function IsTrue([string]$n, [bool]$v, [string]$d = '') { if ($v) { Ok $n } else { Bad $n $d } }
function Head([string]$t) { Write-Host ""; Write-Host "[$t]" }

function Get-Snap([string]$dir) {  # 이름 · 종류 · 내용 해시 · 링크 대상 (수정 시각은 빼고). 복사 표시 파일(.install-mode)은 서식이 달라져서 원본 위치(둘째 줄)만 본다
  $rows = New-Object System.Collections.Generic.List[string]
  function Walk([string]$d, [string]$prefix) {
    foreach ($e in (New-Object IO.DirectoryInfo $d).GetFileSystemInfos()) {
      $rel = if ($prefix) { "$prefix/$($e.Name)" } else { $e.Name }
      if ($e.Attributes -band [IO.FileAttributes]::ReparsePoint) { $rows.Add("L $rel -> " + (Get-Item -LiteralPath $e.FullName -Force).Target); continue }
      if ($e.Attributes -band [IO.FileAttributes]::Directory) { $rows.Add("D $rel"); Walk $e.FullName $rel; continue }
      $bytes = [IO.File]::ReadAllBytes($e.FullName)
      if ($e.Name -eq '.install-mode') {
        $lines = ($Utf8.GetString($bytes).TrimStart([char]0xFEFF) -replace "`r", '').Split("`n")
        $rows.Add("F $rel marker:$($lines[0]):$($lines[1])")
      } else {
        $sha = [Security.Cryptography.SHA256]::Create()
        $rows.Add("F $rel " + (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '').Substring(0, 12))
      }
    }
  }
  if (Test-Path -LiteralPath $dir) { Walk $dir '' }
  $arr = [string[]]$rows
  [Array]::Sort($arr, [StringComparer]::Ordinal)
  return $arr
}
function Same-Snap($a, $b) { return (@($a) -join "`n") -ceq (@($b) -join "`n") }

function Copy-Repo([string]$to) {
  robocopy $Repo $to /E /XD .git tests /XF config.local.json /NFL /NDL /NJH /NJS /NP | Out-Null
}
function New-Box([string]$name) {
  $script:Box = Join-Path $Tmp $name
  $script:CL = Join-Path $script:Box 'claude'
  $script:HH = Join-Path $script:Box 'home'
  [void][IO.Directory]::CreateDirectory($script:Box)
  Copy-Repo (Join-Path $script:Box 'repo')
  Copy-Repo (Join-Path $script:Box 'legacy')
  Copy-Item (Join-Path $Here 'fixtures\install-legacy.ps1') (Join-Path $script:Box 'legacy\install.ps1') -Force
}
function Invoke-Script([string]$script, [string[]]$a) {
  $env:CLAUDE_CONFIG_DIR = $script:CL; $env:CLAUDE_HARNESS_HOME = $script:HH
  $o = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script @a 2>$null
  $script:Rc = $LASTEXITCODE
  $script:Out = (@($o) -join "`n")
}
function Run([string[]]$a) { Invoke-Script (Join-Path $script:Box 'repo\install.ps1') $a }
function Run-Legacy([string[]]$a) { Invoke-Script (Join-Path $script:Box 'legacy\install.ps1') $a }
function Get-J { return ($script:Out | ConvertFrom-Json) }
function Put-Custom([string]$rel, [string]$text) {
  $p = Join-Path $script:HH ('custom\' + $rel.Replace('/', '\'))
  [void][IO.Directory]::CreateDirectory((Split-Path -Parent $p))
  [IO.File]::WriteAllBytes($p, $Utf8.GetBytes($text))
}
function Read-File([string]$p) { return $Utf8.GetString([IO.File]::ReadAllBytes($p)) }
function Agent-Text([string]$name, [string]$desc, [string]$who) { return "---`nname: $name`ndescription: $desc`nmodel: sonnet`n---`n`n너는 ${who}다.`n" }

# ── 스크립트 자체 ──
Head '0. 파일 서식 — install.ps1 은 UTF-8 BOM, 셸 · 문서는 LF'
$b = [IO.File]::ReadAllBytes((Join-Path $Repo 'install.ps1'))
IsTrue 'install.ps1 은 UTF-8 BOM 으로 시작' ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
foreach ($f in 'install.ps1', 'install.sh', 'uninstall.sh', 'shared\app-contract.md', 'tests\install.test.sh', 'tests\install.test.ps1') {
  $p = Join-Path $Repo $f
  if (Test-Path -LiteralPath $p) { IsTrue "$f 에 CR 이 없다 (LF)" (-not ([IO.File]::ReadAllBytes($p) -contains 13)) }
}
IsTrue 'tests\install.test.ps1 도 BOM (한글이 깨지지 않게)' (([IO.File]::ReadAllBytes((Join-Path $Here 'install.test.ps1')))[0] -eq 0xEF)

# ═══════════════════════════════════════
Head '1. 내 수정이 없으면 지금과 같다 (예전 install.ps1 과 비교)'
New-Box 'parity'
Run-Legacy @(); $legacyRc = $script:Rc
$legacyTree = Get-Snap $script:CL
$legacyClaude = $script:CL
$script:CL = Join-Path $script:Box 'claude-new'
Run @(); $newRc = $script:Rc
Eq '종료 코드가 같다' $newRc $legacyRc
$newTree = Get-Snap $script:CL
$canLink = (Get-Item -LiteralPath (Join-Path $script:CL 'harness') -Force).Attributes -band [IO.FileAttributes]::ReparsePoint
if ($canLink) {
  IsTrue '(링크 환경) 링크 모양이 같다' ((@($legacyTree | Where-Object { $_ -like 'L *' }) -join "`n").Replace($legacyClaude, '@') -ceq (@($newTree | Where-Object { $_ -like 'L *' }) -join "`n").Replace($script:CL, '@').Replace('legacy', 'repo'))
} else {
  $legacyN = @($legacyTree | Where-Object { $_ -notlike '* harness/install.ps1 *' }) -replace [regex]::Escape((Join-Path $script:Box 'legacy')), '@REPO@'   # install.ps1 자신은 새 것이라 다르다
  $newN = @($newTree | Where-Object { $_ -notlike '* harness/install.ps1 *' }) -replace [regex]::Escape((Join-Path $script:Box 'repo')), '@REPO@'
  Eq '설치된 파일 · 복사본이 예전과 똑같다 (이름 · 내용 · 표시 파일의 원본 위치)' ($newN -join "`n") ($legacyN -join "`n")
}
$agentsSame = $true
foreach ($f in (Get-ChildItem (Join-Path $legacyClaude 'agents'))) { if ([IO.File]::ReadAllText($f.FullName) -cne [IO.File]::ReadAllText((Join-Path $script:CL "agents\$($f.Name)"))) { $agentsSame = $false } }
IsTrue '에이전트 파일이 같다' $agentsSame
IsTrue '저장소에 설정 파일을 만들어 준다 (예전처럼)' (Test-Path (Join-Path $script:Box 'repo\config.local.json'))
Run @('-Plan', '-Json'); $j = Get-J
Eq '설치 뒤 미리보기는 바뀔 것이 없다' $j.same $true
Run @('-Check')
Eq '-Check 가 같다고 한다' $script:Rc 0
Eq '-Check 출력' $script:Out '작업자: 저장소와 같음'
[IO.File]::AppendAllText((Join-Path $script:CL 'agents\harness-helper.md'), "손으로 고침`n")
Run @('-Check')
Eq '고친 작업자는 다름 (종료 코드 1)' $script:Rc 1
Eq '고친 작업자 출력' $script:Out '다름: harness-helper.md'
Remove-Item (Join-Path $script:CL 'agents\harness-tester.md')
[IO.File]::WriteAllText((Join-Path $script:CL 'agents\harness-builder.md'), "x`n")
Run @('-Check')
Eq '빠짐 · 남음도 알린다' $script:Out "다름: harness-helper.md`n빠짐: harness-tester.md`n남음 (예전 작업자): harness-builder.md"
Run @()
Eq '다시 설치하면 고쳐진다' $script:Rc 0
Run @('-Check'); Eq '그 뒤 -Check' $script:Out '작업자: 저장소와 같음'

# ═══════════════════════════════════════
Head '2. 내 수정 겹치기 · 미리보기 = 설치'
New-Box 'overlay'
Put-Custom 'agents/harness-builder-ui.values.yml' "# 값만`neffort: high`nmodel: opus`nmaxTurns: 20`n"
Put-Custom 'agents/harness-builder-ui.append.md' "## 내 규칙`n- 시험 이름은 한국어로.`n"
Put-Custom 'agents/translator.md' ((Agent-Text 'translator' '문서를 영어로 옮긴다' '번역가') + "`n")
Put-Custom 'skills/mine/SKILL.md' "---`nname: mine`ndescription: 내 스킬`n---`n`n본문`n"
Put-Custom 'skills/web-lite/SKILL.values.yml' "effort: low`n"
Put-Custom 'config.local.json' "{`"language`":`"ko`",`"mine`":true}`n"
Put-Custom 'agent-cats.json' '{"version":1,"agents":{}}'
Put-Custom '.git/HEAD' "x`n"
Run @('-OriginHash', 'agents/harness-designer.md'); $hashDesigner = $script:Out.Trim()
Eq '원본 해시는 64글자' $hashDesigner.Length 64
Put-Custom 'agents/harness-designer.md' ((Read-File (Join-Path $script:Box 'repo\agents\harness-designer.md')) -replace '(?m)^description: .*$', 'description: 내 디자이너 — 따뜻한 게임 UI')
Put-Custom 'agents/harness-designer.md.origin' "$hashDesigner`n"
Run @('-Plan', '-Json'); $plan = $script:Out; $j = Get-J
Eq '미리보기 종료 코드' $script:Rc 0
Eq '방식은 복사' $j.mode 'copy'
Eq '내 수정 종류' ((@($j.custom.items | ForEach-Object { $_.kind } | Sort-Object -Unique)) -join ',') 'append,config,new,replace,values'
Eq '원본 안 바뀜' (@($j.custom.items | Where-Object { $_.kind -eq 'replace' } | ForEach-Object { $_.originChanged }) -join ',') 'False'
IsTrue '미리보기는 아무것도 쓰지 않는다' (-not (Test-Path $script:CL))
IsTrue '미리보기는 백업 폴더도 만들지 않는다' (-not (Test-Path (Join-Path $script:HH 'backups')))
Run @('-Json'); $install = $script:Out
Eq '설치 종료 코드' $script:Rc 0
function Shape($json) { $d = $json | ConvertFrom-Json; return (($d.changes | ForEach-Object { "$($_.path)|$($_.action)|$($_.type)|$($_.reason)" }) -join "`n") + "`n" + ($d.counts | ConvertTo-Json -Compress) }
Eq '미리보기와 실제 설치가 같은 목록' (Shape $plan) (Shape $install)
Run @('-Plan', '-Json'); Eq '설치 뒤 미리보기는 바뀔 것이 없다' (Get-J).same $true

$ui = Read-File (Join-Path $script:CL 'agents\harness-builder-ui.md')
IsTrue '값 바꾸기 — effort' ($ui -match '(?m)^effort: high$')
IsTrue '값 바꾸기 — model' ($ui -match '(?m)^model: opus$')
IsTrue '값 바꾸기 — 없던 키는 앞머리 끝에' ($ui -match '(?s)^---\n.*?\nmaxTurns: 20\n.*?---\n')
IsTrue '덧붙이기 — 끝에 내 규칙' ($ui.EndsWith("## 내 규칙`n- 시험 이름은 한국어로.`n"))
IsTrue '공통 규칙 · 가드 hook 은 그대로 붙는다' ($ui.Contains('builder-guard.sh'))
IsTrue '새 에이전트 + 가드 hook' ((Read-File (Join-Path $script:CL 'agents\translator.md')).Contains('builder-guard.sh'))
IsTrue '통째 바꾸기 적용' ((Read-File (Join-Path $script:CL 'agents\harness-designer.md')).Contains('내 디자이너 — 따뜻한 게임 UI'))
IsTrue '에이전트 파일에 CR 이 없다' (-not ([IO.File]::ReadAllBytes((Join-Path $script:CL 'agents\harness-builder-ui.md')) -contains 13))
$marker = (Read-File (Join-Path $script:CL 'harness\.install-mode')).Split("`n")
Eq '복사 설치 표시' $marker[0] 'copy'
Eq '표시에 원본 위치' $marker[1] (Join-Path $script:Box 'repo')
IsTrue '복사본에도 값 바꾸기' ((Read-File (Join-Path $script:CL 'harness\agents\harness-builder-ui.md')) -match '(?m)^effort: high$')
IsTrue '복사본에 내 스킬' (Test-Path (Join-Path $script:CL 'harness\skills\mine\SKILL.md'))
IsTrue '설정은 custom 에서 복사본으로' ((Read-File (Join-Path $script:CL 'harness\config.local.json')) -ceq "{`"language`":`"ko`",`"mine`":true}`n")
IsTrue '앱 전용 파일(agent-cats.json)은 설치하지 않는다' (-not (Test-Path (Join-Path $script:CL 'harness\agent-cats.json')))
IsTrue '.git 은 복사하지 않는다' (-not (Test-Path (Join-Path $script:CL 'harness\.git')))
Eq '상태 파일 — 새로 만든 것만' ((Read-File (Join-Path $script:CL '.harness-installed')).TrimEnd("`n")) "agent translator.md`nskill mine"
IsTrue '원본 저장소는 그대로' (-not (Test-Path (Join-Path $script:Box 'repo\config.local.json')))
Eq '원본 저장소의 에이전트도 그대로' (Read-File (Join-Path $script:Box 'repo\agents\harness-builder-ui.md')) (Read-File (Join-Path $script:Box 'legacy\agents\harness-builder-ui.md'))
IsTrue '스킬 (링크 또는 복사)' (Test-Path (Join-Path $script:CL 'skills\mine\SKILL.md'))
IsTrue '스킬 값 바꾸기가 스킬에 닿는다' ((Read-File (Join-Path $script:CL 'skills\web-lite\SKILL.md')) -match '(?m)^effort: low$')

Head '2-2. 내 수정에서 에이전트 · 스킬을 지우면 설치에서도 빠진다'
Remove-Item (Join-Path $script:HH 'custom\agents\translator.md'); Remove-Item (Join-Path $script:HH 'custom\skills\mine') -Recurse
Run @()
IsTrue '새 에이전트가 지워짐' (-not (Test-Path (Join-Path $script:CL 'agents\translator.md')))
IsTrue '새 스킬이 지워짐' (-not (Test-Path (Join-Path $script:CL 'skills\mine')))
IsTrue '상태 파일이 지워짐' (-not (Test-Path (Join-Path $script:CL '.harness-installed')))
IsTrue '하네스 에이전트는 남음' (Test-Path (Join-Path $script:CL 'agents\harness-helper.md'))

# ═══════════════════════════════════════
Head '3. 원본 바뀜'
New-Box 'origin'
Put-Custom 'agents/harness-designer.md' ((Read-File (Join-Path $script:Box 'repo\agents\harness-designer.md')) + "# 내 수정`n")
Run @('-OriginHash', 'agents/harness-designer.md'); $h1 = $script:Out.Trim()
Put-Custom 'agents/harness-designer.md.origin' "$h1`n"
Run @('-Plan', '-Json'); $j = Get-J
Eq '원본 그대로면 바뀜 아님' (@($j.custom.items | Where-Object { $_.kind -eq 'replace' } | ForEach-Object { $_.originChanged }) -join ',') 'False'
[IO.File]::AppendAllText((Join-Path $script:Box 'repo\agents\harness-designer.md'), "원본에서 한 줄 고침`n")
Run @('-Plan', '-Json'); $j = Get-J
Eq '원본이 바뀌면 바뀜' (@($j.custom.items | Where-Object { $_.kind -eq 'replace' } | ForEach-Object { $_.originChanged }) -join ',') 'True'
Eq '원본 바뀜 목록' (@($j.originChanged | ForEach-Object { "$($_.path):$($_.recorded -eq $h1):$($_.current -ne $_.recorded)" }) -join ',') 'agents/harness-designer.md:True:True'
Run @('-Plan'); IsTrue '사람용 미리보기에도 원본 바뀜' ($script:Out.Contains('원본 바뀜: agents/harness-designer.md'))
Run @(); Eq '원본이 바뀌어도 설치는 내 것으로 끝난다' $script:Rc 0
IsTrue '내 것을 그대로 쓴다' ((Read-File (Join-Path $script:CL 'agents\harness-designer.md')).Contains("# 내 수정`n"))
Run @('-OriginHash', 'agents/harness-designer.md'); $h2 = $script:Out.Trim()
IsTrue '새 원본 해시는 다르다' ($h1 -cne $h2)
Put-Custom 'agents/harness-designer.md.origin' "$h2`n"
Run @('-Plan', '-Json'); Eq '해시를 새로 적으면 바뀜이 풀린다' (@((Get-J).originChanged)).Count 0
Remove-Item (Join-Path $script:HH 'custom\agents\harness-designer.md.origin')
Run @('-Plan', '-Json'); $j = Get-J
Eq '해시가 없으면 알 수 없음(null)' ($null -eq (@($j.custom.items | Where-Object { $_.kind -eq 'replace' }))[0].originChanged) $true
Eq '해시가 없으면 알림' (@($j.warnings | ForEach-Object { $_.reason }) -join ',') 'noOriginHash'
# CRLF 로 저장된 내 파일도 LF 로
New-Box 'crlf'
Put-Custom 'agents/harness-helper.md' "---`r`nname: harness-helper`r`ndescription: 내 도우미`r`nmodel: haiku`r`n---`r`n`r`n내 도우미다.`r`n"
Run @(); Eq 'CRLF 로 저장된 통째 바꾸기도 설치된다' $script:Rc 0
IsTrue '설치된 에이전트에 CR 이 없다' (-not ([IO.File]::ReadAllBytes((Join-Path $script:CL 'agents\harness-helper.md')) -contains 13))

# ═══════════════════════════════════════
Head '4. 백업 · 되돌리기 (하네스와 상관없는 파일은 읽지도 백업하지도 않는다)'
New-Box 'backup'
Run-Legacy @()
[void][IO.Directory]::CreateDirectory((Join-Path $script:CL 'projects\p1')); [void][IO.Directory]::CreateDirectory((Join-Path $script:CL 'plugins'))
[void][IO.Directory]::CreateDirectory((Join-Path $script:CL 'skills\my-own'))
foreach ($kv in @(@('.credentials.json', '{"secret":"x"}'), @('history.jsonl', '기록'), @('settings.json', '{}'), @('projects\p1\s.jsonl', '세션'), @('skills\my-own\SKILL.md', '내 스킬'), @('agents\my-own.md', '내 에이전트'), @('plugins\x', '플러그인'))) {
  [IO.File]::WriteAllBytes((Join-Path $script:CL $kv[0]), $Utf8.GetBytes($kv[1]))
}
$before = Get-Snap $script:CL
$repoBefore = Get-Snap (Join-Path $script:Box 'repo')
# 읽지 않는 것을 확인하려고 인증 · 기록 파일을 다른 프로세스가 독점으로 잡아 둔다 (읽으려 하면 실패)
$locks = @()
foreach ($f in '.credentials.json', 'history.jsonl', 'projects\p1\s.jsonl') { $locks += New-Object IO.FileStream (Join-Path $script:CL $f), ([IO.FileMode]::Open), ([IO.FileAccess]::Read), ([IO.FileShare]::None) }
Put-Custom 'agents/harness-builder-ui.values.yml' "effort: high`n"
Put-Custom 'agents/translator.md' ((Agent-Text 'translator' '번역' '번역가') + "`n")
Run @('-Json'); $j = Get-J
foreach ($l in $locks) { $l.Dispose() }
Eq '인증 · 기록 파일을 못 읽는 상태에서도 설치된다 (읽지 않는다)' $script:Rc 0
$bk = $j.backup.id
IsTrue '백업 폴더가 생겼다' (Test-Path (Join-Path $script:HH "backups\$bk\manifest.txt"))
$bkList = @((Get-ChildItem (Join-Path $script:HH "backups\$bk") -Recurse -File | ForEach-Object { $_.FullName.Substring((Join-Path $script:HH "backups\$bk").Length + 1) }))
IsTrue '백업에 인증 · 기록 · 설정이 없다' (-not ($bkList -match 'credentials|history|settings|projects|plugins|my-own'))
IsTrue '목록에도 없다' (-not ((Read-File (Join-Path $script:HH "backups\$bk\manifest.txt")) -match 'credentials|history|settings|projects|plugins|my-own'))
Eq '하네스와 상관없는 파일은 그대로' ((Read-File (Join-Path $script:CL '.credentials.json')) + (Read-File (Join-Path $script:CL 'agents\my-own.md'))) '{"secret":"x"}내 에이전트'
Run @('-Backups', '-Json'); $j = Get-J
Eq '백업 목록' (@($j.backups | ForEach-Object { "$($_.id -eq $bk):$($_.command):$($_.readable)" }) -join ',') 'True:install:True'
Run @('-Restore', $bk, '-Plan', '-Json'); Eq '되돌리기 미리보기 dryRun' (Get-J).dryRun $true
Same-Snap (Get-Snap $script:CL) (Get-Snap $script:CL) | Out-Null
$mid = Get-Snap $script:CL; Run @('-Restore', $bk, '-Plan') | Out-Null
IsTrue '미리보기는 아무것도 바꾸지 않는다' (Same-Snap $mid (Get-Snap $script:CL))
Run @('-Restore', $bk, '-Json'); Eq '되돌리기 성공' $script:Rc 0
IsTrue '되돌린 뒤 설치 전과 똑같다 (이름 · 내용)' (Same-Snap $before (Get-Snap $script:CL)) ((Compare-Object @($before) @(Get-Snap $script:CL) | ForEach-Object { $_.InputObject }) -join ' / ')
Run @('-Restore', $bk, '-Plan', '-Json'); $j = Get-J
Eq '되돌린 뒤 다시 되돌릴 것이 없다' $j.same $true
Run @('-Restore', $bk)
IsTrue '두 번 되돌려도 같다' (Same-Snap $before (Get-Snap $script:CL))
IsTrue '되돌리기가 원본 저장소를 건드리지 않는다' (Same-Snap $repoBefore (Get-Snap (Join-Path $script:Box 'repo')))
Run @(); $s1 = Get-Snap $script:CL
Run @(); $s2 = Get-Snap $script:CL
IsTrue '두 번 설치해도 같다' (Same-Snap $s1 $s2)
Eq '같은 일이면 백업을 더 만들지 않는다' @(Get-ChildItem (Join-Path $script:HH 'backups') -Directory).Count 2
Remove-Item (Join-Path $script:HH 'custom') -Recurse -Force
Run @('-Json'); $j = Get-J
$bk2 = $j.backup.id
IsTrue '내 수정을 지우면 내 에이전트도 지워진다' (-not (Test-Path (Join-Path $script:CL 'agents\translator.md')))
Run @('-Restore', $bk2); IsTrue '그 설치를 되돌리면 내 에이전트가 돌아온다' (Test-Path (Join-Path $script:CL 'agents\translator.md'))
Run @('-Restore', $bk)
IsTrue '첫 백업으로 되돌리면 처음 상태' (Same-Snap $before (Get-Snap $script:CL))

Head '4-3. 처음 설치한 것을 되돌리면 ~/.claude 가 비어 있다 (폴더도 새로 만든 것은 지운다)'
New-Box 'fresh'
Put-Custom 'agents/translator.md' ((Agent-Text 'translator' '번역' '번역가') + "`n")
Run @('-Json'); $fb = (Get-J).backup.id
Run @('-Restore', $fb, '-Json'); Eq '처음 설치 되돌리기 성공' $script:Rc 0
Eq '하네스 파일 · 폴더가 하나도 남지 않는다' @(Get-ChildItem $script:CL -Force).Count 0
New-Box 'fresh2'
Run @('-Json'); $fb = (Get-J).backup.id
Run @('-Restore', $fb, '-Json'); Eq '내 수정 없이 처음 설치해도 되돌리면 비어 있다' @(Get-ChildItem $script:CL -Force).Count 0

# ═══════════════════════════════════════
Head '5. 중간에 실패하면 — 되돌리고 알린다'
New-Box 'fail'
Run-Legacy @()
$before = Get-Snap $script:CL
[IO.File]::AppendAllText((Join-Path $script:Box 'repo\agents\harness-helper.md'), "고침`n")
[IO.File]::AppendAllText((Join-Path $script:Box 'repo\agents\harness-tester.md'), "고침`n")
# 설치할 파일 하나를 다른 쪽이 독점으로 잡고 있다 (EBUSY 처럼)
$held = New-Object IO.FileStream (Join-Path $script:CL 'agents\harness-tester.md'), ([IO.FileMode]::Open), ([IO.FileAccess]::Read), ([IO.FileShare]::Read)
Run @('-Json'); $j = Get-J
$held.Dispose()
Eq '실패하면 종료 코드 3' $script:Rc 3
Eq '오류 코드' $j.error.code 'applyFailed'
Eq '되돌렸다고 알린다' $j.rolledBack $true
IsTrue '백업 번호를 알려 준다' ($null -ne $j.backup)
IsTrue '실패 뒤에도 설치 전과 똑같다' (Same-Snap $before (Get-Snap $script:CL)) ((Compare-Object @($before) @(Get-Snap $script:CL) | ForEach-Object { $_.InputObject }) -join ' / ')
IsTrue '임시 파일이 남지 않는다' (@(Get-ChildItem $script:CL -Recurse -Force | Where-Object { $_.Name -like '*.harness-tmp.*' }).Count -eq 0)
IsTrue '잠금이 남지 않는다' (-not (Test-Path (Join-Path $script:CL '.harness-install.lock')))
Run @(); Eq '문제를 고치면 다시 설치된다' $script:Rc 0

# ═══════════════════════════════════════
Head '6. 내 수정 폴더가 잘못됐으면 아무것도 쓰지 않고 멈춘다'
function Bad-Case([string]$name, [string]$reason) {
  Run @('-Json'); $j = Get-J
  Eq "$name — 종료 코드 2" $script:Rc 2
  Eq "$name — 사유 $reason" ((@($j.problems | ForEach-Object { $_.reason } | Sort-Object -Unique)) -join ',') $reason
  IsTrue "$name — ~/.claude 를 만들지 않았다" (-not (Test-Path $script:CL))
  IsTrue "$name — 백업도 만들지 않았다" (-not (Test-Path (Join-Path $script:HH 'backups')))
}
New-Box 'bad2'; Put-Custom 'agents/harness-helper.values.yml' "effort high`n"; Bad-Case '값 모양' 'badValues'
New-Box 'bad3'; Put-Custom 'agents/harness-helper.values.yml' "name: other`n"; Bad-Case 'name 바꾸기' 'badValues'
New-Box 'bad4'; Put-Custom 'agents/nothing.values.yml' "effort: high`n"; Bad-Case '없는 원본' 'targetMissing'
New-Box 'bad5'; Put-Custom 'agents/_common/rules.md' 'x'; Bad-Case '공통 규칙 바꾸기' 'unsupported'
New-Box 'bad6'; Put-Custom 'agents/sub/x.md' 'x'; Bad-Case 'agents 하위 폴더' 'unsupported'
New-Box 'bad7'; Put-Custom 'skills/loose.md' 'x'; Bad-Case 'skills 바로 아래 파일' 'unsupported'
New-Box 'bad8'; Put-Custom 'agents/harness-helper.md' (Read-File (Join-Path $script:Box 'repo\agents\harness-helper.md')); Put-Custom 'agents/harness-helper.md.origin' 'xyz'; Bad-Case '원본 해시 모양' 'badOrigin'
New-Box 'bad9'; Put-Custom 'agents/oops.md' "---`nname: other`n---`n"; Bad-Case '새 에이전트 틀(name)' 'invalidAgent'
New-Box 'bad10'; Put-Custom 'agents/oops.md' "---`nname: oops`nhooks:`n  x: y`n---`n"; Bad-Case '새 에이전트 틀(hooks)' 'invalidAgent'
New-Box 'bad11'; Put-Custom 'agents/harness-helper.values.yml' "tools: A`n"
[IO.File]::WriteAllBytes((Join-Path $script:Box 'repo\agents\harness-helper.md'), $Utf8.GetBytes("---`nname: harness-helper`ntools:`n  - A`n  - B`n---`n본문`n"))
Bad-Case '여러 줄 값' 'badValues'
New-Box 'bad12'; Put-Custom 'agents/harness-helper.values.yml' "effort: high`neffort: low`n"; Bad-Case '키 중복' 'badValues'

# ═══════════════════════════════════════
Head '7. 동시에 두 번 · 낯선 것이 있을 때'
New-Box 'lock'
[void][IO.Directory]::CreateDirectory($script:CL)
$lock = New-Object IO.FileStream (Join-Path $script:CL '.harness-install.lock'), ([IO.FileMode]::CreateNew), ([IO.FileAccess]::ReadWrite), ([IO.FileShare]::None), 1, ([IO.FileOptions]::DeleteOnClose)
Run @('-Json'); $j = Get-J
Eq '다른 설치가 돌고 있으면 종료 코드 2' $script:Rc 2
Eq '오류 코드 busy' $j.error.code 'busy'
IsTrue '아무것도 설치하지 않았다' (-not (Test-Path (Join-Path $script:CL 'agents')))
Run @('-Plan', '-Json'); Eq '미리보기는 잠금과 상관없이 돈다' $script:Rc 0
$lock.Dispose()
Run @('-Json'); Eq '잠금이 풀리면 설치된다' $script:Rc 0
IsTrue '끝나면 잠금을 치운다' (-not (Test-Path (Join-Path $script:CL '.harness-install.lock')))

New-Box 'foreign'
[void][IO.Directory]::CreateDirectory((Join-Path $script:CL 'harness')); [void][IO.Directory]::CreateDirectory((Join-Path $script:CL 'skills\web-full'))
[IO.File]::WriteAllText((Join-Path $script:CL 'harness\mine.txt'), '내 것', $Utf8); [IO.File]::WriteAllText((Join-Path $script:CL 'skills\web-full\SKILL.md'), '내 스킬', $Utf8)
Run @('-Json'); $j = Get-J
Eq '낯선 하네스 폴더가 있으면 멈춘다 (복사 설치)' $script:Rc 2
Eq '사유 harnessNotOurs' (@($j.problems | ForEach-Object { $_.reason }) -join ',') 'harnessNotOurs'
Eq '낯선 파일은 그대로' ((Read-File (Join-Path $script:CL 'harness\mine.txt')) + (Read-File (Join-Path $script:CL 'skills\web-full\SKILL.md'))) '내 것내 스킬'
New-Box 'collide'
[void][IO.Directory]::CreateDirectory((Join-Path $script:CL 'agents')); [IO.File]::WriteAllText((Join-Path $script:CL 'agents\translator.md'), '내 번역가', $Utf8)
Put-Custom 'agents/translator.md' ((Agent-Text 'translator' '번역' '번역가') + "`n")
Run @('-Json'); $j = Get-J
Eq '새 에이전트가 내 파일과 이름이 같으면 건너뛴다' (@($j.changes | Where-Object { $_.action -eq 'skip' } | ForEach-Object { "$($_.path):$($_.reason)" }) -join ',') 'agents/translator.md:notOurs'
Eq '내 파일은 그대로' (Read-File (Join-Path $script:CL 'agents\translator.md')) '내 번역가'
New-Box 'tamper'
Run-Legacy @()
[IO.File]::WriteAllText((Join-Path $script:CL 'mine.txt'), '내 것', $Utf8); [void][IO.Directory]::CreateDirectory((Join-Path $script:CL 'projects'))
[IO.File]::WriteAllText((Join-Path $script:CL 'projects\a.jsonl'), '기록', $Utf8); [IO.File]::WriteAllText((Join-Path $script:CL '.install-mode'), 'x')
[IO.File]::WriteAllText((Join-Path $script:CL '.harness-installed'), "skill ..`nagent ..md`nskill ../x`nskill /etc`n")   # 고쳐 둔 상태 파일 — 읽지 않는다
Run @('-Json'); Eq '고쳐 둔 상태 파일이 있어도 설치된다' $script:Rc 0
Eq '상태 파일의 이상한 이름으로 아무것도 지우지 않는다' ((Read-File (Join-Path $script:CL 'mine.txt')) + (Read-File (Join-Path $script:CL 'projects\a.jsonl'))) '내 것기록'
IsTrue '~/.claude 안의 다른 것도 그대로' ((Test-Path (Join-Path $script:CL '.install-mode')) -and (Test-Path (Join-Path $script:CL 'skills')) -and (Test-Path (Join-Path $script:CL 'agents')))

# ═══════════════════════════════════════
Head '7-2. 복사본 폴더가 링크(정션)로 바뀌어 있어도 링크를 따라가지 않는다'
New-Box 'junction'
Put-Custom 'agents/harness-builder-ui.values.yml' "effort: high`n"
Run @('-Json'); $bkj = (Get-J).backup.id
Remove-Item (Join-Path $script:CL 'harness') -Recurse -Force
cmd.exe /c mklink /J (Join-Path $script:CL 'harness') (Join-Path $script:Box 'repo') | Out-Null
$repoBefore = Get-Snap (Join-Path $script:Box 'repo')
Run @('-Restore', $bkj, '-Plan', '-Json'); $j = Get-J
Eq '링크 아래의 복사본 파일은 지울 것으로 잡지 않는다' (@($j.changes | Where-Object { $_.path -like 'harness/*' }).Count) 0
Run @('-Restore', $bkj)
IsTrue '되돌려도 원본 저장소는 그대로 (링크를 따라가 지우지 않는다)' (Same-Snap $repoBefore (Get-Snap (Join-Path $script:Box 'repo')))
if (-not (Test-Path (Join-Path $script:CL 'harness'))) { cmd.exe /c mklink /J (Join-Path $script:CL 'harness') (Join-Path $script:Box 'repo') | Out-Null }
Run @('-Json'); $j = Get-J
Eq '하네스 자리가 링크(정션)여도 복사 설치가 된다' $script:Rc 0
IsTrue '그 설치가 링크를 따라 원본 저장소에 쓰지 않는다' (Same-Snap $repoBefore (Get-Snap (Join-Path $script:Box 'repo')))
IsTrue '링크는 지워지고 복사본이 됐다' (((Get-Item (Join-Path $script:CL 'harness') -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -and (Test-Path (Join-Path $script:CL 'harness\.install-mode')))
IsTrue '지금 가리키던 원본을 알린다 (existingSource)' ("$($j.existingSource)" -like '*\repo') "existingSource = $($j.existingSource)"

# ═══════════════════════════════════════
Head '8. 지우기 (-Uninstall)'
New-Box 'uninstall'
Run-Legacy @()
[void][IO.Directory]::CreateDirectory((Join-Path $script:CL 'skills\my-own')); [IO.File]::WriteAllText((Join-Path $script:CL 'skills\my-own\SKILL.md'), '내 스킬', $Utf8); [IO.File]::WriteAllText((Join-Path $script:CL 'settings.json'), '{}')
$before = Get-Snap $script:CL
Run @('-Uninstall', '-Plan', '-Json'); $j = Get-J
$agentsGone = 'agents/harness-builder-system.md,agents/harness-builder-ui.md,agents/harness-designer.md,agents/harness-helper.md,agents/harness-reviewer.md,agents/harness-tester.md'
Eq '지우기 미리보기 — 지울 에이전트' ((@($j.changes | Where-Object { $_.action -eq 'remove' -and $_.path -match '^agents/' } | ForEach-Object { $_.path } | Sort-Object -Unique)) -join ',') $agentsGone
IsTrue '지우기 미리보기 — 하네스 복사본(또는 링크)도 지운다' (@($j.changes | Where-Object { $_.action -eq 'remove' -and ($_.path -eq 'harness' -or $_.path -like 'harness/*') }).Count -gt 0)
IsTrue '미리보기는 아무것도 지우지 않는다' (Same-Snap $before (Get-Snap $script:CL))
Run @('-Uninstall'); Eq '지우기 성공' $script:Rc 0
IsTrue '끝 줄' ($script:Out.Split("`n")[-1].Trim() -ceq '완료.')
IsTrue '하네스 · 에이전트가 지워짐' (-not (Test-Path (Join-Path $script:CL 'harness')) -and -not (Test-Path (Join-Path $script:CL 'agents\harness-helper.md')))
Eq '내 스킬 · 설정은 그대로' ((Read-File (Join-Path $script:CL 'skills\my-own\SKILL.md')) + (Read-File (Join-Path $script:CL 'settings.json'))) '내 스킬{}'
IsTrue '저장소는 그대로' (Test-Path (Join-Path $script:Box 'repo\agents\harness-helper.md'))
Run @('-Backups', '-Json'); $j = Get-J
Eq '지우기도 백업 (명령 이름)' $j.backups[0].command 'uninstall'
Run @('-Restore', $j.backups[0].id)
IsTrue '지운 것도 되돌릴 수 있다' (Same-Snap $before (Get-Snap $script:CL))

# ═══════════════════════════════════════
Head '9. 잘못된 사용 · 입력 검사'
New-Box 'args'
Run @('-Json'); $bkA = (Get-J).backup.id
Run @('-Restore', '../x', '-Json'); Eq '백업 번호에 경로를 못 쓴다' $script:Rc 2
Run @('-Restore', '2020-01-01_000000', '-Json'); Eq '없는 백업' (Get-J).error.code 'noBackup'
Run @('-Check', '-Uninstall', '-Json'); Eq '옵션이 겹치면 오류' (Get-J).error.code 'badArgs'
Run @('-OriginHash', '../x', '-Json'); Eq '원본 해시 — 경로 밖' (Get-J).error.code 'badArgs'
Run @('-OriginHash', 'nothing.md', '-Json'); Eq '원본 해시 — 없는 파일' (Get-J).error.code 'notFound'
$mf = Join-Path $script:HH "backups\$bkA\manifest.txt"
$keep = Read-File $mf
[IO.File]::AppendAllText($mf, "add`tfile`t../../outside.txt`t`n")
Run @('-Restore', $bkA, '-Json'); Eq '목록에 밖으로 나가는 경로가 있으면 거부' (Get-J).error.code 'badBackup'
[IO.File]::WriteAllText($mf, $keep + "add`tfile`tsettings.json`t`n")
Run @('-Restore', $bkA, '-Json'); Eq '하네스가 다루지 않는 자리도 거부' (Get-J).error.code 'badBackup'
[IO.File]::WriteAllText($mf, ($keep -replace '(?m)^# claudeDir: .*$', '# claudeDir: C:\somewhere\else'))
Run @('-Restore', $bkA, '-Json'); Eq '다른 대상의 백업은 거부' (Get-J).error.code 'wrongTarget'

# ═══════════════════════════════════════
Head '10. 한글 · 공백이 든 경로 · UNC 에서 돌리기'
$kor = Join-Path $Tmp '한글 상자'
New-Box '한글 상자'
Put-Custom 'agents/harness-builder-ui.values.yml' "effort: high`n"
Run @('-Json'); $j = Get-J
Eq '한글 경로에서 설치' $script:Rc 0
Eq 'JSON 의 경로가 그대로' $j.claudeDir $script:CL
IsTrue '한글 경로 설치 결과' ((Read-File (Join-Path $script:CL 'agents\harness-builder-ui.md')) -match '(?m)^effort: high$')
if ($Repo.StartsWith('\\')) {
  New-Box 'unc'
  Invoke-Script (Join-Path $Repo 'install.ps1') @('-Plan', '-Json'); $j = Get-J
  Eq 'UNC 경로의 install.ps1 도 돈다 (미리보기)' $script:Rc 0
  Eq 'UNC — 원본 위치' $j.repo $Repo
  IsTrue 'UNC 미리보기는 아무것도 쓰지 않는다' (-not (Test-Path $script:CL))
}

# ═══════════════════════════════════════
Head '11. install.sh 와 같은 JSON · 같은 설치 결과 (WSL)'
$wslOk = $false
try { $v = (& wsl.exe -d $Distro --exec bash -c 'echo ok' 2>$null); $wslOk = ("$v".Trim() -eq 'ok') } catch { }
if (-not $wslOk) { Write-Host "  건너뜀: WSL($Distro)을 쓸 수 없다" }
else {
  function Wsl-Path([string]$p) { return ("$(& wsl.exe -d $Distro --exec wslpath -u $p)").Trim() }
  New-Box 'cross'
  $b = $script:Box
  foreach ($n in 'psc', 'psh', 'shc', 'shh') { [void][IO.Directory]::CreateDirectory((Join-Path $b $n)) }
  $script:HH = Join-Path $b 'psh'; $script:CL = Join-Path $b 'psc'
  Put-Custom 'agents/harness-builder-ui.values.yml' "effort: high`nmodel: opus`n"
  Put-Custom 'agents/harness-builder-ui.append.md' "## 내 규칙`r`n- 시험 이름은 한국어로.`r`n"
  Put-Custom 'agents/translator.md' ((Agent-Text 'translator' '번역' '번역가') + "`n")
  Put-Custom 'skills/mine/SKILL.md' "---`nname: mine`ndescription: 내 스킬`n---`n`n본문`n"
  Put-Custom 'skills/web-lite/SKILL.values.yml' "effort: low`n"
  Put-Custom 'config.local.json' "{`"language`":`"ko`"}`n"
  Put-Custom 'agent-cats.json' '{"version":1,"agents":{}}'
  Put-Custom 'shared/extra.md' "새 공유 문서`n"
  Put-Custom 'shared/workflow.append.md' "`n## 내 워크플로 메모`n- 한 줄`n"
  Run @('-OriginHash', 'agents/harness-designer.md'); $dh = $script:Out.Trim()
  Put-Custom 'agents/harness-designer.md' ((Read-File (Join-Path $b 'repo\agents\harness-designer.md')) + "# 내 수정`n")
  Put-Custom 'agents/harness-designer.md.origin' "$dh`n"
  Put-Custom 'agents/harness-tester.md' ((Read-File (Join-Path $b 'repo\agents\harness-tester.md')) + "# 내 수정`n")   # 해시 없이 통째로 — 알림
  Copy-Item (Join-Path $b 'psh\custom') (Join-Path $b 'shh\custom') -Recurse
  $wRepo = Wsl-Path (Join-Path $b 'repo\install.sh'); $wCl = Wsl-Path (Join-Path $b 'shc'); $wHh = Wsl-Path (Join-Path $b 'shh')
  function Run-Sh([string[]]$a) {
    $cmd = "CLAUDE_CONFIG_DIR='$wCl' CLAUDE_HARNESS_HOME='$wHh' CLAUDE_HARNESS_NO_SYMLINK=1 bash '$wRepo' " + ($a -join ' ')
    $o = & wsl.exe -d $Distro --exec bash -c $cmd 2>$null
    $script:ShRc = $LASTEXITCODE; $script:ShOut = (@($o) -join "`n")
  }
  $env:CLAUDE_HARNESS_NO_SYMLINK = '1'   # 링크가 되는 PC 에서도 같은 길(복사)로 맞춘다
  function Norm-Json([string]$json) {
    $d = $json | ConvertFrom-Json
    $d.claudeDir = '<C>'; $d.harnessHome = '<H>'; $d.repo = '<R>'
    if ($d.existingSource) { $d.existingSource = '<E>' }
    $d.custom.dir = '<D>'
    if ($d.backup) { $d.backup.id = '<B>'; $d.backup.dir = '<BD>' }
    foreach ($x in $d.backups) { $x.id = '<B>'; $x.createdAt = '<T>' }
    foreach ($p in $d.problems) { $p.detail = '<detail>' }
    return ($d | ConvertTo-Json -Depth 20 -Compress)
  }
  function Cmp-Json([string]$name, [string[]]$a) {
    Run ($a + '-Json') | Out-Null; $ps = $script:Out; $psRc = $script:Rc
    $map = @{ '-Plan' = '--plan'; '-Check' = '--check'; '-Backups' = '--backups'; '-Restore' = '--restore'; '-Uninstall' = '--uninstall'; '-OriginHash' = '--origin-hash' }
    $shArgs = @(); foreach ($x in $a) { if ($map.ContainsKey($x)) { $shArgs += $map[$x] } else { $shArgs += $x } }
    Run-Sh ($shArgs + '--json')
    Eq "$name — 종료 코드" $psRc $script:ShRc
    $n1 = Norm-Json $ps; $n2 = Norm-Json $script:ShOut
    if ($n1 -ceq $n2) { Ok "$name — JSON 이 같다" } else { Bad "$name — JSON 이 다르다" ("`nPS: $n1`nSH: $n2") }
  }
  Cmp-Json '미리보기' @('-Plan')
  Cmp-Json '확인(처음)' @('-Check')
  Cmp-Json '백업 목록(없음)' @('-Backups')
  Cmp-Json '원본 해시' @('-OriginHash', 'agents/harness-helper.md')
  Cmp-Json '원본 해시(없는 파일)' @('-OriginHash', 'nothing.md')
  Cmp-Json '잘못된 옵션 값' @('-Restore', '../x')
  Cmp-Json '지우기 미리보기(처음)' @('-Uninstall', '-Plan')
  # 설치 — 두 구현이 같은 내용을 쓰는지
  Run @('-Json') | Out-Null; $psInstall = $script:Out; $psRc = $script:Rc
  Run-Sh @('--json');
  Eq '설치 종료 코드' $psRc $script:ShRc
  Eq '설치 changes · counts 가 같다' (Shape $psInstall) (Shape $script:ShOut)
  $nps = Norm-Json $psInstall; $nsh = Norm-Json $script:ShOut
  IsTrue '설치 JSON 이 같다' ($nps -ceq $nsh) ("`nPS: $nps`nSH: $nsh")
  $snapPs = Get-Snap (Join-Path $b 'psc'); $snapSh = Get-Snap (Join-Path $b 'shc')
  function Norm-Marker($rows) { return @($rows | ForEach-Object { if ($_ -like '*marker:*') { ($_ -replace 'marker:copy:.*?[\\/]repo', 'marker:copy:@repo').Replace('\', '/') } else { $_ } }) }
  $nm1 = Norm-Marker $snapPs; $nm2 = Norm-Marker $snapSh
  IsTrue '설치된 파일이 두 구현에서 똑같다 (이름 · 내용 · 표시 파일의 원본 위치)' (Same-Snap $nm1 $nm2) ((Compare-Object $nm1 $nm2 | ForEach-Object { $_.InputObject }) -join ' / ')
  Cmp-Json '설치 뒤 미리보기' @('-Plan')
  Cmp-Json '설치 뒤 확인' @('-Check')
  Cmp-Json '백업 목록' @('-Backups')
  Cmp-Json '지우기 미리보기' @('-Uninstall', '-Plan')
  # 되돌리기 미리보기 — 백업 번호는 구현마다 다르다
  $psBk = (Get-ChildItem (Join-Path $b 'psh\backups') -Directory)[0].Name; $shBk = (Get-ChildItem (Join-Path $b 'shh\backups') -Directory)[0].Name
  Run @('-Restore', $psBk, '-Plan', '-Json') | Out-Null; $r1 = $script:Out
  Run-Sh @('--restore', $shBk, '--plan', '--json'); $r2 = $script:ShOut
  IsTrue '되돌리기 미리보기 JSON 이 같다' ((Norm-Json $r1) -ceq (Norm-Json $r2)) ("`nPS: $(Norm-Json $r1)`nSH: $(Norm-Json $r2)")
  # sh 로 설치한 것을 ps 로 되돌리고 싶어도 대상이 다르니 거부 — 대신 같은 입력의 되돌리기를 각자 한다
  Run @('-Restore', $psBk, '-Json') | Out-Null; $rps = $script:Out
  Run-Sh @('--restore', $shBk, '--json'); $rsh = $script:ShOut
  IsTrue '되돌리기 JSON 이 같다' ((Norm-Json $rps) -ceq (Norm-Json $rsh)) ("`nPS: $(Norm-Json $rps)`nSH: $(Norm-Json $rsh)")
  IsTrue '되돌린 뒤 두 쪽 다 비었다 (하네스 파일 없음)' ((@(Get-Snap (Join-Path $b 'psc') | Where-Object { $_ -like 'F *' }).Count -eq 0) -and (@(Get-Snap (Join-Path $b 'shc') | Where-Object { $_ -like 'F *' }).Count -eq 0))
  # 원본 해시 값 — 줄바꿈이 달라도 같은 값
  Run @('-OriginHash', 'agents/harness-helper.md') | Out-Null; $o1 = $script:Out.Trim()
  Run-Sh @('--origin-hash', 'agents/harness-helper.md'); Eq '원본 해시 값이 install.sh 와 같다' $o1 $script:ShOut.Trim()
  Remove-Item Env:CLAUDE_HARNESS_NO_SYMLINK
}

# ═══════════════════════════════════════
Write-Host ""
Write-Host "통과 $($script:Pass) · 실패 $($script:Fail)"
try { Remove-Item -LiteralPath $Tmp -Recurse -Force -ErrorAction SilentlyContinue } catch { }
if ($script:Fail -gt 0) { exit 1 } else { exit 0 }
