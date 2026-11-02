# ┌─────────────────────────────────────────────────────────────────────────┐
# │ WinDotfiles setup script, by Marco Gomez (@TheCodeTherapy) 2025         │
# ├─────────────────────────────────────────────────────────────────────────┤
# │ C:\Users\marcogomez\WinDotfiles\setup.ps1                               │
# ├─────────────────────────────────────────────────────────────────────────┤
# │ This script creates symbolic links for your PowerShell profiles.        │
# │ It will link the profile in your WinDotfiles directory to the           │
# │ appropriate location for PowerShell 7 and 5. Among other things.        │
# ├─────────────────────────────────────────────────────────────────────────┤
# │ Written to be used on Windows 10 Enterprise LTSC 2021 -> 2031 ...       │
# │ because fuck Microsoft and its bloat, ads, and abusive data mining on   │
# │ a fucking PAID operating system. We're not idiots, nor products.        │
# ├─────────────────────────────────────────────────────────────────────────┤
# │ usage: .\setup.ps1                                                      │
# └─────────────────────────────────────────────────────────────────────────┘

# NOTE: All packages are installed through winget. On Windows 10 LTSC winget
# may not be available right after installation; if the script reports it as
# missing, install "App Installer" and run the script again.

# NOTE: Before running nvim for the first time, you must install any recent
# NodeJS LTS version through nvm, as some neovim scripts will need NodeJS
# to install and configure plugins.
# NOTE: Run this after the install:
# Set-ExecutionPolicy RemoteSigned -Scope CurrentUser

# 🔹 Package List
$wingetPackages = @(
  "Microsoft.WindowsTerminal",
  "Microsoft.PowerShell",
  "JanDeDobbeleer.OhMyPosh",
  "LLVM.LLVM",
  "AuthorSoftware.NVMWindows",
  "JesseDuffield.lazygit",
  "sharkdp.fd",
  "junegunn.fzf",
  "BurntSushi.ripgrep.MSVC",
  "Neovim.Neovim",
  "tree-sitter.tree-sitter-cli",
  "eza-community.eza",
  "Rustlang.Rustup"
)

# 🔹 Auto-Elevate: Relaunch as Administrator if not already elevated
$scriptPath = $MyInvocation.MyCommand.Definition
$scriptArgs = $args -join ' '
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
  Write-Host "🔸 Elevation required. Restarting as Administrator..."
  Start-Process pwsh -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" $scriptArgs" -Verb RunAs
  exit
}

Write-Host "✅ Running as Administrator."

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

$dotfilesProfile = Join-Path $scriptDir "dotfiles\powershell\Microsoft.PowerShell_profile.ps1"
$dotfilesTerminalSettings = Join-Path $scriptDir "dotfiles\terminal\settings.json"
$dotfilesVSCodeSettings = Join-Path $scriptDir "dotfiles\vscode\settings.json"
$dotfilesWinfetchSettings = Join-Path $scriptDir "dotfiles\winfetch\config.ps1"
$dotfilesNvimConfig = Join-Path $scriptDir "dotfiles\nvim"
$dotBashrc = Join-Path $scriptDir "dotfiles\bash\bashrc"
$dotInputrc = Join-Path $scriptDir "dotfiles\bash\inputrc"

# Define target paths ========================================================
New-Item -ItemType Directory -Path "$env:USERPROFILE\.config\winfetch" -Force
$ps7Profile = "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
$ps5Profile = "$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
$vscodeSettingsPath = "$env:APPDATA\Code\User\settings.json"
$winfetchSettingsPath = "$env:USERPROFILE\.config\winfetch\config.ps1"
$nvimConfigPath = "$env:LOCALAPPDATA\nvim"
$dotBashrcTarget = "$env:USERPROFILE\.bashrc"
$dotInputrcTarget = "$env:USERPROFILE\.inputrc"

$terminalSettingsPath = Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
# Fallback for manually installed Windows Terminal
if (-Not (Test-Path $terminalSettingsPath)) {
  $terminalSettingsPath = Join-Path $env:LOCALAPPDATA "Microsoft\Windows Terminal\settings.json"
}
# ============================================================================

# Ensure the source profile exists
if (-Not (Test-Path $dotfilesProfile)) {
  Write-Host "❌ Error: Source profile not found at $dotfilesProfile" -ForegroundColor Red
  exit 1
}

