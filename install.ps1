# Eagle installer for Windows (PowerShell 5.1+).
#
#   irm https://raw.githubusercontent.com/joeyrobert/eagle.cr/main/install.ps1 | iex
#
# Pin a version:  $env:EAGLE_VERSION = 'v0.1.0'; irm .../install.ps1 | iex
# Uninstall:      $env:EAGLE_UNINSTALL = '1'; irm .../install.ps1 | iex
#
# Installs eagle.exe, SDL2.dll and SDL2.lib into %LOCALAPPDATA%\eagle (or $env:EAGLE_HOME)
# with the engine source in src\, and adds its bin folder to your user PATH.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue' # Invoke-WebRequest is much faster without the progress bar

$Repo = 'joeyrobert/eagle.cr'
$Releases = if ($env:EAGLE_RELEASES) { $env:EAGLE_RELEASES } else { "https://github.com/$Repo/releases" }
$InstallDir = if ($env:EAGLE_HOME) { $env:EAGLE_HOME } else { Join-Path $env:LOCALAPPDATA 'eagle' }
$Version = if ($env:EAGLE_VERSION) { $env:EAGLE_VERSION } else { 'latest' }
$InstallDir = [IO.Path]::GetFullPath($InstallDir)
$unsafeDirs = @([IO.Path]::GetPathRoot($InstallDir), $env:USERPROFILE, $env:LOCALAPPDATA) |
  Where-Object { $_ } | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') }
if ($unsafeDirs -contains $InstallDir.TrimEnd('\')) {
  throw "EAGLE_HOME must be a dedicated install directory, not $InstallDir"
}
$BinDir = Join-Path $InstallDir 'bin'

function Get-UserPath { [Environment]::GetEnvironmentVariable('Path', 'User') }
function Set-UserPath($value) { [Environment]::SetEnvironmentVariable('Path', $value, 'User') }
function Split-PathList($value) { if ($value) { $value -split ';' | Where-Object { $_ } } else { @() } }

if ($env:EAGLE_UNINSTALL) {
  foreach ($p in 'bin', 'src', 'lib', 'wasm-toolchain') { Remove-Item -Recurse -Force (Join-Path $InstallDir $p) -ErrorAction SilentlyContinue }
  if ((Test-Path $InstallDir) -and -not (Get-ChildItem $InstallDir)) { Remove-Item $InstallDir }
  Set-UserPath ((Split-PathList (Get-UserPath) | Where-Object { $_ -ne $BinDir }) -join ';')
  Write-Host "Removed Eagle from $InstallDir and your PATH."
  return
}

if (-not [Environment]::Is64BitOperatingSystem) { throw 'Eagle needs 64-bit Windows.' }

# The release zip holds bin\eagle.exe, bin\SDL2.dll, lib\SDL2.lib and src\ (the engine source).
$asset = 'eagle-windows-x86_64.zip'
$url = if ($Version -eq 'latest') { "$Releases/latest/download/$asset" } else {
  $tag = if ($Version.StartsWith('v')) { $Version } else { "v$Version" }
  "$Releases/download/$tag/$asset"
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("eagle-install-" + [Guid]::NewGuid())
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
  Write-Host "==> Downloading $url"
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  Invoke-WebRequest -Uri $url -OutFile (Join-Path $tmp $asset) -UseBasicParsing
  Expand-Archive -Path (Join-Path $tmp $asset) -DestinationPath (Join-Path $tmp 'release') -Force
  $release = Join-Path $tmp 'release'
  foreach ($required in 'bin\eagle.exe', 'bin\SDL2.dll', 'lib\SDL2.lib', 'src\src\eagle.cr') {
    if (-not (Test-Path (Join-Path $release $required))) { throw "$asset has an unexpected layout (missing $required)" }
  }

  # Replace the previous install (idempotent), keeping anything else in the folder.
  New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
  foreach ($p in 'bin', 'src', 'lib') {
    Remove-Item -Recurse -Force (Join-Path $InstallDir $p) -ErrorAction SilentlyContinue
    if (Test-Path (Join-Path $release $p)) { Move-Item (Join-Path $release $p) (Join-Path $InstallDir $p) }
  }
} finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

$eagle = Join-Path $BinDir 'eagle.exe'
if (-not (Test-Path $eagle)) { throw "installation did not produce $eagle" }
$installed = & $eagle version
if ($LASTEXITCODE -ne 0) { throw "$eagle failed its version smoke test" }
Write-Host "==> Installed $installed to $eagle"

if ((Split-PathList (Get-UserPath)) -notcontains $BinDir) {
  Set-UserPath (((Split-PathList (Get-UserPath)) + $BinDir) -join ';')
  Write-Host "==> Added $BinDir to your user PATH (open a new terminal to pick it up)"
}
if (-not (($env:Path -split ';') -contains $BinDir)) { $env:Path = "$env:Path;$BinDir" }

if (-not (Get-Command crystal -ErrorAction SilentlyContinue)) {
  Write-Host ''
  Write-Host 'Crystal (>= 1.21) is not installed. eagle needs it to build games:'
  Write-Host '  https://crystal-lang.org/install/on_windows/'
  Write-Host 'Crystal on Windows also needs the Visual Studio C++ build tools (MSVC).'
}

Write-Host ''
Write-Host 'Get started:'
Write-Host '  eagle init mygame --yes'
Write-Host '  cd mygame; eagle run'
Write-Host ''
Write-Host "Uninstall: `$env:EAGLE_UNINSTALL = '1'; irm https://raw.githubusercontent.com/$Repo/main/install.ps1 | iex"
