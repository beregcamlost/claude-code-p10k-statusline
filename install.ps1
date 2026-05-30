<#
.SYNOPSIS
  Installs the claude-code-p10k-statusline on Windows: the script, the Claude Code
  settings.json wiring, the MesloLGS NF Nerd Font (per-user, no admin), and best-effort
  font configuration for Windows Terminal and VS Code / Cursor.

.DESCRIPTION
  Safe by design: every file it modifies is backed up to "<file>.bak-<timestamp>" first,
  JSON is only rewritten when it parses cleanly (otherwise the installer prints a manual
  snippet instead of risking corruption), and -DryRun shows what would happen without
  touching anything.

.PARAMETER NoFont           Skip downloading/installing the Nerd Font.
.PARAMETER NoTerminalConfig Skip editing Windows Terminal / VS Code font settings.
.PARAMETER DryRun           Print actions without making changes.
.PARAMETER Ref              Git ref (branch/tag) to fetch statusline.sh from. Default: main.

.EXAMPLE
  irm https://raw.githubusercontent.com/beregcamlost/claude-code-p10k-statusline/main/install.ps1 | iex
.EXAMPLE
  .\install.ps1 -NoTerminalConfig
#>
[CmdletBinding()]
param(
  [switch]$NoFont,
  [switch]$NoTerminalConfig,
  [switch]$DryRun,
  [string]$Ref = 'main'
)

$ErrorActionPreference = 'Stop'
$RepoRawBase = "https://raw.githubusercontent.com/beregcamlost/claude-code-p10k-statusline/$Ref"
$FontBase    = 'https://github.com/romkatv/powerlevel10k-media/raw/master'
$FontFiles   = @('MesloLGS NF Regular.ttf','MesloLGS NF Bold.ttf','MesloLGS NF Italic.ttf','MesloLGS NF Bold Italic.ttf')
$FontFamily  = 'MesloLGS NF'

function Info($m){ Write-Host "  $m" -ForegroundColor Cyan }
function Ok  ($m){ Write-Host "  [ok] $m" -ForegroundColor Green }
function Warn($m){ Write-Host "  [!]  $m" -ForegroundColor Yellow }
function Step($m){ Write-Host "`n==> $m" -ForegroundColor White }

# Back up a file (timestamped) before we touch it. Honors -DryRun.
function Backup-File($path){
  if(Test-Path -LiteralPath $path){
    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $bak = "$path.bak-$stamp"
    if($DryRun){ Info "would back up $path -> $bak" }
    else { Copy-Item -LiteralPath $path -Destination $bak -Force; Info "backed up -> $bak" }
  }
}

# Merge keys into a JSON file, preserving existing content. Only writes if the existing
# file parses as strict JSON (PS 5.1 ConvertFrom-Json rejects comments/trailing commas);
# on failure returns $false so the caller can print a manual snippet instead of corrupting.
function Merge-Json {
  param([string]$Path, [scriptblock]$Apply)
  $obj = $null
  if(Test-Path -LiteralPath $Path){
    $raw = Get-Content -LiteralPath $Path -Raw
    if([string]::IsNullOrWhiteSpace($raw)){ $obj = [pscustomobject]@{} }
    else {
      try { $obj = $raw | ConvertFrom-Json } catch { return $false }
    }
  } else {
    $obj = [pscustomobject]@{}
  }
  & $Apply $obj
  if($DryRun){ Info "would write $Path"; return $true }
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  # UTF-8 NO BOM: PS 5.1 'Set-Content -Encoding UTF8' prepends a BOM, and Node (Claude Code) rejects a BOM in settings.json.
  [System.IO.File]::WriteAllText($Path, ($obj | ConvertTo-Json -Depth 50), (New-Object System.Text.UTF8Encoding($false)))
  return $true
}

# Idempotently set a property on a PSCustomObject (add or overwrite).
function Set-Prop($obj, $name, $value){
  if($obj.PSObject.Properties.Name -contains $name){ $obj.$name = $value }
  else { $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value }
}

Write-Host "claude-code-p10k-statusline installer (Windows)" -ForegroundColor Magenta
if($DryRun){ Warn "DRY RUN - no changes will be made" }

# --------------------------------------------------------------------------------------
Step "1/5  Install statusline.sh -> ~/.claude/statusline.sh"
$claudeDir = Join-Path $HOME '.claude'
$dest = Join-Path $claudeDir 'statusline.sh'
# $PSScriptRoot is EMPTY under `irm | iex`; guard so Join-Path never receives an empty Path (it throws).
$localSrc = if($PSScriptRoot){ Join-Path $PSScriptRoot 'statusline.sh' } else { $null }   # set only when run from a clone
if(-not (Test-Path -LiteralPath $claudeDir)){
  if($DryRun){ Info "would create $claudeDir" } else { New-Item -ItemType Directory -Force -Path $claudeDir | Out-Null }
}
Backup-File $dest
if($localSrc -and (Test-Path -LiteralPath $localSrc)){
  $content = Get-Content -LiteralPath $localSrc -Raw
  Info "using local copy: $localSrc"
} else {
  Info "downloading $RepoRawBase/statusline.sh"
  $content = (Invoke-WebRequest -Uri "$RepoRawBase/statusline.sh" -UseBasicParsing).Content
}
# Write with LF endings and NO BOM - it is a bash script run by Git-bash; CRLF or a BOM break it.
$content = $content -replace "`r`n", "`n"
if(-not $DryRun){
  [System.IO.File]::WriteAllText($dest, $content, (New-Object System.Text.UTF8Encoding($false)))
  Ok "wrote $dest"
} else { Info "would write $dest (LF, no BOM)" }

