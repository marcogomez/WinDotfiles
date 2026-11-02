# gitswitch.ps1
# Switch the active SSH key (and git identity) between GitHub accounts.
#
# usage: .\gitswitch.ps1            -> interactive menu
#        .\gitswitch.ps1 marco      -> Marco Gomez
#        .\gitswitch.ps1 tct        -> TheCodeTherapy
#        .\gitswitch.ps1 -Status    -> show which profile is active
#
# How it works: OpenSSH tries ~/.ssh/id_ed25519 and ~/.ssh/id_rsa by default.
# This script removes both default key files and copies the chosen profile's
# key into the default slot that matches its type, so only one key is offered.
[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [ValidateSet("marco", "tct")]
  [string]$Profile,

  [switch]$Status
)

$SshDir = "$HOME\.ssh"

$Profiles = [ordered]@{
  marco = @{
    Label = "Marco Gomez"
    Key   = "marco_gomez_id_ed25519"
    Name  = "Marco Gomez"
    Email = "marcogomez@mgz.me"
  }
  tct   = @{
    Label = "TheCodeTherapy"
    Key   = "thecodetherapy_id_rsa"
    Name  = "TheCodeTherapy"
    Email = "me@mgz.me"
  }
}

$DefaultKeys = @("id_ed25519", "id_rsa")

function Get-DefaultKeyName($pubFile) {
  $type = (Get-Content $pubFile -TotalCount 1).Split(" ")[0]
  switch ($type) {
    "ssh-ed25519" { return "id_ed25519" }
    "ssh-rsa" { return "id_rsa" }
    default { throw "Unsupported key type '$type' in $pubFile" }
  }
}

function Get-ActiveProfile {
  foreach ($id in $Profiles.Keys) {
    $pub = Join-Path $SshDir "$($Profiles[$id].Key).pub"
    if (-not (Test-Path $pub)) { continue }
    $slot = Join-Path $SshDir "$(Get-DefaultKeyName $pub).pub"
    if ((Test-Path $slot) -and ((Get-Content $slot -Raw) -eq (Get-Content $pub -Raw))) {
      return $id
    }
  }
  return $null
}

function Remove-DefaultKeys {
  foreach ($name in $DefaultKeys) {
    foreach ($file in @((Join-Path $SshDir $name), (Join-Path $SshDir "$name.pub"))) {
      if (Test-Path $file) {
        # Earlier switches strip inheritance; make sure we can still delete it.
        icacls $file /grant:r "$($env:USERNAME):(F)" > $null 2>&1
        attrib -R $file 2>$null
        Remove-Item $file -Force
      }
    }
  }
}

function Switch-KeyPair($id) {
  $p = $Profiles[$id]
  $srcPriv = Join-Path $SshDir $p.Key
  $srcPub = "$srcPriv.pub"

  foreach ($f in @($srcPriv, $srcPub)) {
    if (-not (Test-Path $f)) {
      Write-Host "Missing key file: $f" -ForegroundColor Red
      exit 1
    }
  }

  $slot = Get-DefaultKeyName $srcPub
  $destPriv = Join-Path $SshDir $slot
  $destPub = "$destPriv.pub"

  Remove-DefaultKeys
  Copy-Item $srcPriv $destPriv -Force
  Copy-Item $srcPub $destPub -Force

  # OpenSSH refuses private keys readable by anyone but the owner.
  icacls $destPriv /inheritance:r /grant:r "$($env:USERNAME):F" "SYSTEM:F" > $null

  git config --global user.name $p.Name
  git config --global user.email $p.Email

  Write-Host "Switched to $($p.Label)"
  Write-Host "  ssh key : $slot  (from $($p.Key))"
  Write-Host "  git user: $($p.Name) <$($p.Email)>"
  Write-Host "Test with: ssh -T git@github.com"
}

function Show-Status {
  $active = Get-ActiveProfile
  if ($active) {
    Write-Host "Active profile: $($Profiles[$active].Label)"
  }
  else {
    Write-Host "Active profile: none (no default key matches a known profile)"
  }
  Write-Host "Git identity  : $(git config --global user.name) <$(git config --global user.email)>"
}

if (-not (Test-Path $SshDir)) {
  Write-Host "No SSH directory at $SshDir" -ForegroundColor Red
  exit 1
}

if ($Status) {
  Show-Status
  exit 0
}

if (-not $Profile) {
  $active = Get-ActiveProfile
  Write-Host "Select profile:"
  $i = 1
  $keys = @($Profiles.Keys)
  foreach ($id in $keys) {
    $mark = if ($id -eq $active) { "  (active)" } else { "" }
    Write-Host "$i) $($Profiles[$id].Label)$mark"
    $i++
  }
  $choice = Read-Host "Enter choice (1-$($keys.Count))"
  if ($choice -notmatch '^\d+$' -or [int]$choice -lt 1 -or [int]$choice -gt $keys.Count) {
    Write-Host "Invalid choice." -ForegroundColor Red
    exit 1
  }
  $Profile = $keys[[int]$choice - 1]
}

Switch-KeyPair $Profile
