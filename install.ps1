# claude-harness 설치 (Windows) — install.sh 와 같은 일을 Windows 의 Claude Code 사용자 설정(%USERPROFILE%\.claude)에 한다. 옵션 이름 · JSON 모양도 같다.
#   ~/.claude/harness           → 이 저장소 (내 수정이 없으면 링크. 있으면 원본 + 내 수정을 합친 복사)
#   ~/.claude/skills/<스킬>      → skills/<스킬>
#   ~/.claude/agents/<에이전트>  ← agents/*.md + agents/_common/ (합쳐서 복사)
# 심볼릭 링크를 먼저 시도하고, 권한이 없으면(개발자 모드 꺼짐 · 관리자 아님) 복사한다.
# 복사로 설치했으면 harness\.install-mode 에 "copy" 를 남긴다 — 저장소를 고친 뒤에는 다시 돌려야 한다.
#
#   powershell -ExecutionPolicy Bypass -File \\wsl.localhost\<배포판>\home\<사용자>\project\claude-harness\install.ps1 [옵션]
#   (옵션 없음)          설치 (덮어쓰거나 지우기 전에 백업)
#   -Plan                설치하지 않고 계획만 — 새로 생김 · 바뀜 · 지워짐 · 건너뜀 · 원본 바뀜 (아무것도 쓰지 않는다)
#   -Check               설치하지 않고, 설치된 작업자가 저장소(+ 내 수정)와 같은지만 본다 (다르면 종료 코드 1)
#   -Backups             백업 목록
#   -Restore <번호>      고른 백업으로 되돌린다 (-Plan 과 같이 쓰면 미리보기)
#   -Uninstall           하네스가 만든 것을 지운다 (-Plan 으로 미리보기)
#   -OriginHash <경로>   원본 파일의 해시 (내 수정 "통째 바꾸기" 가 남기는 값)
#   -Json                사람용 출력 대신 JSON 한 개를 내보낸다 (모양: shared/app-contract.md — install.sh --json 과 같다)
#
# 위치는 환경 변수로 바꾼다 (시험용으로도 쓴다): CLAUDE_CONFIG_DIR (%USERPROFILE%\.claude) · CLAUDE_HARNESS_HOME (%USERPROFILE%\.claude-harness)
# 종료 코드: 0 성공 · 1 -Check 에서 다름 · 2 잘못된 사용 · 내 수정 폴더 오류 · 다른 설치 진행 중 · 3 실행 중 실패 (되돌림 시도)
param(
  [switch]$Uninstall, [switch]$Check, [switch]$Plan, [switch]$Backups, [switch]$Json,
  [string]$Restore, [string]$OriginHash
)
$ErrorActionPreference = 'Stop'

$Contract = 1
$Repo = $PSScriptRoot
$Retired = @('harness-builder', 'harness-builder-deep')  # 이름이 바뀌어 저장소에서 빠진 예전 작업자
$Mark = '<!-- harness:common -->'
$StateFile = '.harness-installed'  # 내 수정으로 새로 만든 에이전트 · 스킬 이름 (나중에 지워졌을 때 알아보려고)
$Tab = "`t"
$Utf8 = New-Object System.Text.UTF8Encoding $false
$BackupIdRe = '^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{6}(-[0-9]+)?$'

# ── 옵션 ──
$Cmd = 'install'
$ArgErr = ''
$RestoreId = ''
$HashPath = ''
function Set-Cmd([string]$c) {
  if ($script:Cmd -ne 'install' -and $script:Cmd -ne $c) { $script:ArgErr = "옵션이 겹칩니다: $($script:Cmd) 와 $c" }
  $script:Cmd = $c
}
if ($Check) { Set-Cmd 'check' }
if ($Backups) { Set-Cmd 'backups' }
if ($Uninstall) { Set-Cmd 'uninstall' }
if ($PSBoundParameters.ContainsKey('Restore')) { Set-Cmd 'restore'; $RestoreId = $Restore }
if ($PSBoundParameters.ContainsKey('OriginHash')) { Set-Cmd 'originHash'; $HashPath = $OriginHash }
$Dry = [bool]$Plan
$JsonOut = [bool]$Json

