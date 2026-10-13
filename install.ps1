# claude-harness 설치 (Windows) — install.sh 와 같은 일을 Windows 의 Claude Code 사용자 설정(%USERPROFILE%\.claude)에 한다.
#   ~/.claude/harness           → 이 저장소
#   ~/.claude/skills/<스킬>      → skills/<스킬>
#   ~/.claude/agents/<에이전트>  ← agents/*.md + agents/_common/ (합쳐서 복사)
# 심볼릭 링크를 먼저 시도하고, 권한이 없으면(개발자 모드 꺼짐 · 관리자 아님) 복사한다.
# 복사로 설치했으면 harness\.install-mode 에 "copy" 를 남긴다 — 저장소를 고친 뒤에는 다시 돌려야 한다.
#
#   powershell -ExecutionPolicy Bypass -File \\wsl.localhost\<배포판>\home\<사용자>\project\claude-harness\install.ps1
#   지우기: 같은 명령 끝에 -Uninstall
#   비교만: 같은 명령 끝에 -Check (설치된 작업자가 저장소와 같은지, 다르면 종료 코드 1)
param([switch]$Uninstall, [switch]$Check)
$ErrorActionPreference = 'Stop'

$Repo = $PSScriptRoot
$ClaudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
$Marker = '.install-mode'
$Skills = Get-ChildItem -Directory (Join-Path $Repo 'skills')
$Agents = Get-ChildItem -File (Join-Path $Repo 'agents') -Filter '*.md'
$Retired = @('harness-builder', 'harness-builder-deep')  # 이름이 바뀌어 저장소에서 빠진 예전 작업자

function Remove-Retired {
  foreach ($r in $Retired) {
    $t = Join-Path $ClaudeDir "agents\$r.md"
    if (Test-Path -LiteralPath $t) { Remove-Item -LiteralPath $t -Force; Write-Host "  지움 (예전 작업자): $t" }
  }
}

$Common = Join-Path $Repo 'agents\_common'
$Mark = '<!-- harness:common -->'

function Test-AgentFile($f) {  # 틀이 맞는지 본다
  $lines = @(Get-Content -LiteralPath $f.FullName -Encoding UTF8)
  $base = [IO.Path]::GetFileNameWithoutExtension($f.Name)
  if ($lines.Count -lt 2 -or $lines[1] -ne "name: $base") { throw "$($f.FullName) — 두 번째 줄이 'name: $base' 이어야 한다" }
  for ($i = 1; $i -lt $lines.Count -and $lines[$i] -ne '---'; $i++) {
    if ($lines[$i] -like 'hooks:*') { throw "$($f.FullName) — hooks 는 쓰지 않는다 (설치할 때 agents/_common/hooks.yml 이 붙는다)" }
  }
}

function Build-Agent($f) {  # 앞머리 끝에 hooks.yml, 표시 줄 자리(없으면 끝)에 rules.md 를 넣은 내용을 돌려준다
  $hooks = @(Get-Content -LiteralPath (Join-Path $Common 'hooks.yml') -Encoding UTF8)
  $rules = @(Get-Content -LiteralPath (Join-Path $Common 'rules.md') -Encoding UTF8)
  $out = New-Object System.Collections.Generic.List[string]
  $fm = $false; $done = $false; $n = 0
  foreach ($l in @(Get-Content -LiteralPath $f.FullName -Encoding UTF8)) {
    $n++
    if ($n -eq 1 -and $l -eq '---') { $fm = $true; $out.Add($l); continue }
    if ($fm -and $l -eq '---') { $out.AddRange([string[]]$hooks); $out.Add($l); $fm = $false; continue }
    if ($l -eq $Mark) { $out.AddRange([string[]]$rules); $done = $true; continue }
    $out.Add($l)
  }
  if (-not $done) { $out.Add(''); $out.AddRange([string[]]$rules) }
  ($out -join "`n") + "`n"
}

function Write-Agent($f) {
  $t = Join-Path $ClaudeDir "agents\$($f.Name)"
  [IO.File]::WriteAllText($t, (Build-Agent $f), (New-Object Text.UTF8Encoding $false))
  Write-Host "  설치: $t (+ 공통 규칙 · 가드 hook)"
}

