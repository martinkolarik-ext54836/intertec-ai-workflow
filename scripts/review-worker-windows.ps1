[CmdletBinding()]
param(
    [string]$ConfigPath = "$env:LOCALAPPDATA\SharedAIReviewer\config.json",
    [string]$Repository,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "Reviewer configuration was not found: $ConfigPath"
}

$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
foreach ($required in @("BashPath", "WorkerPath", "ReviewOnePath", "ProjectsRoot", "RuntimeRoot", "LogRoot", "Model", "Reasoning")) {
    if (-not $config.$required) {
        throw "Reviewer configuration is missing '$required': $ConfigPath"
    }
}

$env:PROJECTS_ROOT = [string]$config.ProjectsRoot
$env:REVIEW_RUNTIME_ROOT = [string]$config.RuntimeRoot
$env:REVIEW_LOG_ROOT = [string]$config.LogRoot
$env:REVIEW_MODEL = [string]$config.Model
$env:REVIEW_REASONING = [string]$config.Reasoning
if ($config.PSObject.Properties.Name -contains "CodexBin" -and $config.CodexBin) {
    $env:CODEX_BIN = [string]$config.CodexBin
}

$logDirectory = Split-Path -Parent $ConfigPath
$schedulerLog = Join-Path $logDirectory "task-scheduler.log"

function ConvertTo-GitBashPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $converted = & ([string]$config.BashPath) -c 'cygpath -u "$1"' -- $Path
    if ($LASTEXITCODE -ne 0 -or -not $converted) {
        throw "Could not convert Windows path for Git Bash: $Path"
    }
    return ([string]$converted).Trim()
}

$scriptPath = [string]$config.WorkerPath
$arguments = @($scriptPath)
$env:REVIEW_TRIGGER = "worker"
$env:REVIEW_FORCE = "0"
if ($Repository) {
    $env:REVIEW_TRIGGER = "manual"
    if ($Force) {
        $env:REVIEW_FORCE = "1"
    }
    $scriptPath = [string]$config.ReviewOnePath
    $arguments = @($scriptPath, (ConvertTo-GitBashPath -Path $Repository))
}

$startedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Add-Content -LiteralPath $schedulerLog -Value "$startedAt START script=$scriptPath"
$output = & ([string]$config.BashPath) @arguments 2>&1
$exitCode = $LASTEXITCODE
if ($output) {
    $output | ForEach-Object { Add-Content -LiteralPath $schedulerLog -Value ([string]$_) }
}
$finishedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Add-Content -LiteralPath $schedulerLog -Value "$finishedAt DONE exit=$exitCode"
exit $exitCode
