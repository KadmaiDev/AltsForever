<#
Works around the WoW Forever beta bug where the client writes SavedVariables on
logout but never loads them back at startup.

Creates a folder link "SavedData" in the addon folder pointing at your account's
SavedVariables folder. The .toc lists SavedData\AltsForever.lua, so the game runs
the saved file as ordinary addon code and the data comes back.

Usage:  .\tools\link-saved-data.ps1 -WowDir "C:\Program Files (x86)\World of Warcraft\_classic_beta_"
        (add -Account "123456#1" if you have more than one account folder)
#>
param(
    [Parameter(Mandatory)] [string] $WowDir,
    [string] $Account
)
$ErrorActionPreference = "Stop"

$accountsDir = Join-Path $WowDir "WTF\Account"
$accounts = Get-ChildItem -LiteralPath $accountsDir -Directory | Where-Object { $_.Name -ne "SavedVariables" }
if ($Account) { $accounts = $accounts | Where-Object Name -eq $Account }
if (@($accounts).Count -ne 1) {
    throw "Found $(@($accounts).Count) account folders in $accountsDir. Pass -Account with one of: $((Get-ChildItem -LiteralPath $accountsDir -Directory).Name -join ', ')"
}

$target = Join-Path $accounts[0].FullName "SavedVariables"
$link = Join-Path (Split-Path $PSScriptRoot -Parent) "SavedData"

if (Test-Path -LiteralPath $link) {
    $existing = Get-Item -LiteralPath $link
    if ($existing.LinkType -ne "Junction") { throw "$link exists and is not a link; not touching it." }
    Remove-Item -LiteralPath $link -Force
}
New-Item -ItemType Junction -Path $link -Target $target | Out-Null
Write-Host "Linked $link -> $target"
Write-Host "Restart the game client fully (not just /reload) for the .toc change to take effect."
