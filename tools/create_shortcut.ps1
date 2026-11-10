# Creates a SecureID shortcut on the current user's desktop.
# Build the Windows app first: flutter build windows --release

$exe = Join-Path $PSScriptRoot '..\build\windows\x64\runner\Release\secure_id.exe'
if (-not (Test-Path $exe)) {
    Write-Error "Could not find $exe. Run 'flutter build windows --release' first."
    exit 1
}

$target = (Resolve-Path $exe).Path
$desktop = [Environment]::GetFolderPath('Desktop')
$linkPath = Join-Path $desktop 'SecureID.lnk'

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($linkPath)
$shortcut.TargetPath = $target
$shortcut.WorkingDirectory = Split-Path $target
$shortcut.IconLocation = "$target,0"
$shortcut.Description = 'SecureID - offline password, passkey and authenticator vault'
$shortcut.Save()

Write-Output "Created $linkPath"