# --------------------------------------------------------------------------------------
Step "2/5  Wire up ~/.claude/settings.json (statusLine block)"
$settings = Join-Path $claudeDir 'settings.json'
Backup-File $settings
$wired = Merge-Json -Path $settings -Apply {
  param($o)
  Set-Prop $o 'statusLine' ([pscustomobject]@{
    type='command'; command='~/.claude/statusline.sh'; padding=0; refreshInterval=10
  })
}
if($wired){ Ok "statusLine configured in settings.json" }
else {
  Warn "settings.json did not parse as strict JSON. Add this block manually:"
  Write-Host '    "statusLine": { "type": "command", "command": "~/.claude/statusline.sh", "padding": 0, "refreshInterval": 10 }' -ForegroundColor Gray
}

# --------------------------------------------------------------------------------------
Step "3/5  Check runtime deps (bash + jq)"
$bash = Get-Command bash -ErrorAction SilentlyContinue
$jq   = Get-Command jq   -ErrorAction SilentlyContinue
if($bash){ Ok "bash found: $($bash.Source)" } else { Warn "bash NOT found. Install Git for Windows (provides Git-bash); the statusline runs under bash." }
if($jq)  { Ok "jq found:   $($jq.Source)"   } else { Warn "jq NOT found. Install with: winget install jqlang.jq  (the statusline needs jq at runtime)." }

# --------------------------------------------------------------------------------------
Step "4/5  Install MesloLGS NF (per-user, no admin)"
if($NoFont){ Info "skipped (-NoFont)" }
else {
  $userFonts = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
  $regPath   = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Fonts'
  if(-not (Test-Path -LiteralPath $userFonts)){
    if($DryRun){ Info "would create $userFonts" } else { New-Item -ItemType Directory -Force -Path $userFonts | Out-Null }
  }
  # On a machine that never installed a per-user font, the HKCU Fonts key is absent, and
  # New-ItemProperty won't create it (-Force only overwrites an existing value). Create it first.
  if(-not $DryRun -and -not (Test-Path -LiteralPath $regPath)){ New-Item -Path $regPath -Force | Out-Null }
  foreach($f in $FontFiles){
    $target = Join-Path $userFonts $f
    $regName = ($f -replace '\.ttf$','') + ' (TrueType)'
    if(Test-Path -LiteralPath $target){ Info "$f already installed"; continue }
    $url = "$FontBase/$([uri]::EscapeDataString($f))"
    if($DryRun){ Info "would download+install $f"; continue }
    try {
      Invoke-WebRequest -Uri $url -OutFile $target -UseBasicParsing
      New-ItemProperty -Path $regPath -Name $regName -Value $target -PropertyType String -Force | Out-Null
      Ok "installed $f"
    } catch { Warn "failed to install $f : $($_.Exception.Message)" }
  }
  Info "If glyphs still look like boxes, fully restart the terminal app (fonts load at startup)."
}

# --------------------------------------------------------------------------------------
Step "5/5  Point terminals at $FontFamily (best-effort, backed up)"
if($NoTerminalConfig){ Info "skipped (-NoTerminalConfig)" }
else {
  # ---- Windows Terminal (Store / Preview / unpackaged) ----
  $wtPaths = @(
    (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
    (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
  ) | Where-Object { Test-Path -LiteralPath $_ }

  foreach($wt in $wtPaths){
    Backup-File $wt
    $done = Merge-Json -Path $wt -Apply {
      param($o)
      if(-not ($o.PSObject.Properties.Name -contains 'profiles')){ Set-Prop $o 'profiles' ([pscustomobject]@{}) }
      if(-not ($o.profiles.PSObject.Properties.Name -contains 'defaults')){ Set-Prop $o.profiles 'defaults' ([pscustomobject]@{}) }
      Set-Prop $o.profiles.defaults 'font' ([pscustomobject]@{ face = $FontFamily })
    }
    if($done){ Ok "Windows Terminal -> $FontFamily ($wt)" }
    else { Warn "WT settings has comments/could not parse safely. Set Profiles > Defaults > Appearance > Font face = '$FontFamily' manually ($wt)" }
  }
  if(-not $wtPaths){ Info "Windows Terminal settings not found - skipping." }

  # ---- VS Code & Cursor ----
  $codePaths = @(
    (Join-Path $env:APPDATA 'Code\User\settings.json'),
    (Join-Path $env:APPDATA 'Code - Insiders\User\settings.json'),
    (Join-Path $env:APPDATA 'Cursor\User\settings.json')
  ) | Where-Object { Test-Path -LiteralPath $_ }

  foreach($cp in $codePaths){
    Backup-File $cp
    $done = Merge-Json -Path $cp -Apply {
      param($o)
      Set-Prop $o 'terminal.integrated.fontFamily' "$FontFamily, monospace"
    }
    if($done){ Ok "VS Code/Cursor terminal font -> $FontFamily ($cp)" }
    else { Warn "VS Code settings has comments/could not parse safely. Add 'terminal.integrated.fontFamily: $FontFamily, monospace' manually ($cp)" }
  }
  if(-not $codePaths){ Info "VS Code / Cursor settings not found - skipping." }
}

Write-Host "`nDone." -ForegroundColor Magenta
Write-Host "Open a new Claude Code session (or wait one refresh tick) to see the statusline." -ForegroundColor Gray
Write-Host "IDE terminal WITHOUT a Nerd Font? set CC_STATUSLINE_GLYPHS=emoji (or auto) in that terminal's env." -ForegroundColor Gray