# ── 경로 ──
function ConvertTo-FullPath([string]$p) {
  $f = [IO.Path]::GetFullPath($p)
  if ($f.Length -gt 3) { $f = $f.TrimEnd('\', '/') }
  return $f
}
$ClaudeDir = ConvertTo-FullPath $(if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' })
$HarnessHome = ConvertTo-FullPath $(if ($env:CLAUDE_HARNESS_HOME) { $env:CLAUDE_HARNESS_HOME } else { Join-Path $HOME '.claude-harness' })
$Custom = Join-Path $HarnessHome 'custom'
$Backup = Join-Path $HarnessHome 'backups'
$LockPath = Join-Path $ClaudeDir '.harness-install.lock'
$Work = Join-Path ([IO.Path]::GetTempPath()) ('claude-harness.' + [guid]::NewGuid().ToString('N').Substring(0, 8))
[void][IO.Directory]::CreateDirectory((Join-Path $Work 'files\agents'))

$script:Items = New-Object System.Collections.Generic.List[string]     # 내 수정 — 경로 TAB 종류 TAB 원본 바뀜(true|false|-)
$script:Origins = New-Object System.Collections.Generic.List[string]   # 원본 바뀜 — 경로 TAB 적어 둔 해시 TAB 지금 해시(-)
$script:Problems = New-Object System.Collections.Generic.List[string]  # 막는 문제 — 경로 TAB 코드 TAB 설명
$script:Warnings = New-Object System.Collections.Generic.List[string]  # 알림 — 경로 TAB 코드 TAB 설명
$script:Ops = New-Object System.Collections.Generic.List[string]       # 계획 — 동작 TAB 종류 TAB 경로 TAB 덧붙임 (동작: add · change · remove / 종류: file · link · dir)
$script:Skips = New-Object System.Collections.Generic.List[string]     # 건너뜀 — 종류 TAB 경로 TAB 이유
$script:Same = 0
$script:Mode = ''          # link · copy (이번에 설치할 방식) — 계획을 세우지 않는 명령은 비움
$script:Src = $Repo        # 내 수정을 합친 원본 폴더 (내 수정이 없으면 저장소 그대로)
$script:ConfigSrc = ''
$script:ErrCode = ''
$script:ErrDetail = ''
$script:RolledBack = ''
$script:BkId = ''
$script:BkDir = ''
$script:BkFiles = 0
$script:Manifest = ''
$script:ExitCode = 0
$script:OriginHashValue = ''
$script:Restart = $false
$script:Existing = ''
$script:DevMode = $false
$script:LockStream = $null
$script:AwkErr = ''
$script:BackupRows = New-Object System.Collections.Generic.List[string]
$script:AgentList = New-Object System.Collections.Generic.List[string]
$script:SkillList = New-Object System.Collections.Generic.List[string]
$script:StateDesired = New-Object System.Collections.Generic.List[string]
$script:StatePrev = New-Object System.Collections.Generic.List[string]
$script:Slots = @{}        # 복사 방식 목록 이름 → 줄 목록 (상대 경로 TAB 원본 파일)
$script:Rev = New-Object System.Collections.Generic.List[string]

function Write-Say([string]$s) { if (-not $JsonOut) { Write-Host $s } }
function Add-Problem([string]$p, [string]$code, [string]$detail) { $script:Problems.Add("$p$Tab$code$Tab$detail") }
function Add-Warning([string]$p, [string]$code, [string]$detail) { $script:Warnings.Add("$p$Tab$code$Tab$detail") }
function Add-Op([string]$act, [string]$type, [string]$p, [string]$extra = '') { $script:Ops.Add("$act$Tab$type$Tab$p$Tab$extra") }
function Add-Skip([string]$type, [string]$p, [string]$reason) { $script:Skips.Add("$type$Tab$p$Tab$reason") }

# ── 도구 ──
function Get-Lines([string]$t) {  # 줄 나누기 — 마지막 줄바꿈 뒤의 빈 조각은 줄이 아니다
  if ($t.Length -eq 0) { return , @() }
  $parts = $t.Split("`n")
  if ($t.EndsWith("`n")) { $parts = $parts[0..($parts.Length - 2)] }
  return , $parts
}
function Read-Utf8([string]$p) { return $Utf8.GetString([IO.File]::ReadAllBytes($p)) }
function Write-Utf8([string]$p, [string]$text) { [IO.File]::WriteAllBytes($p, $Utf8.GetBytes($text)) }
function Get-Sha256([byte[]]$bytes) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '') } finally { $sha.Dispose() }
}
function Get-NormBytes([byte[]]$b) {  # 줄 끝 CRLF → LF, 마지막 줄에 줄바꿈을 보장 (바이트 단위)
  $o = New-Object System.Collections.Generic.List[byte] ($b.Length + 1)
  for ($i = 0; $i -lt $b.Length; $i++) {
    if ($b[$i] -eq 13 -and ($i + 1 -eq $b.Length -or $b[$i + 1] -eq 10)) { continue }
    $o.Add($b[$i])
  }
  if ($o.Count -gt 0 -and $o[$o.Count - 1] -ne 10) { $o.Add(10) }
  return , $o.ToArray()
}
function Get-NormText([string]$p) { return $Utf8.GetString((Get-NormBytes ([IO.File]::ReadAllBytes($p)))) }
function Get-FileSha([string]$p) { return Get-Sha256 ([IO.File]::ReadAllBytes($p)) }
function Test-SameFile([string]$a, [string]$b) {
  if ((New-Object IO.FileInfo $a).Length -ne (New-Object IO.FileInfo $b).Length) { return $false }
  return (Get-FileSha $a) -ceq (Get-FileSha $b)
}
function Get-OriginHashOf([string]$rel) {  # .md 는 줄바꿈을 LF 로 맞춘 뒤 해시
  $p = Join-Path $Repo $rel.Replace('/', '\')
  $bytes = [IO.File]::ReadAllBytes($p)
  if ($rel.EndsWith('.md')) { $bytes = Get-NormBytes $bytes }
  return Get-Sha256 $bytes
}
function Sort-Ordinal($list) {
  $arr = [string[]]@($list)
  [Array]::Sort($arr, [StringComparer]::Ordinal)
  return , $arr
}
function Sort-Unique($list) {
  $set = New-Object System.Collections.Generic.HashSet[string]
  foreach ($s in @($list)) { [void]$set.Add($s) }
  return Sort-Ordinal $set
}
function Get-Abs([string]$rel) { return Join-Path $ClaudeDir $rel.Replace('/', '\') }

function Get-Kind([string]$p) {  # 지금 있는 것의 종류 — absent · link · dir · file
  try { $a = [IO.File]::GetAttributes($p) } catch { return 'absent' }
  if ($a -band [IO.FileAttributes]::ReparsePoint) { return 'link' }
  if ($a -band [IO.FileAttributes]::Directory) { return 'dir' }
  return 'file'
}
function Get-LinkTarget([string]$p) {
  $t = (Get-Item -LiteralPath $p -Force).Target
  if ($t -is [array]) { $t = $t[0] }
  if ($null -eq $t) { return '' }
  return [string]$t
}
function Test-SameTarget([string]$a, [string]$b) {
  return ($a.TrimEnd('\', '/').Replace('/', '\')) -ieq ($b.TrimEnd('\', '/').Replace('/', '\'))
}
function Test-ManagedDir([string]$p) { return (Get-Kind $p) -eq 'dir' -and (Test-Path -LiteralPath (Join-Path $p '.install-mode') -PathType Leaf) }  # 하네스가 복사로 만든 폴더 (표시 파일이 있다)
function Get-ExistingSource {  # 지금 ~/.claude/harness 가 가리키는 원본 (없으면 빈 값)
  $h = Join-Path $ClaudeDir 'harness'
  $k = Get-Kind $h
  if ($k -eq 'link') { return Get-LinkTarget $h }
  if ($k -eq 'dir' -and (Test-ManagedDir $h)) {
    $l = Get-Lines (Read-Utf8 (Join-Path $h '.install-mode'))
    if ($l.Count -ge 2) { return ([string]$l[1]).TrimEnd("`r") }
  }
  return ''
}
function Remove-Link([string]$p) {
  $item = Get-Item -LiteralPath $p -Force
  if ($item.PSIsContainer) { $item.Delete() } else { [IO.File]::Delete($p) }
}

$script:CanLinkValue = $null
function Test-CanLink {  # 심볼릭 링크를 만들 수 있는지 (권한) — 임시 폴더에서 해 본다
  if ($env:CLAUDE_HARNESS_NO_SYMLINK -eq '1') { return $false }
  if ($null -ne $script:CanLinkValue) { return $script:CanLinkValue }
  $probe = Join-Path $Work 'probe'
  try {
    [void][IO.Directory]::CreateDirectory((Join-Path $probe 't'))
    New-Item -ItemType SymbolicLink -Path (Join-Path $probe 'l') -Target (Join-Path $probe 't') | Out-Null
    $script:CanLinkValue = $true
  } catch { $script:CanLinkValue = $false }
  return $script:CanLinkValue
}

function Get-TreeWalk([string]$root, [bool]$pruneGit) {  # 폴더 안 — files · links · dirs (상대 경로, / 구분, 정렬). 링크 안으로는 들어가지 않는다
  $files = New-Object System.Collections.Generic.List[string]
  $links = New-Object System.Collections.Generic.List[string]
  $dirs = New-Object System.Collections.Generic.List[string]
  function Step([string]$dir, [string]$prefix, [bool]$isRoot) {
    foreach ($e in (New-Object IO.DirectoryInfo $dir).GetFileSystemInfos()) {
      $rel = if ($prefix) { "$prefix/$($e.Name)" } else { $e.Name }
      if ($e.Attributes -band [IO.FileAttributes]::ReparsePoint) { $links.Add($rel); continue }
      if ($e.Attributes -band [IO.FileAttributes]::Directory) {
        if ($isRoot -and $pruneGit -and $e.Name -eq '.git') { continue }
        $dirs.Add($rel); Step $e.FullName $rel $false
      } else { $files.Add($rel) }
    }
  }
  Step $root '' $true
  return @{ Files = (Sort-Ordinal $files); Links = (Sort-Ordinal $links); Dirs = (Sort-Ordinal $dirs) }
}

# ── JSON ──
function ConvertTo-JStr([string]$s) {
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append('"')
  foreach ($c in $s.ToCharArray()) {
    switch ($c) {
      '\' { [void]$sb.Append('\\') }
      '"' { [void]$sb.Append('\"') }
      "`t" { [void]$sb.Append('\t') }
      "`r" { [void]$sb.Append('\r') }
      "`n" { [void]$sb.Append('\n') }
      default { if ([int]$c -lt 32) { [void]$sb.Append(('\u{0:x4}' -f [int]$c)) } else { [void]$sb.Append($c) } }
    }
  }
  [void]$sb.Append('"')
  return $sb.ToString()
}
function ConvertTo-JStrOrNull([string]$s) { if ($s -and $s -ne '-') { return ConvertTo-JStr $s } else { return 'null' } }
function ConvertTo-JBool($b) { if ($b -eq $true -or $b -eq 'true') { return 'true' } else { return 'false' } }

function Get-ChangeRows {  # 변경 목록 — 경로 TAB 동작 TAB 종류 TAB 이유(-) (경로 순)
  $rows = New-Object System.Collections.Generic.List[string]
  foreach ($o in $script:Ops) {
    $f = $o.Split($Tab)
    if ($f[1] -ne 'dir') { $rows.Add("$($f[2])${Tab}$($f[0])${Tab}$($f[1])${Tab}-") }
  }
  foreach ($s in $script:Skips) {
    $f = $s.Split($Tab)
    $rows.Add("$($f[1])${Tab}skip${Tab}$($f[0])${Tab}$($f[2])")
  }
  return Sort-Ordinal $rows
}

function Get-ResultJson {
  $rows = Get-ChangeRows
  $nAdd = 0; $nChange = 0; $nRemove = 0; $nSkip = 0
  foreach ($r in $rows) {
    switch ($r.Split($Tab)[1]) { 'add' { $nAdd++ } 'change' { $nChange++ } 'remove' { $nRemove++ } 'skip' { $nSkip++ } }
  }
  $same = ($nAdd + $nChange + $nRemove) -eq 0
  $ok = ($script:Problems.Count -eq 0) -and (-not $script:ErrCode)
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append('{"contract":' + $Contract + ',"command":' + (ConvertTo-JStr $Cmd) + ',"ok":' + (ConvertTo-JBool $ok) + ',"exitCode":' + $script:ExitCode + ',"dryRun":' + (ConvertTo-JBool $Dry))
  [void]$sb.Append(',"claudeDir":' + (ConvertTo-JStr $ClaudeDir) + ',"harnessHome":' + (ConvertTo-JStr $HarnessHome) + ',"repo":' + (ConvertTo-JStr $Repo))
  [void]$sb.Append(',"mode":' + (ConvertTo-JStrOrNull $script:Mode) + ',"developerMode":' + (ConvertTo-JBool $script:DevMode) + ',"existingSource":' + (ConvertTo-JStrOrNull $script:Existing) + ',"restartNeeded":' + (ConvertTo-JBool $script:Restart))
  [void]$sb.Append(',"custom":{"dir":' + (ConvertTo-JStr $Custom) + ',"items":[')
  $first = $true
  foreach ($line in (Sort-Ordinal $script:Items)) {
    $f = $line.Split($Tab)
    if (-not $first) { [void]$sb.Append(',') }; $first = $false
    $o = if ($f[2] -eq '-') { 'null' } else { $f[2] }
    [void]$sb.Append('{"path":' + (ConvertTo-JStr $f[0]) + ',"kind":' + (ConvertTo-JStr $f[1]) + ',"originChanged":' + $o + '}')
  }
  [void]$sb.Append(']},"changes":[')
  $first = $true
  foreach ($line in $rows) {
    $f = $line.Split($Tab)
    if (-not $first) { [void]$sb.Append(',') }; $first = $false
    [void]$sb.Append('{"path":' + (ConvertTo-JStr $f[0]) + ',"action":' + (ConvertTo-JStr $f[1]) + ',"type":' + (ConvertTo-JStr $f[2]) + ',"reason":' + (ConvertTo-JStrOrNull $f[3]) + '}')
  }
  [void]$sb.Append('],"counts":{"add":' + $nAdd + ',"change":' + $nChange + ',"remove":' + $nRemove + ',"skip":' + $nSkip + ',"same":' + $script:Same + '},"same":' + (ConvertTo-JBool $same))
  [void]$sb.Append(',"originChanged":[')
  $first = $true
  foreach ($line in (Sort-Ordinal $script:Origins)) {
    $f = $line.Split($Tab)
    if (-not $first) { [void]$sb.Append(',') }; $first = $false
    [void]$sb.Append('{"path":' + (ConvertTo-JStr $f[0]) + ',"recorded":' + (ConvertTo-JStr $f[1]) + ',"current":' + (ConvertTo-JStrOrNull $f[2]) + '}')
  }
  [void]$sb.Append('],"problems":[')
  $first = $true
  foreach ($line in (Sort-Unique $script:Problems)) {
    $f = $line.Split($Tab)
    if (-not $first) { [void]$sb.Append(',') }; $first = $false
    [void]$sb.Append('{"path":' + (ConvertTo-JStr $f[0]) + ',"reason":' + (ConvertTo-JStr $f[1]) + ',"detail":' + (ConvertTo-JStr $f[2]) + '}')
  }
  [void]$sb.Append('],"warnings":[')
  $first = $true
  foreach ($line in (Sort-Unique $script:Warnings)) {
    $f = $line.Split($Tab)
    if (-not $first) { [void]$sb.Append(',') }; $first = $false
    [void]$sb.Append('{"path":' + (ConvertTo-JStr $f[0]) + ',"reason":' + (ConvertTo-JStr $f[1]) + ',"detail":' + (ConvertTo-JStr $f[2]) + '}')
  }
  [void]$sb.Append(']')
  if ($script:BkId) { [void]$sb.Append(',"backup":{"id":' + (ConvertTo-JStr $script:BkId) + ',"dir":' + (ConvertTo-JStr $script:BkDir) + ',"files":' + $script:BkFiles + '}') } else { [void]$sb.Append(',"backup":null') }
  [void]$sb.Append(',"backups":[')
  $first = $true
  foreach ($line in $script:BackupRows) {
    $f = $line.Split($Tab)
    if (-not $first) { [void]$sb.Append(',') }; $first = $false
    [void]$sb.Append('{"id":' + (ConvertTo-JStr $f[0]) + ',"createdAt":' + (ConvertTo-JStrOrNull $f[1]) + ',"command":' + (ConvertTo-JStrOrNull $f[2]) + ',"added":' + $f[3] + ',"changed":' + $f[4] + ',"removed":' + $f[5] + ',"files":' + $f[6] + ',"bytes":' + $f[7] + ',"readable":' + $f[8] + '}')
  }
  [void]$sb.Append(']')
  if ($script:OriginHashValue) { [void]$sb.Append(',"originHash":{"path":' + (ConvertTo-JStr $HashPath) + ',"sha256":' + (ConvertTo-JStr $script:OriginHashValue) + '}') } else { [void]$sb.Append(',"originHash":null') }
  if ($script:RolledBack) { [void]$sb.Append(',"rolledBack":' + $script:RolledBack) } else { [void]$sb.Append(',"rolledBack":null') }
  if ($script:ErrCode) { [void]$sb.Append(',"error":{"code":' + (ConvertTo-JStr $script:ErrCode) + ',"detail":' + (ConvertTo-JStr $script:ErrDetail) + '}') } else { [void]$sb.Append(',"error":null') }
  [void]$sb.Append('}')
  return $sb.ToString()
}

function Close-Lock {
  if ($null -ne $script:LockStream) { $script:LockStream.Dispose(); $script:LockStream = $null }
}
function Remove-Work {
  try { if (Test-Path -LiteralPath $Work) { Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue } } catch { }
}

function Finish([int]$code) {  # 결과를 내고 끝낸다
  $script:ExitCode = $code
  Close-Lock
  if ($JsonOut) {
    [Console]::OutputEncoding = $Utf8
    [Console]::Out.Write((Get-ResultJson) + "`n")
    [Console]::Out.Flush()
  } else {
    foreach ($line in (Sort-Unique $script:Problems)) {
      $f = $line.Split($Tab)
      [Console]::Error.WriteLine("  오류: $($f[0]) — $($f[2])")
    }
    if ($script:ErrCode) { [Console]::Error.WriteLine("오류: $($script:ErrDetail)") }
  }
  Remove-Work
  exit $code
}
function Fail([int]$code, [string]$errCode, [string]$detail) {
  $script:ErrCode = $errCode; $script:ErrDetail = $detail
  Finish $code
}

# ── 잘못된 사용 ──
if ($ArgErr) { Fail 2 'badArgs' $ArgErr }
if ($ClaudeDir.TrimEnd('\', '/').Length -le 2) { Fail 2 'badArgs' 'CLAUDE_CONFIG_DIR 가 최상위 폴더입니다' }
if ($HarnessHome.TrimEnd('\', '/').Length -le 2) { Fail 2 'badArgs' 'CLAUDE_HARNESS_HOME 가 최상위 폴더입니다' }
$script:DevMode = -not ((Test-Path -LiteralPath (Join-Path $HarnessHome 'repo')) -and ((Convert-Path -LiteralPath (Join-Path $HarnessHome 'repo')) -ieq (Convert-Path -LiteralPath $Repo)))
$script:Existing = Get-ExistingSource

# ── 원본 해시 ──
if ($Cmd -eq 'originHash') {
  if (-not $HashPath -or $HashPath.StartsWith('/') -or $HashPath.StartsWith('\') -or $HashPath -match '(^|[\\/])\.\.($|[\\/])' -or $HashPath.Contains($Tab) -or $HashPath -match '^[A-Za-z]:') {
    Fail 2 'badArgs' "저장소 안의 상대 경로여야 합니다: $HashPath"
  }
  $hp = Join-Path $Repo $HashPath.Replace('/', '\')
  if ((Get-Kind $hp) -ne 'file') { Fail 2 'notFound' "저장소에 그런 파일이 없습니다: $HashPath" }
  $script:OriginHashValue = Get-OriginHashOf $HashPath.Replace('\', '/')
  if ($JsonOut) { Finish 0 } else { Write-Host $script:OriginHashValue; Remove-Work; exit 0 }
}

# ── 백업 목록 ──
function Get-HeaderValue([string[]]$lines, [string]$key) {
  foreach ($l in $lines) { if ($l.StartsWith("# ${key}: ")) { return $l.Substring($key.Length + 4) } }
  return ''
}
function Get-BackupList {
  $script:BackupRows.Clear()
  $rows = New-Object System.Collections.Generic.List[string]
  if (Test-Path -LiteralPath $Backup) {
    foreach ($d in (New-Object IO.DirectoryInfo $Backup).GetDirectories()) {
      $id = $d.Name
      if ($id -notmatch $BackupIdRe) { continue }
      $mf = Join-Path $d.FullName 'manifest.txt'
      $added = 0; $changed = 0; $removed = 0; $created = '-'; $command = '-'; $readable = 'false'
      if (Test-Path -LiteralPath $mf -PathType Leaf) {
        $lines = Get-Lines (Read-Utf8 $mf)
        $c = Get-HeaderValue $lines 'createdAt'; if ($c) { $created = $c }
        $c = Get-HeaderValue $lines 'command'; if ($c) { $command = $c }
        foreach ($l in $lines) {
          if ($l.StartsWith('#') -or -not $l) { continue }
          $f = $l.Split($Tab)
          if ($f.Count -ge 2 -and $f[1] -ne 'dir') { switch ($f[0]) { 'add' { $added++ } 'change' { $changed++ } 'remove' { $removed++ } } }
        }
        $readable = 'true'
      }
      $files = 0; $bytes = [long]0
      $fd = Join-Path $d.FullName 'files'
      if (Test-Path -LiteralPath $fd) {
        $w = Get-TreeWalk $fd $false
        $files = @($w.Files).Count
        foreach ($rel in $w.Files) { $bytes += (New-Object IO.FileInfo (Join-Path $fd $rel.Replace('/', '\'))).Length }
      }
      $rows.Add(($id, $created, $command, $added, $changed, $removed, $files, $bytes, $readable) -join $Tab)
    }
  }
  $sorted = Sort-Ordinal $rows
  [Array]::Reverse($sorted)
  foreach ($r in $sorted) { $script:BackupRows.Add($r) }
}

if ($Cmd -eq 'backups') {
  Get-BackupList
  if (-not $JsonOut) {
    if ($script:BackupRows.Count -eq 0) { Write-Host "백업이 없습니다 ($Backup)" }
    else {
      Write-Host "백업 ($Backup)"
      foreach ($r in $script:BackupRows) {
        $f = $r.Split($Tab)
        if ($f[8] -eq 'true') { Write-Host "  $($f[0])  $($f[2]) — 새로 $($f[3]) · 바뀜 $($f[4]) · 지움 $($f[5]) (백업한 파일 $($f[6])개)" }
        else { Write-Host "  $($f[0])  (목록 파일을 읽을 수 없음)" }
      }
    }
  }
  Finish 0
}

# ── 잠금 (설치 · 되돌리기 · 지우기를 동시에 못 돌게) ──
function Enter-Lock {
  try { [void][IO.Directory]::CreateDirectory($ClaudeDir) } catch { Fail 3 'writeFailed' "$ClaudeDir 를 만들 수 없습니다" }
  $tries = 0
  while ($true) {
    try {
      # 열려 있는 동안만 잠금 — 프로세스가 죽으면 파일이 저절로 지워진다
      $script:LockStream = New-Object IO.FileStream $LockPath, ([IO.FileMode]::CreateNew), ([IO.FileAccess]::ReadWrite), ([IO.FileShare]::None), 1, ([IO.FileOptions]::DeleteOnClose)
      return
    } catch {
      $tries++
      if ($tries -ge 3) { Fail 2 'busy' "다른 설치가 진행 중입니다 ($LockPath)" }
      Start-Sleep -Seconds 1
    }
  }
}

# ── 쓰기 도구 ──
function Remove-FileSafe([string]$p) {
  try { [IO.File]::SetAttributes($p, [IO.FileAttributes]::Normal) } catch { }
  [IO.File]::Delete($p)
}
function Copy-FileAtomic([string]$src, [string]$dst) {  # 임시 파일에 쓴 뒤 바꿔서 반쯤 쓴 파일이 남지 않게
  $tmp = "$dst.harness-tmp.$PID"
  try {
    [IO.File]::Copy($src, $tmp, $true)
    if (Test-Path -LiteralPath $dst -PathType Leaf) { [IO.File]::Delete($dst) }
    [IO.File]::Move($tmp, $dst)
  } catch {
    try { if (Test-Path -LiteralPath $tmp) { [IO.File]::Delete($tmp) } } catch { }
    throw
  }
}
function New-Link([string]$p, [string]$target) {
  New-Item -ItemType SymbolicLink -Path $p -Target $target | Out-Null
}
function New-ParentDirs([string]$rel) {  # 위쪽 폴더를 만든다 (새로 만든 폴더는 되돌릴 수 있게 목록에 남긴다)
  $idx = $rel.LastIndexOf('/')
  if ($idx -lt 0) { return }
  $acc = ''
  foreach ($part in $rel.Substring(0, $idx).Split('/')) {
    $acc = if ($acc) { "$acc/$part" } else { $part }
    $p = Get-Abs $acc
    if ((Get-Kind $p) -eq 'absent') {
      [void][IO.Directory]::CreateDirectory($p)
      [IO.File]::AppendAllText($script:Manifest, "add${Tab}dir${Tab}${acc}${Tab}`n", $Utf8)
    }
  }
}

# ── 되돌리기 ──
function Test-SafeRel([string]$p, [string]$type) {  # 백업 목록의 경로가 하네스가 다루는 자리 안인지 본다 (agents · skills 폴더 자체는 새로 만들었던 폴더로만)
  if (-not $p -or $p.StartsWith('/') -or $p.Contains($Tab) -or $p -match '(^|/)\.\.($|/)') { return $false }
  if (($p -ceq 'agents' -or $p -ceq 'skills') -and $type -eq 'dir') { return $true }
  return ($p -ceq 'harness' -or $p.StartsWith('harness/') -or $p.StartsWith('skills/') -or $p.StartsWith('agents/') -or $p -ceq $StateFile)
}
function Test-UnderLink([string]$rel) {  # 복사본(harness · skills/<이름>) 안의 경로인데 그 안쪽 위 폴더가 링크면 $true. 링크를 따라가 저장소 같은 바깥을 건드리지 않으려고
  $slot = ''
  if ($rel.StartsWith('harness/')) { $slot = 'harness' }
  elseif ($rel -match '^skills/([^/]+)/') { $slot = "skills/$($Matches[1])" }
  else { return $false }
  $acc = ''
  foreach ($part in $rel.Substring(0, $rel.LastIndexOf('/')).Split('/')) {
    $acc = if ($acc) { "$acc/$part" } else { $part }
    if (($acc -ceq $slot -or $acc.StartsWith("$slot/")) -and (Get-Kind (Get-Abs $acc)) -eq 'link') { return $true }
  }
  return $false
}
function Test-RestoreNeed([string]$act, [string]$type, [string]$p, [string]$extra) {
  if (Test-UnderLink $p) { return ($act -eq 'remove' -or $act -eq 'change') }  # 링크 아래에는 아무것도 없는 셈 — 돌려놓을 것만 남는다
  $cur = Get-Abs $p
  $k = Get-Kind $cur
  switch ("${act}:${type}") {
    'add:file' { return ($k -eq 'file' -or $k -eq 'link') }
    'add:link' { return ($k -eq 'link') }
    { $_ -eq 'remove:file' -or $_ -eq 'change:file' } {
      $b = Join-Path $script:BkDir ('files\' + $p.Replace('/', '\'))
      if ((Get-Kind $b) -ne 'file') { return $true }
      if ($k -ne 'file') { return $true }
      return -not (Test-SameFile $b $cur)
    }
    { $_ -eq 'remove:link' -or $_ -eq 'change:link' } { return ($k -ne 'link') -or -not (Test-SameTarget (Get-LinkTarget $cur) $extra) }
  }
  return $false
}
function Get-ReversedManifest {
  $lines = New-Object System.Collections.Generic.List[string]
  foreach ($l in (Get-Lines (Read-Utf8 $script:Manifest))) { if (-not $l.StartsWith('#') -and $l.Length -gt 0) { $lines.Add($l) } }
  $lines.Reverse()
  $script:Rev = $lines
}

function Invoke-RestorePrepare([string]$id) {  # 목록을 검사하고 되돌릴 계획(Ops)을 세운다
  if ($id -notmatch $BackupIdRe) { Fail 2 'badArgs' "백업 번호 모양이 틀립니다: $id" }
  $script:BkDir = Join-Path $Backup $id; $script:Manifest = Join-Path $script:BkDir 'manifest.txt'
  if ((Get-Kind $script:Manifest) -ne 'file') { Fail 2 'noBackup' "그런 백업이 없습니다: $id (-Backups 로 본다)" }
  $want = Get-HeaderValue (Get-Lines (Read-Utf8 $script:Manifest)) 'claudeDir'
  if ($want -cne $ClaudeDir) { Fail 2 'wrongTarget' "이 백업은 다른 곳($want)의 것입니다 — 지금 대상은 $ClaudeDir" }
  Get-ReversedManifest
  foreach ($l in $script:Rev) {
    $f = $l.Split($Tab)
    $act = $f[0]; $type = if ($f.Count -ge 2) { $f[1] } else { '' }; $p = if ($f.Count -ge 3) { $f[2] } else { '' }
    if ($act -notin 'add', 'change', 'remove') { Fail 2 'badBackup' "백업 목록이 깨졌습니다 (동작: $act)" }
    if ($type -notin 'file', 'link', 'dir') { Fail 2 'badBackup' "백업 목록이 깨졌습니다 (종류: $type)" }
    if (-not (Test-SafeRel $p $type)) { Fail 2 'badBackup' "백업 목록에 하네스가 다루지 않는 경로가 있습니다: $p" }
  }
  $script:BkId = $id
  $fd = Join-Path $script:BkDir 'files'
  $script:BkFiles = if (Test-Path -LiteralPath $fd) { @((Get-TreeWalk $fd $false).Files).Count } else { 0 }
  $script:Ops.Clear(); $script:Same = 0
  foreach ($l in $script:Rev) {
    $f = $l.Split($Tab)
    $act = $f[0]; $type = $f[1]; $p = $f[2]; $extra = if ($f.Count -ge 4) { $f[3] } else { '' }
    if ($type -eq 'dir') { continue }
    if (Test-RestoreNeed $act $type $p $extra) {
      switch ($act) { 'add' { Add-Op 'remove' $type $p } 'remove' { Add-Op 'add' $type $p $extra } 'change' { Add-Op 'change' $type $p $extra } }
    } else { $script:Same++ }
  }
}

function Invoke-RestoreExec {  # 1) 설치가 새로 만든 파일 · 링크 지우기  2) 새로 만든 빈 폴더 지우기  3) 덮어쓴 것 · 지운 것 돌려놓기. 하나라도 못 하면 $false
  $failed = $false
  foreach ($l in $script:Rev) {
    $f = $l.Split($Tab)
    if ($f[0] -ne 'add') { continue }
    if (Test-UnderLink $f[2]) { continue }
    $p = Get-Abs $f[2]
    try {
      if ($f[1] -eq 'file') { $k = Get-Kind $p; if ($k -eq 'file') { Remove-FileSafe $p } elseif ($k -eq 'link') { Remove-Link $p } }
      elseif ($f[1] -eq 'link') { if ((Get-Kind $p) -eq 'link') { Remove-Link $p } }
    } catch { $failed = $true }
  }
  foreach ($l in $script:Rev) {
    $f = $l.Split($Tab)
    if ($f[0] -eq 'add' -and $f[1] -eq 'dir' -and -not (Test-UnderLink $f[2])) { try { [IO.Directory]::Delete((Get-Abs $f[2])) } catch { } }
  }
  foreach ($l in $script:Rev) {
    $f = $l.Split($Tab)
    if ($f[0] -eq 'add') { continue }
    $type = $f[1]; $rel = $f[2]; $extra = if ($f.Count -ge 4) { $f[3] } else { '' }
    if (Test-UnderLink $rel) { $failed = $true; continue }
    if ($type -ne 'dir' -and -not (Test-RestoreNeed $f[0] $type $rel $extra)) { continue }  # 이미 같다
    $p = Get-Abs $rel
    try {
      switch ($type) {
        'dir' { [void][IO.Directory]::CreateDirectory($p) }
        'file' {
          $b = Join-Path $script:BkDir ('files\' + $rel.Replace('/', '\'))
          if ((Get-Kind $b) -ne 'file') { $failed = $true; continue }
          [void][IO.Directory]::CreateDirectory((Split-Path -Parent $p))
          Copy-FileAtomic $b $p
        }
        'link' {
          [void][IO.Directory]::CreateDirectory((Split-Path -Parent $p))
          if ((Get-Kind $p) -eq 'link') { Remove-Link $p }
          New-Link $p $extra
        }
      }
    } catch { $failed = $true }
  }
  return -not $failed
}

function Get-RestoreLabel([string]$act) { switch ($act) { 'add' { '다시 만듦' } 'remove' { '지움' } default { '돌려놓음' } } }

function Invoke-CmdRestore {
  if ($Dry) {
    Invoke-RestorePrepare $RestoreId
    if (-not $JsonOut) {
      Write-Host "백업 $RestoreId 로 되돌리면 (미리보기 — 아무것도 쓰지 않았습니다)"
      foreach ($o in $script:Ops) { $f = $o.Split($Tab); Write-Host ("  " + (Get-RestoreLabel $f[0]) + ': ' + $f[2]) }
      if ($script:Ops.Count -eq 0) { Write-Host '  (바뀌는 것 없음)' }
    }
    Finish 0
  }
  Enter-Lock
  Invoke-RestorePrepare $RestoreId
  if (Invoke-RestoreExec) {
    Write-Say "백업 $RestoreId 로 되돌렸습니다 ($($script:BkDir))"
    foreach ($o in $script:Ops) { $f = $o.Split($Tab); Write-Say ("  " + (Get-RestoreLabel $f[0]) + ': ' + $f[2]) }
    Finish 0
  }
  Fail 3 'restoreFailed' "일부를 되돌리지 못했습니다 — 백업 목록: $($script:Manifest)"
}

# ── 내 수정 읽기 (custom\) ──
function Get-ValueRows([string]$file) {  # "키 TAB 값" 줄 목록. 모양이 틀리면 $null 과 설명($script:AwkErr)
  $script:AwkErr = ''
  $rows = New-Object System.Collections.Generic.List[string]
  $seen = New-Object System.Collections.Generic.HashSet[string]
  $n = 0
  foreach ($raw in (Get-Lines (Read-Utf8 $file))) {
    $n++
    $line = $raw -replace "\r$", ''
    if ($line -match '^[ \t]*$') { continue }
    if ($line -match '^[ \t]*#') { continue }
    $i = $line.IndexOf(':')
    if ($i -lt 1) { $script:AwkErr = "${n}번째 줄이 `"키: 값`" 모양이 아니다"; return $null }
    $k = $line.Substring(0, $i)
    $v = $line.Substring($i + 1).Trim(' ', "`t")
    if ($k -cnotmatch '^[A-Za-z][A-Za-z0-9_-]*$') { $script:AwkErr = "${n}번째 줄의 키가 올바르지 않다: $k"; return $null }
    if ($k -ceq 'name' -or $k -ceq 'hooks') { $script:AwkErr = "${n}번째 줄: $k 는 바꿀 수 없다"; return $null }
    if ($v -eq '') { $script:AwkErr = "${n}번째 줄: $k 의 값이 비었다"; return $null }
    if ($v.Contains($Tab)) { $script:AwkErr = "${n}번째 줄: $k 의 값에 탭이 있다"; return $null }
    if (-not $seen.Add($k)) { $script:AwkErr = "${n}번째 줄: $k 가 두 번 나온다"; return $null }
    $rows.Add("$k$Tab$v")
  }
  return , $rows
}

function Set-FrontValues([string]$target, [string]$valuesFile) {  # 앞머리(---)에 값을 넣는다. 안 되면 $false 와 설명($script:AwkErr)
  $rows = Get-ValueRows $valuesFile
  if ($null -eq $rows) { return $false }
  $keys = @(); $vals = @()
  foreach ($r in $rows) { $i = $r.IndexOf($Tab); $keys += $r.Substring(0, $i); $vals += $r.Substring($i + 1) }
  $out = New-Object System.Collections.Generic.List[string]
  $used = @{}
  $fm = $false; $closed = $false; $prev = -1; $nr = 0
  foreach ($l in (Get-Lines (Read-Utf8 $target))) {
    $nr++
    if ($nr -eq 1) {
      if ($l -cne '---') { $script:AwkErr = '앞머리(---)가 없다'; return $false }
      $fm = $true; $out.Add($l); continue
    }
    if ($fm -and $l -ceq '---') {
      for ($j = 0; $j -lt $keys.Count; $j++) { if (-not $used.ContainsKey($j)) { $out.Add($keys[$j] + ': ' + $vals[$j]) } }
      $fm = $false; $closed = $true; $out.Add($l); continue
    }
    if ($fm) {
      if ($prev -ge 0 -and ($l -match '^[ \t]' -or $l.StartsWith('- ', [StringComparison]::Ordinal))) {
        $script:AwkErr = $keys[$prev] + ' 의 값이 여러 줄이라 값 바꾸기로 바꿀 수 없다'; return $false
      }
      $prev = -1
      $hit = $false
      for ($j = 0; $j -lt $keys.Count; $j++) {
        if ($l.StartsWith($keys[$j] + ':', [StringComparison]::Ordinal)) {
          $out.Add($keys[$j] + ': ' + $vals[$j]); $used[$j] = $true; $prev = $j; $hit = $true; break
        }
      }
      if (-not $hit) { $out.Add($l) }
      continue
    }
    $out.Add($l)
  }
  if (-not $closed) { $script:AwkErr = '앞머리(---)가 닫히지 않았다'; return $false }
  Write-Utf8 $target ((($out.ToArray()) -join "`n") + "`n")
  return $true
}

function Add-Appended([string]$target, [string]$appendFile) {  # 원본 끝에 빈 줄 하나를 두고 덧붙인다
  $base = Get-NormText $target
  Write-Utf8 $target ($base + "`n" + (Get-NormText $appendFile))
}

function Test-HasContent([string]$p) { return (Read-Utf8 $p) -match '[^\s]' }

function Add-CustomFile([string]$rel) {  # 내 수정 폴더 안 파일 하나를 읽어 종류를 가른다
  if ($rel.Contains($Tab) -or $rel.Contains("`r")) { Add-Problem $rel 'badPath' '경로에 탭 · 줄바꿈 글자를 쓸 수 없다'; return }
  $abs = Join-Path $Custom $rel.Replace('/', '\')
  if ((Get-Kind $abs) -eq 'link') { Add-Problem $rel 'symlinkInCustom' '내 수정 폴더 안에는 링크를 둘 수 없다'; return }
  if ((Get-Kind $abs) -ne 'file') { Add-Problem $rel 'badPath' '경로를 읽을 수 없다'; return }
  $slash = $rel.IndexOf('/')
  if ($slash -lt 0) { Add-Problem $rel 'unsupported' "$rel 는 파일이 아니라 폴더여야 한다"; return }
  $top = $rel.Substring(0, $slash); $rest = $rel.Substring($slash + 1)
  if ($rel.StartsWith('agents/_common/')) { Add-Problem $rel 'unsupported' '공통 규칙 · 가드 hook(agents/_common)은 내 수정으로 바꿀 수 없다'; return }
  if ($top -eq 'agents' -and $rest.Contains('/')) { Add-Problem $rel 'unsupported' 'agents 안에는 하위 폴더를 둘 수 없다'; return }
  if ($top -eq 'skills' -and -not $rest.Contains('/')) { Add-Problem $rel 'unsupported' 'skills 안에는 폴더만 둔다 (skills/<이름>/SKILL.md)'; return }
  $kind = ''; $target = $rel
  if ($rel.EndsWith('.origin')) { $script:Sidecars.Add($rel.Substring(0, $rel.Length - 7)); return }
  elseif ($rel.EndsWith('.values.yml')) { $kind = 'values'; $target = $rel.Substring(0, $rel.Length - 11) + '.md' }
  elseif ($rel.EndsWith('.append.md')) { $kind = 'append'; $target = $rel.Substring(0, $rel.Length - 10) + '.md' }
  if ($kind) {
    if ((Get-Kind (Join-Path $Repo $target.Replace('/', '\'))) -ne 'file') { Add-Problem $rel 'targetMissing' "고칠 원본 파일($target)이 저장소에 없다"; return }
    if ($kind -eq 'values') {
      if ($null -eq (Get-ValueRows $abs)) { Add-Problem $rel 'badValues' $script:AwkErr; return }
    } elseif (-not (Test-HasContent $abs)) {
      Add-Warning $rel 'emptyAppend' '덧붙일 내용이 비어 있어 건너뛴다'; return
    }
    $script:Items.Add("$target$Tab$kind${Tab}-")
    return
  }
  $sidecar = "$abs.origin"
  $rec = ''
  if ((Get-Kind $sidecar) -eq 'file') {
    $rec = ((Read-Utf8 $sidecar) -replace "[ \t\r\n]", '')
    $rec = [regex]::Replace($rec, '[A-F]', { param($m) $m.Value.ToLowerInvariant() })
    if ($rec -cnotmatch '^[0-9a-f]{64}$') { Add-Problem "$rel.origin" 'badOrigin' '원본 해시는 sha256 16진수 64글자여야 한다'; return }
  }
  if ((Get-Kind (Join-Path $Repo $rel.Replace('/', '\'))) -eq 'file') {
    $kind = 'replace'
    $cur = Get-OriginHashOf $rel
    if ($rec) {
      if ($rec -ceq $cur) { $origin = 'false' } else { $origin = 'true'; $script:Origins.Add("$rel$Tab$rec$Tab$cur") }
    } else {
      $origin = '-'
      Add-Warning $rel 'noOriginHash' '만들 때의 원본 해시가 없어 원본이 바뀌었는지 알 수 없다'
    }
  } elseif ($rec) {  # 원본에서 사라진 파일을 통째로 바꿔 둔 경우
    $kind = 'replace'; $origin = 'true'
    $script:Origins.Add("$rel$Tab$rec${Tab}-")
    Add-Warning $rel 'originGone' '통째로 바꾼 파일의 원본이 저장소에서 사라졌다'
  } else { $kind = 'new'; $origin = '-' }
  $script:Items.Add("$rel$Tab$kind$Tab$origin")
}

$script:Sidecars = New-Object System.Collections.Generic.List[string]

function Read-Custom {
  $script:Sidecars.Clear()
  if ((Get-Kind $Custom) -ne 'dir') { return }
  foreach ($e in (New-Object IO.DirectoryInfo $Custom).GetFileSystemInfos()) {
    $name = $e.Name
    $isLink = [bool]($e.Attributes -band [IO.FileAttributes]::ReparsePoint)
    $isDir = [bool]($e.Attributes -band [IO.FileAttributes]::Directory)
    switch -CaseSensitive ($name) {
      'config.local.json' {
        if ($isLink) { Add-Problem $name 'symlinkInCustom' '내 수정 폴더 안에는 링크를 둘 수 없다' }
        elseif (-not $isDir) { $script:Items.Add("$name${Tab}config${Tab}-") }
        else { Add-Problem $name 'unsupported' 'config.local.json 이 파일이 아니다' }
      }
      { $_ -in 'agent-cats.json', '.git', '.gitignore' } { }  # 앱 · git 이 쓰는 것 — 설치는 읽지 않는다
      { $_ -in 'agents', 'skills', 'shared' } {
        if ($isLink) { Add-Problem $name 'symlinkInCustom' '내 수정 폴더 안에는 링크를 둘 수 없다' }
        elseif ($isDir) {
          $w = Get-TreeWalk $e.FullName $false
          $all = New-Object System.Collections.Generic.List[string]
          foreach ($f in $w.Files) { $all.Add("$name/$f") }
          foreach ($f in $w.Links) { $all.Add("$name/$f") }
          foreach ($rel in (Sort-Ordinal $all)) { Add-CustomFile $rel }
        } else { Add-CustomFile $name }
      }
      default { Add-Warning $name 'ignored' '내 수정 폴더에서 설치가 읽지 않는 항목' }
    }
  }
  $replaced = New-Object System.Collections.Generic.HashSet[string]
  foreach ($i in $script:Items) { $f = $i.Split($Tab); if ($f[1] -eq 'replace') { [void]$replaced.Add($f[0]) } }
  foreach ($s in $script:Sidecars) { if (-not $replaced.Contains($s)) { Add-Warning "$s.origin" 'orphanOrigin' '짝이 되는 통째로 바꾼 파일이 없다' } }
}

# ── 합치기 (원본 + 내 수정) ──
function Copy-Custom([string]$from, [string]$to) {  # .md 는 줄바꿈을 LF 로 맞춘다
  if ($from.EndsWith('.md')) { Write-Utf8 $to (Get-NormText $from) } else { [IO.File]::Copy($from, $to, $true) }
}
function New-ParentOf([string]$p) { [void][IO.Directory]::CreateDirectory((Split-Path -Parent $p)) }

function Initialize-Source {
  $hasOverlay = $false
  foreach ($i in $script:Items) { if ($i.Split($Tab)[1] -ne 'config') { $hasOverlay = $true } }
  if (-not $hasOverlay) { $script:Src = $Repo; return }
  $script:Src = Join-Path $Work 'src'
  [void][IO.Directory]::CreateDirectory($script:Src)
  foreach ($rel in (Get-TreeWalk $Repo $true).Files) {
    $to = Join-Path $script:Src $rel.Replace('/', '\')
    New-ParentOf $to
    [IO.File]::Copy((Join-Path $Repo $rel.Replace('/', '\')), $to, $true)
  }
  foreach ($i in $script:Items) {
    $f = $i.Split($Tab)
    if ($f[1] -eq 'replace' -or $f[1] -eq 'new') {
      $to = Join-Path $script:Src $f[0].Replace('/', '\')
      New-ParentOf $to
      Copy-Custom (Join-Path $Custom $f[0].Replace('/', '\')) $to
    }
  }
  foreach ($i in $script:Items) {
    $f = $i.Split($Tab)
    if ($f[1] -eq 'values') {
      $stem = $f[0].Substring(0, $f[0].Length - 3)
      if (-not (Set-FrontValues (Join-Path $script:Src $f[0].Replace('/', '\')) (Join-Path $Custom ($stem + '.values.yml').Replace('/', '\')))) { Add-Problem $f[0] 'badValues' $script:AwkErr }
    }
  }
  foreach ($i in $script:Items) {
    $f = $i.Split($Tab)
    if ($f[1] -eq 'append') {
      $stem = $f[0].Substring(0, $f[0].Length - 3)
      Add-Appended (Join-Path $script:Src $f[0].Replace('/', '\')) (Join-Path $Custom ($stem + '.append.md').Replace('/', '\'))
    }
  }
}

function Test-AgentSource([string]$file, [string]$name) {  # 틀이 맞는지 본다. 틀리면 설명, 맞으면 $null
  $lines = Get-Lines (Read-Utf8 $file)
  $base = [IO.Path]::GetFileNameWithoutExtension($name)
  if ($lines.Count -lt 2 -or $lines[1] -cne "name: $base") { return "두 번째 줄이 'name: $base' 이어야 한다" }
  for ($i = 1; $i -lt $lines.Count -and $lines[$i] -cne '---'; $i++) {
    if ($lines[$i].StartsWith('hooks:', [StringComparison]::Ordinal)) { return 'hooks 는 쓰지 않는다 (설치할 때 agents/_common/hooks.yml 이 붙는다)' }
  }
  return $null
}

function Build-AgentText([string]$file) {  # 앞머리 끝에 hooks.yml, 표시 줄 자리(없으면 끝)에 rules.md 를 넣은 내용
  $common = Join-Path $script:Src 'agents\_common'
  $hooks = Get-Lines (Read-Utf8 (Join-Path $common 'hooks.yml'))
  $rules = Get-Lines (Read-Utf8 (Join-Path $common 'rules.md'))
  $out = New-Object System.Collections.Generic.List[string]
  $fm = $false; $done = $false; $n = 0
  foreach ($l in (Get-Lines (Read-Utf8 $file))) {
    $n++
    if ($n -eq 1 -and $l -ceq '---') { $fm = $true; $out.Add($l); continue }
    if ($fm -and $l -ceq '---') { $out.AddRange([string[]]$hooks); $out.Add($l); $fm = $false; continue }
    if ($l -ceq $Mark) { $out.AddRange([string[]]$rules); $done = $true; continue }
    $out.Add($l)
  }
  if (-not $done) { $out.Add(''); $out.AddRange([string[]]$rules) }
  return (($out.ToArray()) -join "`n") + "`n"
}

function Initialize-Agents {
  $script:AgentList.Clear()
  $dir = Join-Path $script:Src 'agents'
  if (-not (Test-Path -LiteralPath $dir)) { return }
  $names = New-Object System.Collections.Generic.List[string]
  foreach ($fi in (New-Object IO.DirectoryInfo $dir).GetFiles('*.md')) { if (-not ($fi.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $names.Add($fi.Name) } }
  foreach ($name in (Sort-Ordinal $names)) {
    $f = Join-Path $dir $name
    $err = Test-AgentSource $f $name
    if ($err) { Add-Problem "agents/$name" 'invalidAgent' $err; continue }
    Write-Utf8 (Join-Path $Work "files\agents\$name") (Build-AgentText $f)
    $script:AgentList.Add($name)
  }
}

function Select-Mode {
  $script:Mode = 'link'
  if ($script:Items.Count -gt 0 -or -not (Test-CanLink)) { $script:Mode = 'copy' }
}

function Initialize-SlotList([string]$id, [string]$dir, [string]$markSrc, [bool]$withConfig) {  # 복사 방식 목록 — 상대 경로 TAB 원본 파일
  Write-Utf8 (Join-Path $Work "files\marker.$id") "copy`n$markSrc`n"
  $rows = New-Object System.Collections.Generic.List[string]
  foreach ($rel in (Get-TreeWalk $dir $true).Files) {
    if ($withConfig -and $rel -ceq 'config.local.json') { continue }
    $rows.Add("$rel$Tab" + (Join-Path $dir $rel.Replace('/', '\')))
  }
  if ($withConfig -and $script:ConfigSrc) { $rows.Add("config.local.json$Tab$($script:ConfigSrc)") }
  $rows.Add(".install-mode$Tab" + (Join-Path $Work "files\marker.$id"))
  $script:Slots[$id] = Sort-Ordinal $rows
}

function Select-Config {  # 복사 방식일 때 ~/.claude/harness/config.local.json 으로 들어갈 설정 — 내 수정 > 저장소 > 지금 설치에 있는 것
  $script:ConfigSrc = ''
  if ($script:Mode -ne 'copy') { return }
  $hasConfig = $false
  foreach ($i in $script:Items) { if ($i.Split($Tab)[1] -eq 'config') { $hasConfig = $true } }
  $installed = Join-Path $ClaudeDir 'harness\config.local.json'
  if ($hasConfig) { $script:ConfigSrc = Join-Path $Custom 'config.local.json' }
  elseif ((Get-Kind (Join-Path $Repo 'config.local.json')) -eq 'file') { $script:ConfigSrc = Join-Path $Repo 'config.local.json' }
  elseif ((Test-ManagedDir (Join-Path $ClaudeDir 'harness')) -and (Get-Kind $installed) -eq 'file') {
    $script:ConfigSrc = $installed
    Add-Warning 'config.local.json' 'configOnlyInInstall' '설정이 내 수정 폴더(custom/)가 아니라 설치본에만 있다 — 다음 설치까지는 그대로 둔다'
  }
  elseif ($script:Items.Count -eq 0 -and $script:DevMode -and (Get-Kind (Join-Path $Repo 'config.example.json')) -eq 'file') {
    $script:ConfigSrc = Join-Path $Repo 'config.example.json'  # 예전처럼 저장소에 설정 파일을 만들어 주는 사람 — 복사본에도 같은 내용
  }
}

function Initialize-Slots {
  Select-Config
  if ($script:Mode -eq 'copy') { Initialize-SlotList 'harness' $script:Src $Repo $true }
  $script:SkillList.Clear()
  $sd = Join-Path $script:Src 'skills'
  if (Test-Path -LiteralPath $sd) {
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($d in (New-Object IO.DirectoryInfo $sd).GetDirectories()) {
      if ($d.Name.StartsWith('.')) { continue }  # sh 의 */ 처럼 점으로 시작하는 폴더는 스킬이 아니다
      if ($d.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
      $names.Add($d.Name)
    }
    foreach ($n in (Sort-Ordinal $names)) {
      $script:SkillList.Add($n)
      if (-not (Test-CanLink)) { Initialize-SlotList "skill.$n" (Join-Path $sd $n) (Join-Path $Repo "skills\$n") $false }
    }
  }
  $state = New-Object System.Collections.Generic.List[string]
  foreach ($n in $script:AgentList) { if (-not (Test-Path -LiteralPath (Join-Path $Repo "agents\$n"))) { $state.Add("agent $n") } }
  foreach ($n in $script:SkillList) { if (-not (Test-Path -LiteralPath (Join-Path $Repo "skills\$n"))) { $state.Add("skill $n") } }
  $script:StateDesired.Clear()
  foreach ($s in (Sort-Ordinal $state)) { $script:StateDesired.Add($s) }
  if ($script:StateDesired.Count -gt 0) { Write-Utf8 (Join-Path $Work 'files\state') ((($script:StateDesired.ToArray()) -join "`n") + "`n") }
}

function Read-State {  # 지난번 설치가 남긴, 내 수정으로 새로 만든 에이전트 · 스킬 이름
  $script:StatePrev.Clear()
  $p = Join-Path $ClaudeDir $StateFile
  if ((Get-Kind $p) -eq 'file') {
    $set = New-Object System.Collections.Generic.List[string]
    foreach ($l in (Get-Lines (Read-Utf8 $p))) { if ($l -cmatch '^(agent [A-Za-z0-9][A-Za-z0-9._-]*\.md|skill [A-Za-z0-9][A-Za-z0-9._-]*)$') { $set.Add($l) } }
    foreach ($s in (Sort-Unique $set)) { $script:StatePrev.Add($s) }
  }
}

# ── 계획 (지금 ~/.claude 와 비교) ──
function Compare-One([string]$rel, [string]$src) {
  $cur = Get-Abs $rel
  switch (Get-Kind $cur) {
    'absent' { Add-Op 'add' 'file' $rel $src }
    'file' { if (Test-SameFile $src $cur) { $script:Same++ } else { Add-Op 'change' 'file' $rel $src } }
    default { Add-Skip 'file' $rel 'notOurs' }
  }
}
function Add-RemoveTree([string]$rel) {  # 복사로 만든 폴더 전체를 지운다 (파일 · 링크 → 폴더 깊은 것부터)
  $cur = Get-Abs $rel
  $w = Get-TreeWalk $cur $false
  $entries = New-Object System.Collections.Generic.List[string]
  foreach ($f in $w.Files) { $entries.Add("0$Tab$f") }
  foreach ($l in $w.Links) { $entries.Add("1$Tab$l") }
  # find 는 파일과 링크를 이름 순으로 섞어 내므로, 같은 순서로 맞춘다
  $mixed = New-Object System.Collections.Generic.List[string]
  foreach ($e in $entries) { $mixed.Add($e.Substring(2)) }
  foreach ($name in (Sort-Ordinal $mixed)) {
    if ($w.Links -contains $name) { Add-Op 'remove' 'link' "$rel/$name" (Get-LinkTarget (Join-Path $cur $name.Replace('/', '\'))) }
    else { Add-Op 'remove' 'file' "$rel/$name" }
  }
  $dirs = New-Object System.Collections.Generic.List[string]
  $dirs.Add('.')
  foreach ($d in $w.Dirs) { $dirs.Add("./$d") }
  $sorted = Sort-Ordinal $dirs
  [Array]::Reverse($sorted)
  foreach ($d in $sorted) { if ($d -eq '.') { Add-Op 'remove' 'dir' $rel } else { Add-Op 'remove' 'dir' "$rel/$($d.Substring(2))" } }
}
function Add-LinkSlot([string]$rel, [string]$target) {  # 링크로 둔다
  $cur = Get-Abs $rel
  switch (Get-Kind $cur) {
    'absent' { Add-Op 'add' 'link' $rel $target }
    'link' { if (Test-SameTarget (Get-LinkTarget $cur) $target) { $script:Same++ } else { Add-Op 'change' 'link' $rel $target } }
    'dir' { if (Test-ManagedDir $cur) { Add-RemoveTree $rel; Add-Op 'add' 'link' $rel $target } else { Add-Skip 'link' $rel 'notOurs' } }
    default { Add-Skip 'link' $rel 'notOurs' }
  }
}
function Add-CopySlot([string]$id, [string]$rel) {  # 복사로 둔다
  $cur = Get-Abs $rel
  $fresh = $false
  switch (Get-Kind $cur) {
    'absent' { $fresh = $true }
    'link' { Add-Op 'remove' 'link' $rel (Get-LinkTarget $cur); $fresh = $true }
    'dir' {
      if (Test-ManagedDir $cur) {
        $want = New-Object System.Collections.Generic.HashSet[string]
        foreach ($row in $script:Slots[$id]) { [void]$want.Add($row.Split($Tab)[0]) }
        $w = Get-TreeWalk $cur $false
        $mixed = New-Object System.Collections.Generic.List[string]
        foreach ($f in $w.Files) { $mixed.Add($f) }
        foreach ($l in $w.Links) { $mixed.Add($l) }
        foreach ($name in (Sort-Ordinal $mixed)) {
          if ($want.Contains($name)) { continue }
          if ($w.Links -contains $name) { Add-Op 'remove' 'link' "$rel/$name" (Get-LinkTarget (Join-Path $cur $name.Replace('/', '\'))) }
          else { Add-Op 'remove' 'file' "$rel/$name" }
        }
      } else {
        Add-Skip 'dir' $rel 'notOurs'
        if ($rel -eq 'harness') { Add-Problem 'harness' 'harnessNotOurs' "$ClaudeDir/harness 에 하네스가 만들지 않은 폴더가 있다 — 직접 확인해야 한다" }
        return
      }
    }
    default {
      Add-Skip 'dir' $rel 'notOurs'
      if ($rel -eq 'harness') { Add-Problem 'harness' 'harnessNotOurs' "$ClaudeDir/harness 에 하네스가 만들지 않은 파일이 있다 — 직접 확인해야 한다" }
      return
    }
  }
  foreach ($row in $script:Slots[$id]) {
    $f = $row.Split($Tab)
    if ($fresh) { Add-Op 'add' 'file' "$rel/$($f[0])" $f[1] } else { Compare-One "$rel/$($f[0])" $f[1] }
  }
}

function Build-Plan {
  $script:Ops.Clear(); $script:Skips.Clear(); $script:Same = 0
  Read-State
  $prev = New-Object System.Collections.Generic.HashSet[string]
  foreach ($s in $script:StatePrev) { [void]$prev.Add($s) }
  if ($script:Mode -eq 'link') { Add-LinkSlot 'harness' $Repo } else { Add-CopySlot 'harness' 'harness' }
  foreach ($n in $script:SkillList) {
    $cur = Get-Abs "skills/$n"
    if (-not (Test-Path -LiteralPath (Join-Path $Repo "skills\$n")) -and -not $prev.Contains("skill $n") -and ((Get-Kind $cur) -ne 'absent')) { Add-Skip 'link' "skills/$n" 'notOurs'; continue }
    if (-not (Test-CanLink)) { Add-CopySlot "skill.$n" "skills/$n" }
    else {
      $target = if ($script:Mode -eq 'copy') { Join-Path $ClaudeDir "harness\skills\$n" } else { Join-Path $Repo "skills\$n" }
      Add-LinkSlot "skills/$n" $target
    }
  }
  foreach ($r in $Retired) {
    $cur = Get-Abs "agents/$r.md"
    $k = Get-Kind $cur
    if ($k -eq 'link') { Add-Op 'remove' 'link' "agents/$r.md" (Get-LinkTarget $cur) }
    elseif ($k -eq 'file') { Add-Op 'remove' 'file' "agents/$r.md" }
  }
  foreach ($f in $script:AgentList) {
    $cur = Get-Abs "agents/$f"
    if (-not (Test-Path -LiteralPath (Join-Path $Repo "agents\$f")) -and -not $prev.Contains("agent $f") -and ((Get-Kind $cur) -ne 'absent')) { Add-Skip 'file' "agents/$f" 'notOurs'; continue }
    Compare-One "agents/$f" (Join-Path $Work "files\agents\$f")
  }
  if ($script:StateDesired.Count -gt 0) { Compare-One $StateFile (Join-Path $Work 'files\state') }
  elseif ((Get-Kind (Get-Abs $StateFile)) -eq 'file') { Add-Op 'remove' 'file' $StateFile }
  foreach ($s in $script:StatePrev) {
    $kind = $s.Substring(0, $s.IndexOf(' ')); $n = $s.Substring($s.IndexOf(' ') + 1)
    if ($kind -eq 'agent') {
      if ($script:AgentList.Contains($n)) { continue }
      $cur = Get-Abs "agents/$n"
      $k = Get-Kind $cur
      if ($k -eq 'link') { Add-Op 'remove' 'link' "agents/$n" (Get-LinkTarget $cur) } elseif ($k -eq 'file') { Add-Op 'remove' 'file' "agents/$n" }
    } else {
      if ($script:SkillList.Contains($n)) { continue }
      $cur = Get-Abs "skills/$n"
      switch (Get-Kind $cur) {
        'link' { Add-Op 'remove' 'link' "skills/$n" (Get-LinkTarget $cur) }
        'dir' { if (Test-ManagedDir $cur) { Add-RemoveTree "skills/$n" } else { Add-Skip 'link' "skills/$n" 'notOurs' } }
      }
    }
  }
}

function Test-HasChanges { foreach ($o in $script:Ops) { if ($o.Split($Tab)[1] -ne 'dir') { return $true } }; return $false }

# ── 쓰기 (백업 → 실행 → 확인) ──
function Invoke-Apply {
  if (-not (Test-HasChanges)) { return }
  $ordered = New-Object System.Collections.Generic.List[string]
  foreach ($act in 'remove', 'change', 'add') { foreach ($o in $script:Ops) { if ($o.Split($Tab)[0] -eq $act) { $ordered.Add($o) } } }
  try { [void][IO.Directory]::CreateDirectory($Backup) } catch { Fail 3 'backupFailed' "백업 폴더를 만들 수 없습니다: $Backup" }
  $base = (Get-Date).ToString('yyyy-MM-dd_HHmmss', [Globalization.CultureInfo]::InvariantCulture)
  $script:BkId = $base; $n = 1
  while ($true) {
    $dir = Join-Path $Backup $script:BkId
    if (-not (Test-Path -LiteralPath $dir)) {
      try { [void][IO.Directory]::CreateDirectory($dir); break } catch { }
    }
    $n++; $script:BkId = "$base-$n"
    if ($n -ge 100) { $script:BkId = ''; Fail 3 'backupFailed' "백업 폴더를 만들 수 없습니다: $Backup" }
  }
  $script:BkDir = Join-Path $Backup $script:BkId; $script:Manifest = Join-Path $script:BkDir 'manifest.txt'; $script:BkFiles = 0
  try { [void][IO.Directory]::CreateDirectory((Join-Path $script:BkDir 'files')) } catch { $script:BkId = ''; Fail 3 'backupFailed' "백업 폴더를 만들 수 없습니다: $($script:BkDir)" }
  $d = Get-Date
  $stamp = $d.ToString('yyyy-MM-ddTHH:mm:ss', [Globalization.CultureInfo]::InvariantCulture) + $d.ToString('zzz', [Globalization.CultureInfo]::InvariantCulture).Replace(':', '')
  $head = "# claude-harness backup v1`n# id: $($script:BkId)`n# createdAt: $stamp`n# command: $Cmd`n# claudeDir: $ClaudeDir`n# repo: $Repo`n"
  try { [IO.File]::WriteAllText($script:Manifest, $head, $Utf8) } catch { $script:BkId = ''; Fail 3 'backupFailed' '백업 목록을 쓸 수 없습니다' }
  # 1) 덮어쓰거나 지울 것을 백업하고 목록에 적는다 (아직 아무것도 바꾸지 않았다)
  $sb = New-Object System.Text.StringBuilder
  foreach ($o in $ordered) {
    $f = $o.Split($Tab)
    $act = $f[0]; $type = $f[1]; $p = $f[2]; $extra = if ($f.Count -ge 4) { $f[3] } else { '' }
    switch ($type) {
      'file' {
        if ($act -ne 'add') {
          try {
            $to = Join-Path $script:BkDir ('files\' + $p.Replace('/', '\'))
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $to))
            [IO.File]::Copy((Get-Abs $p), $to, $true)
          } catch {
            Remove-Item -LiteralPath $script:BkDir -Recurse -Force -ErrorAction SilentlyContinue
            $script:BkId = ''; Fail 3 'backupFailed' "백업하지 못했습니다: $p — 아무것도 바꾸지 않았습니다"
          }
          $script:BkFiles++
        }
        [void]$sb.Append("$act${Tab}file$Tab$p${Tab}`n")
      }
      'link' {
        if ($act -eq 'add') { [void]$sb.Append("add${Tab}link$Tab$p$Tab$extra`n") }
        else { [void]$sb.Append("$act${Tab}link$Tab$p$Tab" + (Get-LinkTarget (Get-Abs $p)) + "`n") }
      }
      'dir' { [void]$sb.Append("$act${Tab}dir$Tab$p${Tab}`n") }
    }
  }
  [IO.File]::AppendAllText($script:Manifest, $sb.ToString(), $Utf8)
  # 2) 실행
  $err = ''
  foreach ($o in $ordered) {
    $f = $o.Split($Tab)
    $act = $f[0]; $type = $f[1]; $p = $f[2]; $extra = if ($f.Count -ge 4) { $f[3] } else { '' }
    $abs = Get-Abs $p
    if (Test-UnderLink $p) { $err = "$act $type $p (링크 아래)"; break }
    try {
      switch ("${act}:${type}") {
        'remove:file' { Remove-FileSafe $abs }
        'remove:link' { Remove-Link $abs }
        'remove:dir' { [IO.Directory]::Delete($abs) }
        { $_ -eq 'change:file' -or $_ -eq 'add:file' } { New-ParentDirs $p; Copy-FileAtomic $extra $abs }
        'change:link' { Remove-Link $abs; New-Link $abs $extra }
        'add:link' { New-ParentDirs $p; New-Link $abs $extra }
      }
    } catch { $err = "$act $type $p"; break }
  }
  # 3) 확인 — 다시 계획을 세워 바뀔 것이 남아 있으면 실패
  if (-not $err) {
    $appliedOps = @($script:Ops); $appliedSkips = @($script:Skips); $appliedSame = $script:Same
    Build-Plan
    if (Test-HasChanges) { $err = '확인 실패 — 설치 뒤에도 달라지는 것이 있다' }
    $script:Ops.Clear(); foreach ($x in $appliedOps) { $script:Ops.Add($x) }
    $script:Skips.Clear(); foreach ($x in $appliedSkips) { $script:Skips.Add($x) }
    $script:Same = $appliedSame
  }
  if ($err) {
    Get-ReversedManifest
    if (Invoke-RestoreExec) { $script:RolledBack = 'true' } else { $script:RolledBack = 'false' }
    Fail 3 'applyFailed' "쓰는 중 실패했습니다 ($err) — 이미 쓴 것을 되돌렸는지: $($script:RolledBack). 백업: $($script:BkDir)"
  }
}

# ── 사람용 출력 ──
function Write-PlanText {  # 미리보기
  Write-Say "claude-harness 설치 미리보기 ($Repo) — 아무것도 쓰지 않았습니다"
  $how = if ($script:Mode -eq 'link') { '링크' } else { '복사 (원본 + 내 수정)' }
  if ($script:DevMode) { $how += " · 개발자 모드 (원본: $Repo)" }
  Write-Say "  방식: $how"
  foreach ($row in (Get-ChangeRows)) {
    $f = $row.Split($Tab)
    switch ($f[1]) {
      'add' { Write-Say "  새로 생김: $($f[0])" }
      'change' { Write-Say "  바뀜: $($f[0])" }
      'remove' { Write-Say "  지워짐: $($f[0])" }
      'skip' { Write-Say "  건너뜀: $($f[0]) — 하네스가 만들지 않은 것이 있음 (직접 확인하세요)" }
    }
  }
  foreach ($line in (Sort-Ordinal $script:Origins)) { Write-Say "  원본 바뀜: $($line.Split($Tab)[0]) — 통째로 바꾼 파일의 원본이 달라졌습니다 (내 것을 그대로 쓰는 중)" }
  if (-not (Test-HasChanges)) { Write-Say '  (바뀌는 것 없음)' }
}
function Test-Skipped([string]$type, [string]$rel) {
  foreach ($s in $script:Skips) { $f = $s.Split($Tab); if ($f[1] -ceq $rel -and ($type -eq '*' -or $f[0] -eq $type)) { return $true } }
  return $false
}
function Test-Removed([string]$rel) {
  foreach ($o in $script:Ops) { $f = $o.Split($Tab); if ($f[0] -eq 'remove' -and $f[2] -ceq $rel) { return $true } }
  return $false
}
function Write-InstallReport {
  Write-Say "claude-harness 설치 ($Repo)"
  if ($script:DevMode) { Write-Say "  개발자 모드 — 원본: $Repo (~/.claude-harness/repo 가 아님)" }
  if ($script:Mode -eq 'copy') { Write-Say "  내 수정 $($script:Items.Count)개를 합쳐서 복사합니다" }
  if (Test-Skipped '*' 'harness') { Write-Say "  건너뜀: $(Join-Path $ClaudeDir 'harness') — 링크가 아닌 파일이 이미 있음 (직접 확인하세요)" }
  elseif ($script:Mode -eq 'link') { Write-Say "  연결: $(Join-Path $ClaudeDir 'harness') → $Repo" }
  else { Write-Say "  복사: $(Join-Path $ClaudeDir 'harness') ← $Repo (파일 $(@($script:Slots['harness']).Count)개)" }
  foreach ($n in $script:SkillList) {
    $t = Join-Path $ClaudeDir "skills\$n"
    if (Test-Skipped '*' "skills/$n") { Write-Say "  건너뜀: $t — 링크가 아닌 파일이 이미 있음 (직접 확인하세요)" }
    elseif (-not (Test-CanLink)) { Write-Say "  복사: $t ← $(Join-Path $Repo "skills\$n") (링크 권한 없음)" }
    elseif ($script:Mode -eq 'copy') { Write-Say "  연결: $t → $(Join-Path $ClaudeDir "harness\skills\$n")" }
    else { Write-Say "  연결: $t → $(Join-Path $Repo "skills\$n")" }
  }
  foreach ($r in $Retired) { if (Test-Removed "agents/$r.md") { Write-Say "  지움 (예전 작업자): $(Join-Path $ClaudeDir "agents\$r.md")" } }
  foreach ($f in $script:AgentList) {
    if (Test-Skipped 'file' "agents/$f") { Write-Say "  건너뜀: $(Join-Path $ClaudeDir "agents\$f") — 하네스가 만들지 않은 파일이 이미 있음 (직접 확인하세요)" }
    else { Write-Say "  설치: $(Join-Path $ClaudeDir "agents\$f") (+ 공통 규칙 · 가드 hook)" }
  }
  foreach ($o in $script:Ops) {
    $f = $o.Split($Tab)
    if ($f[0] -ne 'remove' -or $f[1] -eq 'dir') { continue }
    $p = $f[2]
    if ($p -eq 'agents/harness-builder.md' -or $p -eq 'agents/harness-builder-deep.md') { continue }
    if ($p.StartsWith('agents/') -or $p -match '^skills/[^/]+$' -or $p -ceq $StateFile) { Write-Say "  지움 (내 수정에서 빠진 것): $(Join-Path $ClaudeDir $p.Replace('/', '\'))" }
  }
  foreach ($line in (Sort-Ordinal $script:Origins)) { Write-Say "  원본 바뀜: $($line.Split($Tab)[0]) — 통째로 바꾼 파일의 원본이 달라졌습니다. 내 것을 그대로 쓰고 있습니다 (앱이나 /harness-setup 에서 고르세요)" }
  if ($script:BkId -and $script:BkFiles -gt 0) { Write-Say "  백업: $($script:BkDir) (덮어쓰거나 지운 파일 $($script:BkFiles)개 — 되돌리기: install.ps1 -Restore $($script:BkId))" }
}

# ── 명령 ──
function Initialize-Install {  # 내 수정 읽기 → 합치기. 문제가 있으면 여기서 끝낸다
  Read-Custom
  if ($script:Problems.Count -gt 0) { Finish 2 }
  Select-Mode
  Initialize-Source
  if ($script:Problems.Count -gt 0) { Finish 2 }
  Initialize-Agents
  if ($script:Problems.Count -gt 0) { Finish 2 }
  Initialize-Slots
}

function Invoke-CmdInstall {
  Initialize-Install
  $script:Restart = (Get-Kind (Join-Path $ClaudeDir 'agents')) -eq 'absent'
  Build-Plan
  if ($script:Problems.Count -gt 0) { Finish 2 }
  if ($Dry) { Write-PlanText; Finish 0 }
  Enter-Lock
  $script:Restart = (Get-Kind (Join-Path $ClaudeDir 'agents')) -eq 'absent'
  Build-Plan  # 잠근 뒤 다시 — 그사이 바뀌었을 수 있다
  if ($script:Problems.Count -gt 0) { Finish 2 }
  Invoke-Apply
  Write-InstallReport
  $cfg = Join-Path $Repo 'config.local.json'
  if ($script:Items.Count -eq 0 -and $script:DevMode -and (Get-Kind $cfg) -eq 'absent') {
    try {
      [IO.File]::Copy((Join-Path $Repo 'config.example.json'), $cfg, $false)
      Write-Say "  설정 파일을 만들었습니다: $cfg — /harness-setup 으로 채우세요"
    } catch { }
  }
  Write-Say '완료. 스킬: /web-full · /web-lite · /desktop-app · /harness-resume · /harness-setup'
  if ($script:Mode -eq 'copy' -and -not (Test-CanLink) -and $script:Items.Count -eq 0) { Write-Say '※ 복사로 설치했습니다. 저장소를 고친 뒤에는 이 스크립트를 다시 돌리세요. (개발자 모드를 켜면 링크로 설치됩니다)' }
  if ($script:Restart) { Write-Say '※ 에이전트 폴더를 새로 만들었습니다. 열려 있는 Claude Code 를 다시 시작해야 작업자 에이전트가 보입니다.' }
  Write-Say '※ 작업자 가드 hook 은 bash 로 돕니다 — Windows 에서는 Git Bash 가 있어야 합니다.'
  Finish 0
}

function Invoke-CmdCheck {  # 설치된 작업자가 저장소(+ 내 수정)와 같은지만 본다
  Initialize-Install
  $diff = $false
  $script:Ops.Clear(); $script:Same = 0
  foreach ($f in $script:AgentList) {
    $t = Get-Abs "agents/$f"
    $staged = Join-Path $Work "files\agents\$f"
    if ((Get-Kind $t) -ne 'file') { Write-Say "빠짐: $f"; Add-Op 'add' 'file' "agents/$f"; $diff = $true }
    elseif (-not (Test-SameFile $staged $t)) { Write-Say "다름: $f"; Add-Op 'change' 'file' "agents/$f"; $diff = $true }
    else { $script:Same++ }
  }
  foreach ($r in $Retired) {
    if ((Get-Kind (Get-Abs "agents/$r.md")) -eq 'file') { Write-Say "남음 (예전 작업자): $r.md"; Add-Op 'remove' 'file' "agents/$r.md"; $diff = $true }
  }
  if (-not $diff) { Write-Say '작업자: 저장소와 같음' }
  Finish $(if ($diff) { 1 } else { 0 })
}

function Build-UninstallPlan {
  $script:Ops.Clear(); $script:Skips.Clear(); $script:Same = 0
  Read-State
  $h = Get-Abs 'harness'
  switch (Get-Kind $h) {
    'link' { Add-Op 'remove' 'link' 'harness' (Get-LinkTarget $h) }
    'dir' { if (Test-ManagedDir $h) { Add-RemoveTree 'harness' } else { Add-Skip 'dir' 'harness' 'notOurs' } }
    'absent' { }
    default { Add-Skip 'file' 'harness' 'notOurs' }
  }
  # 스킬 (저장소의 것 + 내 수정으로 만든 것)
  $skills = New-Object System.Collections.Generic.List[string]
  $sd = Join-Path $Repo 'skills'
  if (Test-Path -LiteralPath $sd) { foreach ($d in (New-Object IO.DirectoryInfo $sd).GetDirectories()) { if (-not $d.Name.StartsWith('.')) { $skills.Add($d.Name) } } }
  foreach ($s in $script:StatePrev) { if ($s.StartsWith('skill ')) { $skills.Add($s.Substring(6)) } }
  foreach ($n in (Sort-Unique $skills)) {
    $cur = Get-Abs "skills/$n"
    switch (Get-Kind $cur) {
      'link' { Add-Op 'remove' 'link' "skills/$n" (Get-LinkTarget $cur) }
      'dir' { if (Test-ManagedDir $cur) { Add-RemoveTree "skills/$n" } else { Add-Skip 'link' "skills/$n" 'notOurs' } }
    }
  }
  # 에이전트
  $agents = New-Object System.Collections.Generic.List[string]
  $ad = Join-Path $Repo 'agents'
  if (Test-Path -LiteralPath $ad) { foreach ($fi in (New-Object IO.DirectoryInfo $ad).GetFiles('*.md')) { $agents.Add($fi.Name) } }
  foreach ($s in $script:StatePrev) { if ($s.StartsWith('agent ')) { $agents.Add($s.Substring(6)) } }
  foreach ($r in $Retired) { $agents.Add("$r.md") }
  foreach ($n in (Sort-Unique $agents)) {
    $cur = Get-Abs "agents/$n"
    switch (Get-Kind $cur) {
      'link' { Add-Op 'remove' 'link' "agents/$n" (Get-LinkTarget $cur) }
      'file' { Add-Op 'remove' 'file' "agents/$n" }
      'absent' { }
      default { Add-Skip 'file' "agents/$n" 'notOurs' }
    }
  }
  if ((Get-Kind (Get-Abs $StateFile)) -eq 'file') { Add-Op 'remove' 'file' $StateFile }
}
function Write-UninstallReport {
  foreach ($row in (Get-ChangeRows)) {
    $f = $row.Split($Tab)
    $p = $f[0]
    if ($p -match '^(harness|skills/[^/]+)/.') { continue }
    switch ($f[1]) {
      'remove' { Write-Say "  지움: $(Join-Path $ClaudeDir $p.Replace('/', '\'))" }
      'skip' { Write-Say "  건너뜀: $(Join-Path $ClaudeDir $p.Replace('/', '\')) — 하네스가 만들지 않은 것이 있음 (직접 확인하세요)" }
    }
  }
}
function Invoke-CmdUninstall {
  if ($Dry) {
    Build-UninstallPlan
    if (-not $JsonOut) {
      Write-Host 'claude-harness 지우기 미리보기 — 아무것도 쓰지 않았습니다'
      Write-UninstallReport
      if (-not (Test-HasChanges)) { Write-Host '  (지울 것 없음)' }
    }
    Finish 0
  }
  Enter-Lock
  Build-UninstallPlan
  Invoke-Apply
  Write-UninstallReport
  if ($script:BkId -and $script:BkFiles -gt 0) { Write-Say "  백업: $($script:BkDir) (되돌리기: install.ps1 -Restore $($script:BkId))" }
  Write-Say '완료.'
  Finish 0
}

try {
  switch ($Cmd) {
    'restore' { Invoke-CmdRestore }
    'uninstall' { Invoke-CmdUninstall }
    'check' { Invoke-CmdCheck }
    default { Invoke-CmdInstall }
  }
} catch {
  $script:ErrCode = 'unexpected'; $script:ErrDetail = $_.Exception.Message
  Finish 3
} finally {
  Close-Lock
}