function Test-Link($p) { (Test-Path -LiteralPath $p) -and ((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) }
function Test-OurCopy($p) { Test-Path -LiteralPath (Join-Path $p $Marker) }

function Remove-Ours($p) {  # 우리가 만든 링크 · 복사본만 지운다
  if (Test-Link $p) { (Get-Item -LiteralPath $p -Force).Delete(); Write-Host "  지움: $p"; return $true }
  if (Test-OurCopy $p) { Remove-Item -LiteralPath $p -Recurse -Force; Write-Host "  지움: $p"; return $true }
  return -not (Test-Path -LiteralPath $p)
}

function Install-Dir($src, $dst, [string[]]$exclude = @()) {
  if (-not (Remove-Ours $dst)) { Write-Host "  건너뜀: $dst — 하네스가 만들지 않은 폴더가 이미 있음 (직접 확인하세요)"; return }
  try {
    New-Item -ItemType SymbolicLink -Path $dst -Target $src | Out-Null
    Write-Host "  연결: $dst → $src"; return 'link'
  } catch {
    New-Item -ItemType Directory -Path $dst | Out-Null
    Get-ChildItem -LiteralPath $src -Force | Where-Object { $exclude -notcontains $_.Name } |
      Copy-Item -Destination $dst -Recurse -Force
    Set-Content -LiteralPath (Join-Path $dst $Marker) -Value "copy`n$src" -Encoding UTF8
    Write-Host "  복사: $dst ← $src (링크 권한 없음)"; return 'copy'
  }
}

if ($Check) {
  $diff = $false
  foreach ($a in $Agents) {
    $t = Join-Path $ClaudeDir "agents\$($a.Name)"
    if (-not (Test-Path -LiteralPath $t)) { Write-Host "빠짐: $($a.Name)"; $diff = $true }
    elseif ([IO.File]::ReadAllText($t) -cne (Build-Agent $a)) { Write-Host "다름: $($a.Name)"; $diff = $true }
  }
  foreach ($r in $Retired) {
    if (Test-Path -LiteralPath (Join-Path $ClaudeDir "agents\$r.md")) { Write-Host "남음 (예전 작업자): $r.md"; $diff = $true }
  }
  if (-not $diff) { Write-Host '작업자: 저장소와 같음' }
  if ($diff) { exit 1 } else { exit 0 }
}

if ($Uninstall) {
  foreach ($s in $Skills) { [void](Remove-Ours (Join-Path $ClaudeDir "skills\$($s.Name)")) }
  foreach ($a in $Agents) {
    $t = Join-Path $ClaudeDir "agents\$($a.Name)"
    if (Test-Path -LiteralPath $t) { Remove-Item -LiteralPath $t -Force; Write-Host "  지움: $t" }
  }
  Remove-Retired
  [void](Remove-Ours (Join-Path $ClaudeDir 'harness'))
  Write-Host '완료.'; return
}

foreach ($a in $Agents) { Test-AgentFile $a }
Write-Host "claude-harness 설치 ($Repo)"
$newAgentsDir = -not (Test-Path (Join-Path $ClaudeDir 'agents'))
New-Item -ItemType Directory -Force (Join-Path $ClaudeDir 'skills'), (Join-Path $ClaudeDir 'agents') | Out-Null

if (-not (Test-Path -LiteralPath (Join-Path $Repo 'config.local.json'))) {
  Copy-Item (Join-Path $Repo 'config.example.json') (Join-Path $Repo 'config.local.json')
  Write-Host "  설정 파일을 만들었습니다: $Repo\config.local.json — /harness-setup 으로 채우세요"
}
$mode = Install-Dir $Repo (Join-Path $ClaudeDir 'harness') @('.git')
foreach ($s in $Skills) { [void](Install-Dir $s.FullName (Join-Path $ClaudeDir "skills\$($s.Name)")) }
Remove-Retired
foreach ($a in $Agents) { Write-Agent $a }

Write-Host '완료. 스킬: /web-full · /web-lite · /desktop-app · /harness-resume · /harness-setup'
if ($mode -eq 'copy') { Write-Host '※ 복사로 설치했습니다. 저장소를 고친 뒤에는 이 스크립트를 다시 돌리세요. (개발자 모드를 켜면 링크로 설치됩니다)' }
if ($newAgentsDir) { Write-Host '※ 에이전트 폴더를 새로 만들었습니다. 열려 있는 Claude Code 를 다시 시작해야 작업자 에이전트가 보입니다.' }
Write-Host '※ 작업자 가드 hook 은 bash 로 돕니다 — Windows 에서는 Git Bash 가 있어야 합니다.'
