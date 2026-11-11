param(
  [switch]$BuildFirst,
  [string]$SupabaseUrl,
  [string]$SupabaseKey
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$release = Join-Path $root 'build\windows\x64\runner\Release'
$script = Join-Path $PSScriptRoot 'secure_id.nsi'
$dist = Join-Path $root 'dist'

function Find-Makensis {
  $command = Get-Command makensis.exe -ErrorAction SilentlyContinue
  if ($command) { return $command.Source }

  $candidates = @(
    'C:\Program Files (x86)\NSIS\makensis.exe',
    'C:\Program Files\NSIS\makensis.exe',
    (Join-Path $env:LOCALAPPDATA 'Programs\NSIS\makensis.exe')
  )
  foreach ($candidate in $candidates) {
    if (Test-Path $candidate) { return $candidate }
  }
  return $null
}

$makensis = Find-Makensis
if (-not $makensis) {
  throw 'NSIS was not found. Install it with: winget install --id NSIS.NSIS -e'
}

if ($BuildFirst) {
  if (($SupabaseUrl -and -not $SupabaseKey) -or ($SupabaseKey -and -not $SupabaseUrl)) {
    throw 'Pass both -SupabaseUrl and -SupabaseKey, or neither.'
  }
  # flutter_tts uses NuGet to fetch Microsoft.Windows.CppWinRT on Windows.
  $tools = Join-Path $root 'tools'
  $env:PATH = "$tools;C:\Program Files\Git\cmd;$env:PATH"
  if (-not (Get-Command nuget.exe -ErrorAction SilentlyContinue)) {
    throw 'nuget.exe was not found. Put it in tools\nuget.exe or on PATH; the flutter_tts Windows plugin needs it.'
  }
  $buildArgs = @('build', 'windows', '--release')
  if ($SupabaseUrl) {
    $buildArgs += "--dart-define=SUPABASE_URL=$SupabaseUrl"
    $buildArgs += "--dart-define=SUPABASE_ANON_KEY=$SupabaseKey"
  }
  & 'F:\flutter\bin\flutter.bat' @buildArgs
  if ($LASTEXITCODE -ne 0) { throw 'flutter build windows failed.' }
}

if (-not (Test-Path (Join-Path $release 'secure_id.exe'))) {
  throw "No release build found at $release. Run with -BuildFirst or build Windows first."
}

New-Item -ItemType Directory -Force -Path $dist | Out-Null

# Read the version from pubspec.yaml so the installer, the APK and the in-app
# version badge never drift apart.
$pubspec = Get-Content (Join-Path $root 'pubspec.yaml') -Raw
$versionMatch = [regex]::Match($pubspec, '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)')
if (-not $versionMatch.Success) { throw 'Could not read version from pubspec.yaml.' }
$version = $versionMatch.Groups[1].Value

Push-Location $root
try {
  & $makensis /V2 "/DPRODUCT_VERSION=$version" $script
  if ($LASTEXITCODE -ne 0) { throw 'makensis failed.' }
}
finally {
  Pop-Location
}

$out = Join-Path $dist "SecureID-Setup-$version.exe"
if (-not (Test-Path $out)) { throw "Installer was not created at $out." }
$size = [math]::Round((Get-Item $out).Length / 1MB, 2)
Write-Host ''
Write-Host "Installer: $out ($size MB)" -ForegroundColor Green
