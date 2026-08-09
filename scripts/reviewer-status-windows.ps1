[CmdletBinding()]
param(
    [string]$TaskName = "Shared AI External Reviewer",
    [string]$ConfigPath = "$env:LOCALAPPDATA\SharedAIReviewer\config.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if (-not $task) {
    Write-Host "Task: $TaskName"
    Write-Host "Status: not installed"
    exit 1
}

$info = Get-ScheduledTaskInfo -TaskName $TaskName
Write-Host "Task: $TaskName"
Write-Host "Status: $($task.State)"
Write-Host "Last run: $($info.LastRunTime)"
Write-Host "Last result: $($info.LastTaskResult)"
Write-Host "Next run: $($info.NextRunTime)"

if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) {
    $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    Write-Host "Model: $($config.Model)"
    Write-Host "Reasoning: $($config.Reasoning)"
    Write-Host "Projects: $($config.ProjectsRoot)"
    Write-Host "Runtime: $($config.RuntimeRoot)"
    Write-Host "Logs: $($config.LogRoot)"
    Write-Host ""
    Write-Host "Give-up entries:"
    $failureDirectory = Join-Path ([string]$config.RuntimeRoot) "failures"
    $giveupEntries = @(Get-ChildItem -LiteralPath $failureDirectory -Filter "*.giveup" -File -ErrorAction SilentlyContinue)
    if ($giveupEntries.Count -gt 0) {
        foreach ($entry in $giveupEntries | Sort-Object Name) {
            Write-Host $entry.Name
            Get-Content -LiteralPath $entry.FullName | ForEach-Object { Write-Host "  $_" }
        }
    } else {
        Write-Host "none"
    }
}

$schedulerLog = Join-Path (Split-Path -Parent $ConfigPath) "task-scheduler.log"
Write-Host ""
Write-Host "Recent activity:"
if (Test-Path -LiteralPath $schedulerLog -PathType Leaf) {
    Get-Content -LiteralPath $schedulerLog -Tail 20
} else {
    Write-Host "none"
}
