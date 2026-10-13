# claude-harness 설치 (Windows) — install.sh 와 같은 일을 Windows 의 Claude Code 사용자 설정(%USERPROFILE%\.claude)에 한다.
#   ~/.claude/harness           → 이 저장소
#   ~/.claude/skills/<스킬>      → skills/<스킬>
#   ~/.claude/agents/<에이전트>  ← agents/*.md (복사)
# 심볼릭 링크를 먼저 시도하고, 권한이 없으면(개발자 모드 꺼짐 · 관리자 아님) 복사한다.
# 복사로 설치했으면 harness\.install-mode 에 "copy" 를 남긴다 — 저장소를 고친 뒤에는 다시 돌려야 한다.
#
#   powershell -ExecutionPolicy Bypass -File \\wsl.localhost\<배포판>\home\<사용자>\project\claude-harness\install.ps1
#   지우기: 같은 명령 끝에 -Uninstall
param([switch]$Uninstall)
$ErrorActionPreference = 'Stop'

$Repo = $PSScriptRoot
$ClaudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
$Marker = '.install-mode'
$Skills = Get-ChildItem -Directory (Join-Path $Repo 'skills')
$Agents = Get-ChildItem -File (Join-Path $Repo 'agents') -Filter '*.md'

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

if ($Uninstall) {
  foreach ($s in $Skills) { [void](Remove-Ours (Join-Path $ClaudeDir "skills\$($s.Name)")) }
  foreach ($a in $Agents) {
    $t = Join-Path $ClaudeDir "agents\$($a.Name)"
    if (Test-Path -LiteralPath $t) { Remove-Item -LiteralPath $t -Force; Write-Host "  지움: $t" }
  }
  [void](Remove-Ours (Join-Path $ClaudeDir 'harness'))
  Write-Host '완료.'; return
}

Write-Host "claude-harness 설치 ($Repo)"
$newAgentsDir = -not (Test-Path (Join-Path $ClaudeDir 'agents'))
New-Item -ItemType Directory -Force (Join-Path $ClaudeDir 'skills'), (Join-Path $ClaudeDir 'agents') | Out-Null

if (-not (Test-Path -LiteralPath (Join-Path $Repo 'config.local.json'))) {
  Copy-Item (Join-Path $Repo 'config.example.json') (Join-Path $Repo 'config.local.json')
  Write-Host "  설정 파일을 만들었습니다: $Repo\config.local.json — /harness-setup 으로 채우세요"
}
$mode = Install-Dir $Repo (Join-Path $ClaudeDir 'harness') @('.git')
foreach ($s in $Skills) { [void](Install-Dir $s.FullName (Join-Path $ClaudeDir "skills\$($s.Name)")) }
foreach ($a in $Agents) {
  Copy-Item -LiteralPath $a.FullName -Destination (Join-Path $ClaudeDir 'agents') -Force
  Write-Host "  복사: $ClaudeDir\agents\$($a.Name)"
}

Write-Host '완료. 스킬: /web-full · /web-lite · /harness-setup'
if ($mode -eq 'copy') { Write-Host '※ 복사로 설치했습니다. 저장소를 고친 뒤에는 이 스크립트를 다시 돌리세요. (개발자 모드를 켜면 링크로 설치됩니다)' }
if ($newAgentsDir) { Write-Host '※ 에이전트 폴더를 새로 만들었습니다. 열려 있는 Claude Code 를 다시 시작해야 작업자 에이전트가 보입니다.' }
Write-Host '※ 작업자 가드 hook 은 bash 로 돕니다 — Windows 에서는 Git Bash 가 있어야 합니다.'
