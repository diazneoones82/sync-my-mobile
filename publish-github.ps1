param(
    [string]$Owner = "",
    [string]$Repo = "sync-my-mobile",
    [string]$Description = "Open-source LAN sync apps for downloading selected Android, iPhone, and cloud files to a Windows desktop."
)

$ErrorActionPreference = "Stop"

$GhCommand = Get-Command gh -ErrorAction SilentlyContinue
$Gh = $null
if ($GhCommand) {
    $Gh = $GhCommand.Source
}
if (-not $Gh -and (Test-Path "C:\Program Files\GitHub CLI\gh.exe")) {
    $Gh = "C:\Program Files\GitHub CLI\gh.exe"
}
if (-not $Gh) {
    throw "GitHub CLI was not found. Install it from https://cli.github.com/."
}

$GitCommand = Get-Command git -ErrorAction SilentlyContinue
$Git = $null
if ($GitCommand) {
    $Git = $GitCommand.Source
}
if (-not $Git) {
    throw "Git was not found. Install Git for Windows from https://git-scm.com/download/win, then rerun this script."
}

& $Gh auth status | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw "GitHub CLI is not logged in. Run: gh auth login"
}

if (-not (Test-Path ".git")) {
    & $Git init
}

& $Git config --global --add safe.directory (Get-Location).Path

$GitName = (& $Git config user.name)
if (-not $GitName) {
    & $Git config user.name "Neo Apps"
}
$GitEmail = (& $Git config user.email)
if (-not $GitEmail) {
    $GhUserJson = & $Gh api user
    $GhUser = $GhUserJson | ConvertFrom-Json
    $Login = if ($GhUser.login) { $GhUser.login } else { "neo-apps" }
    $Id = if ($GhUser.id) { $GhUser.id } else { "0" }
    & $Git config user.email "$Id+$Login@users.noreply.github.com"
}

& $Git add README.md LICENSE .gitignore GITHUB_PUBLISH.md publish-github.ps1 assets android-companion windows-desktop ios-companion
& $Git commit -m "Open source Sync My Mobile" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "No new source changes to commit, continuing..."
}

$FullName = if ($Owner) { "$Owner/$Repo" } else { $Repo }
& $Gh repo view $FullName *> $null
if ($LASTEXITCODE -ne 0) {
    if ($Owner) {
        & $Gh repo create $FullName --public --description $Description --source . --remote origin --push
    } else {
        & $Gh repo create $Repo --public --description $Description --source . --remote origin --push
    }
} else {
    & $Git remote remove origin 2>$null
    & $Git remote add origin "https://github.com/$FullName.git"
    & $Git branch -M main
    & $Git push -u origin main
}

$Desktop = "dist\Sync My Mobile Desktop.exe"
$Android = "dist\Sync My Mobile Android.apk"
if ((Test-Path $Desktop) -and (Test-Path $Android)) {
    & $Gh release view v1.0.0 --repo $FullName *> $null
    if ($LASTEXITCODE -eq 0) {
        & $Gh release upload v1.0.0 $Desktop $Android --repo $FullName --clobber
    } else {
        & $Gh release create v1.0.0 $Desktop $Android --repo $FullName --title "Sync My Mobile v1.0.0" --notes "Initial open-source release by Neo Apps."
    }
}

Write-Host "Published: https://github.com/$FullName"
