[CmdletBinding()]
param(
    [string]$TaskName = "Shared AI External Reviewer"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($task) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Uninstalled '$TaskName'."
} else {
    Write-Host "Task '$TaskName' is not installed."
}
Write-Host "Configuration, logs, and completed-review markers were preserved in $env:LOCALAPPDATA\SharedAIReviewer."