# Function to create symbolic link
function New-Symlink {
  param (
    [string]$target,
    [string]$link
  )

  # Check if link already exists and remove it if necessary
  if (Test-Path $link) {
    Write-Host "Removing existing profile at $link"
    Remove-Item -Force $link
  }

  # Create the symbolic link
  Write-Host "Creating symbolic link: $link -> $target"
  New-Item -ItemType SymbolicLink -Path $link -Target $target | Out-Null

  # Verify creation
  if (Test-Path $link) {
    Write-Host "✅ Symlink created successfully: $link -> $(Get-Item $link).Target"
  }
  else {
    Write-Host "❌ Failed to create symlink: $link" -ForegroundColor Red
  }
}

# Function to pause execution and wait for a key press
function Wait-ForKeyPress {
  Write-Host "`nPress any key to exit..."
  $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# 🔹 Install Winget Packages
function Install-Winget-Packages {
  if (-Not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host "⚠️ Winget is not installed or not available in the PATH." -ForegroundColor Yellow
    return
  }

  foreach ($package in $wingetPackages) {
    $installed = winget list --id $package --exact --accept-source-agreements 2>$null
    if ($installed -match $package) {
      Write-Host "✅ $package is already installed. Checking for updates..."
      winget upgrade --id $package --exact --silent --accept-source-agreements --accept-package-agreements
    }
    else {
      Write-Host "📦 Installing $package..."
      winget install --id $package --exact --silent --accept-source-agreements --accept-package-agreements
    }
  }
}

# 🔹 Add LLVM to the user PATH (winget's silent LLVM install does not do it)
function Add-LlvmToPath {
  $llvmBin = Join-Path $env:ProgramFiles "LLVM\bin"
  $clang = Join-Path $llvmBin "clang.exe"

  if (-Not (Test-Path $clang)) {
    Write-Host "⚠️ LLVM is not installed at $llvmBin. Skipping PATH update." -ForegroundColor Yellow
    return
  }

  $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
  $entries = $userPath -split ";" | Where-Object { $_ -ne "" }
  if ($entries -contains $llvmBin) {
    Write-Host "✅ LLVM is already in the user PATH."
  }
  else {
    Write-Host "🔧 Adding $llvmBin to the user PATH..."
    [Environment]::SetEnvironmentVariable("Path", (($entries + $llvmBin) -join ";"), "User")
    $env:Path = "$env:Path;$llvmBin"
    Write-Host "✅ LLVM added to the user PATH. Open a new shell for it to take effect."
  }

  # nvim-treesitter (and LazyVim's health check) only detect cl, gcc, or the
  # compiler named by CC. clang is not probed, so point CC at it explicitly.
  $cc = [Environment]::GetEnvironmentVariable("CC", "User")
  if ($cc) {
    Write-Host "✅ CC is already set to '$cc' for the user."
  }
  else {
    Write-Host "🔧 Setting user environment variable CC=clang..."
    [Environment]::SetEnvironmentVariable("CC", "clang", "User")
    $env:CC = "clang"
    Write-Host "✅ CC=clang set. Open a new shell for it to take effect."
  }
}

# 🔹 Add the WinDotfiles bin directory to the user PATH
function Add-DotfilesBinToPath {
  $binDir = Join-Path $scriptDir "bin"

  $entries = [Environment]::GetEnvironmentVariable("Path", "User") -split ";" | Where-Object { $_ -ne "" }
  if ($entries -contains $binDir) {
    Write-Host "✅ $binDir is already in the user PATH."
    return
  }

  Write-Host "🔧 Adding $binDir to the user PATH..."
  [Environment]::SetEnvironmentVariable("Path", (($entries + $binDir) -join ";"), "User")
  $env:Path = "$env:Path;$binDir"
  Write-Host "✅ $binDir added to the user PATH. Open a new shell for it to take effect."
}

# 🔹 Disable hibernation (also removes hiberfil.sys and disables Fast Startup)
function Disable-Hibernation {
  $states = powercfg /availablesleepstates | Out-String
  if ($states -match "Hibernation has not been enabled") {
    Write-Host "✅ Hibernation is already disabled."
    return
  }

  Write-Host "🔧 Disabling hibernation..."
  powercfg /hibernate off
  if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Hibernation disabled."
  }
  else {
    Write-Host "❌ Failed to disable hibernation (powercfg exit code $LASTEXITCODE)." -ForegroundColor Red
  }
}

