#!/usr/bin/env pwsh
# Build the Ferrule Flutter app bundle and upload to Play Console internal testing.
#
# Examples:
#   .\release-internal.ps1                       # build + upload draft + browser-promote
#   .\release-internal.ps1 -SkipBuild            # re-use the last AAB
#   .\release-internal.ps1 -Notes "Hotfix: ..."  # override notes inline
#   .\release-internal.ps1 -Track alpha          # different track
#   .\release-internal.ps1 -NoPromote            # leave release as draft on Play Console
#   .\release-internal.ps1 -DryRun               # build only, no upload, no promote
#
# First-time setup for browser promote:
#   cd scripts
#   npm install                                  # also runs `playwright install chromium`
#   node promote-via-browser.mjs --login         # opens Chromium, sign in once

[CmdletBinding()]
param(
  [ValidateSet('internal', 'alpha', 'beta', 'production')]
  [string]$Track = 'internal',
  [string]$Notes,
  [string]$NotesFile,
  [ValidateSet('completed', 'draft', 'inProgress', 'halted')]
  [string]$Status = 'draft',
  [string]$Language = 'en-AU',
  [switch]$SkipBuild,
  [switch]$DryRun,
  [switch]$NoPromote
)

$ErrorActionPreference = 'Stop'

$ScriptDir = $PSScriptRoot
$AppDir = (Resolve-Path (Join-Path $ScriptDir '..')).Path

# Parse version from pubspec.yaml. Format: version: <name>+<code>
$pubspecPath = Join-Path $AppDir 'pubspec.yaml'
$pubspec = Get-Content $pubspecPath -Raw
if ($pubspec -notmatch '(?m)^version:\s*([\d\.]+)\+(\d+)\s*$') {
  throw "Could not parse 'version:' line from $pubspecPath"
}
$VersionName = $Matches[1]
$VersionCode = $Matches[2]
Write-Host "[release-internal] version $VersionName (code $VersionCode)"

# Compose release notes
if ($Notes) {
  $ReleaseNotes = $Notes
} elseif ($NotesFile) {
  if (-not (Test-Path $NotesFile)) { throw "Notes file not found: $NotesFile" }
  $ReleaseNotes = (Get-Content $NotesFile -Raw).Trim()
} else {
  $changelogPath = Join-Path $AppDir 'CHANGELOG.md'
  if (Test-Path $changelogPath) {
    $changelog = Get-Content $changelogPath -Raw
    $sections = [regex]::Matches($changelog, '(?ms)^## .+?(?=^## |\Z)')
    if ($sections.Count -gt 0) {
      $top = $sections[0].Value
      $body = ($top -split "`r?`n", 2)[1]
      if (-not $body) { $body = '' }
      $ReleaseNotes = $body.Trim()
    }
  }
}

if (-not $ReleaseNotes) {
  Write-Warning "[release-internal] release notes are empty"
} else {
  Write-Host "[release-internal] release notes:"
  $ReleaseNotes -split "`r?`n" | ForEach-Object { Write-Host "  $_" }
}

$AabPath = Join-Path $AppDir 'build\app\outputs\bundle\release\app-release.aab'

# Build. Flutter's bundleRelease may emit harmless "failed to strip debug
# symbols" to stderr; PS 5.1 with ErrorActionPreference='Stop' would turn that
# into a terminating NativeCommandError. Drop to 'Continue' for the build and
# judge success on exit code + AAB mtime.
if (-not $SkipBuild) {
  $beforeMtime = if (Test-Path $AabPath) { (Get-Item $AabPath).LastWriteTimeUtc } else { [DateTime]::MinValue }
  $prevErrAction = $ErrorActionPreference
  $secretsPath = Join-Path $AppDir 'secrets.json'
  $buildArgs = @('build','appbundle','--release')
  if (Test-Path $secretsPath) {
    $buildArgs += "--dart-define-from-file=$secretsPath"
  }
  Push-Location $AppDir
  try {
    $ErrorActionPreference = 'Continue'
    Write-Host "[release-internal] flutter $($buildArgs -join ' ')"
    & flutter @buildArgs 2>&1 | ForEach-Object { Write-Host $_ }
    $buildExit = $LASTEXITCODE
  } finally {
    Pop-Location
    $ErrorActionPreference = $prevErrAction
  }
  $afterMtime = if (Test-Path $AabPath) { (Get-Item $AabPath).LastWriteTimeUtc } else { [DateTime]::MinValue }
  $aabFresh = $afterMtime -gt $beforeMtime
  if ($buildExit -ne 0) {
    if ($aabFresh) {
      Write-Warning "[release-internal] flutter build exited $buildExit but a fresh AAB was produced (likely the harmless 'failed to strip debug symbols' NDK quirk). Continuing."
    } else {
      throw "flutter build appbundle failed (exit $buildExit) and no fresh AAB was produced."
    }
  }
}

if (-not (Test-Path $AabPath)) {
  throw "AAB not found at $AabPath. Run without -SkipBuild or build manually first."
}
$AabSize = (Get-Item $AabPath).Length
Write-Host ("[release-internal] AAB ready: {0} ({1:N1} MiB)" -f $AabPath, ($AabSize / 1MB))

if ($DryRun) {
  Write-Host "[release-internal] DRY RUN -- would upload to track '$Track' with status '$Status'"
  return
}

# Stage release notes to a temp file (avoids quoting headaches with newlines)
$NotesTemp = Join-Path $ScriptDir '.release-notes.tmp.txt'
if ($ReleaseNotes) {
  Set-Content -Path $NotesTemp -Value $ReleaseNotes -Encoding utf8 -NoNewline
} else {
  Set-Content -Path $NotesTemp -Value '' -Encoding utf8 -NoNewline
}

try {
  Push-Location $ScriptDir
  try {
    if (-not (Test-Path 'node_modules')) {
      Write-Host "[release-internal] installing googleapis + playwright (one-time)..."
      npm install --silent
      if ($LASTEXITCODE -ne 0) { throw "npm install failed (exit $LASTEXITCODE)" }
    }

    $nodeArgs = @(
      'play-upload.mjs',
      '--aab', $AabPath,
      '--track', $Track,
      '--status', $Status,
      '--language', $Language,
      '--name', $VersionName,
      '--notes', $NotesTemp
    )
    & node @nodeArgs
    if ($LASTEXITCODE -ne 0) { throw "play-upload.mjs failed (exit $LASTEXITCODE)" }
  } finally {
    Pop-Location
  }
} finally {
  Remove-Item $NotesTemp -ErrorAction SilentlyContinue
}

if (-not $NoPromote -and $Status -eq 'draft') {
  Push-Location $ScriptDir
  try {
    Write-Host "[release-internal] promoting draft via browser..."
    & node promote-via-browser.mjs --release-name $VersionName --version-code $VersionCode
    if ($LASTEXITCODE -ne 0) { throw "promote-via-browser.mjs failed (exit $LASTEXITCODE)" }
  } finally {
    Pop-Location
  }
}

Write-Host "[release-internal] done."
