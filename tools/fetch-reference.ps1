<#
Downloads (or updates) the community WoW Forever API references into .\reference\,
which git ignores. Both are MIT licensed.

Usage:  .\tools\fetch-reference.ps1
#>
$ErrorActionPreference = "Stop"
$root = Join-Path (Split-Path $PSScriptRoot -Parent) "reference"
New-Item -ItemType Directory -Force -Path $root | Out-Null

$repos = @{
    "forever-addon-dev" = "https://github.com/imperial64/forever-addon-dev.git"
    "forever-addon-kit" = "https://github.com/Thunderz96/forever-addon-kit.git"
}
foreach ($name in $repos.Keys) {
    $dir = Join-Path $root $name
    if (Test-Path (Join-Path $dir ".git")) {
        git -C $dir pull --ff-only --quiet
        Write-Host "Updated $name"
    } else {
        git clone --depth 1 --quiet $repos[$name] $dir
        Write-Host "Downloaded $name"
    }
}