# 🔹 Detect WSL2 and the Ubuntu distro
# wsl.exe writes UTF-16LE to a pipe, so the console encoding must be switched
# to Unicode while capturing its output, otherwise every line reads as nulls.
function Get-WslState {
  $state = [PSCustomObject]@{ Wsl2 = $false; Ubuntu = $false }

  if (-Not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    return $state
  }

  $prevEncoding = [Console]::OutputEncoding
  try {
    [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
    $list = wsl.exe --list --verbose 2>$null
    $exit = $LASTEXITCODE
  }
  finally {
    [Console]::OutputEncoding = $prevEncoding
  }

  if ($exit -ne 0 -or -not $list) {
    return $state
  }

  # Any registered distro on version 2 means WSL2 is installed and working
  $state.Wsl2 = [bool]($list -match '^\*?\s*\S+\s+\S+\s+2\s*$')
  $state.Ubuntu = [bool]($list -match '^\*?\s*Ubuntu\s+\S+\s+2\s*$')
  return $state
}

# 🔹 Install Docker Desktop, only when WSL2 is in place for its backend
function Install-DockerDesktop {
  $wsl = Get-WslState
  if (-Not $wsl.Wsl2) {
    Write-Host "⚠️ WSL2 is not installed. Skipping Docker Desktop. Run 'wsl --install', reboot, and run this script again." -ForegroundColor Yellow
    return
  }
  if ($wsl.Ubuntu) {
    Write-Host "✅ WSL2 with Ubuntu detected."
  }
  else {
    Write-Host "✅ WSL2 detected (no Ubuntu distro registered)."
  }

  $dockerExe = Join-Path $env:ProgramFiles "Docker\Docker\Docker Desktop.exe"
  if (Test-Path $dockerExe) {
    Write-Host "✅ Docker Desktop is already installed."
    return
  }

  if (-Not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host "⚠️ Winget is not available. Cannot install Docker Desktop." -ForegroundColor Yellow
    return
  }

  Write-Host "📦 Installing Docker Desktop..."
  winget install --id Docker.DockerDesktop --exact --silent --accept-source-agreements --accept-package-agreements
  if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Docker Desktop installed. Log out and back in so your user joins the docker-users group."
  }
  else {
    Write-Host "❌ Docker Desktop install failed (winget exit code $LASTEXITCODE)." -ForegroundColor Red
  }
}

if ($isAdmin) {
  Write-Host "🔸 Installing packages..."
  Install-Winget-Packages
  Add-LlvmToPath
  Add-DotfilesBinToPath
  Disable-Hibernation
  Install-DockerDesktop
}

$ps7ProfileDir = Split-Path $ps7Profile -Parent
if (-Not (Test-Path $ps7ProfileDir)) {
  Write-Host "📁 Creating missing directory: $ps7ProfileDir"
  New-Item -ItemType Directory -Path $ps7ProfileDir | Out-Null
}

$ps5ProfileDir = Split-Path $ps5Profile -Parent
if (-Not (Test-Path $ps5ProfileDir)) {
  Write-Host "📁 Creating missing directory: $ps5ProfileDir"
  New-Item -ItemType Directory -Path $ps5ProfileDir | Out-Null
}

# Create symlinks for PowerShell 7 and 5
New-Symlink -target $dotfilesProfile -link $ps7Profile
New-Symlink -target $dotfilesProfile -link $ps5Profile
# New-Symlink -target $dotfilesTerminalSettings -link $terminalSettingsPath
New-Symlink -target $dotfilesVSCodeSettings -link $vscodeSettingsPath
New-Symlink -target $dotfilesWinfetchSettings -link $winfetchSettingsPath
New-Symlink -target $dotfilesNvimConfig -link $nvimConfigPath
New-Symlink -target $dotBashrc -link $dotBashrcTarget
New-Symlink -target $dotInputrc -link $dotInputrcTarget

Write-Host "🎉 All symbolic links have been created successfully!" -ForegroundColor Green

if ($isAdmin) {
  Wait-ForKeyPress
}
