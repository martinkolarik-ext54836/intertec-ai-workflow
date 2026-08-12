[CmdletBinding()]
param(
    [string]$Repository = (Get-Location).Path,
    [string]$ConfigPath = "$env:LOCALAPPDATA\SharedAIReviewer\config.json",
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

& (Join-Path $PSScriptRoot "review-worker-windows.ps1") -ConfigPath $ConfigPath -Repository $Repository -Force:$Force
exit $LASTEXITCODE
