[CmdletBinding()]
param(
    [string]$ProjectsRoot,
    [string]$Model = "gpt-5.6-terra",
    [ValidateSet("low", "medium", "high", "xhigh", "max", "ultra")]
    [string]$Reasoning = "high",
    [string]$TaskName = "Shared AI External Reviewer",
    [string]$BashPath = $env:BASH_EXE,
    [string]$CodexBin = $env:CODEX_BIN
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw "This installer is for Windows. Use install-reviewer.sh on macOS."
}

$aiRoot = Split-Path -Parent $PSScriptRoot
if (-not $ProjectsRoot) {
    $ProjectsRoot = Split-Path -Parent $aiRoot
}
$ProjectsRoot = (Resolve-Path -LiteralPath $ProjectsRoot).Path

function Find-GitBash {
    if ($BashPath) {
        return (Resolve-Path -LiteralPath $BashPath).Path
    }

    $candidates = @()
    if ($env:ProgramFiles) {
        $candidates += (Join-Path $env:ProgramFiles "Git\bin\bash.exe")
    }
    if (${env:ProgramFiles(x86)}) {
        $candidates += (Join-Path ${env:ProgramFiles(x86)} "Git\bin\bash.exe")
    }
    if ($env:LOCALAPPDATA) {
        $candidates += (Join-Path $env:LOCALAPPDATA "Programs\Git\bin\bash.exe")
    }
    $git = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($git) {
        $gitRoot = Split-Path -Parent (Split-Path -Parent $git.Source)
        $candidates += (Join-Path $gitRoot "bin\bash.exe")
    }

    foreach ($candidate in $candidates | Select-Object -Unique) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    throw "Git for Windows Bash was not found. Install Git for Windows or set BASH_EXE."
}

$BashPath = Find-GitBash

function ConvertTo-GitBashPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $converted = & $BashPath -c 'cygpath -u "$1"' -- $Path
    if ($LASTEXITCODE -ne 0 -or -not $converted) {
        throw "Could not convert Windows path for Git Bash: $Path"
    }
    return ([string]$converted).Trim()
}

$dataRoot = Join-Path $env:LOCALAPPDATA "SharedAIReviewer"
$runtimeRoot = Join-Path $dataRoot "Runtime"
$logRoot = Join-Path $dataRoot "Logs"
New-Item -ItemType Directory -Force -Path $dataRoot, $runtimeRoot, $logRoot | Out-Null

$codexBashPath = ""
if ($CodexBin) {
    $resolvedCodex = (Resolve-Path -LiteralPath $CodexBin).Path
    $codexBashPath = ConvertTo-GitBashPath $resolvedCodex
}

$configPath = Join-Path $dataRoot "config.json"
$config = [ordered]@{
    BashPath = $BashPath
    WorkerPath = ConvertTo-GitBashPath (Join-Path $PSScriptRoot "review-worker.sh")
    ReviewOnePath = ConvertTo-GitBashPath (Join-Path $PSScriptRoot "review-one.sh")
    ProjectsRoot = ConvertTo-GitBashPath $ProjectsRoot
    RuntimeRoot = ConvertTo-GitBashPath $runtimeRoot
    LogRoot = ConvertTo-GitBashPath $logRoot
    Model = $Model
    Reasoning = $Reasoning
    CodexBin = $codexBashPath
}
$config | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding UTF8

$runner = Join-Path $PSScriptRoot "review-worker-windows.ps1"
$powerShellExe = Join-Path $PSHOME "powershell.exe"
$actionArguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$runner`" -ConfigPath `"$configPath`""
$action = New-ScheduledTaskAction -Execute $powerShellExe -Argument $actionArguments
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 1)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
$principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "Runs the shared AI external-review worker once per minute." -Force | Out-Null
Start-ScheduledTask -TaskName $TaskName

Write-Host "Installed and started '$TaskName'."
Write-Host "Git Bash: $BashPath"
Write-Host "Projects: $ProjectsRoot"
Write-Host "Model: $Model"
Write-Host "Reasoning: $Reasoning"
Write-Host "Configuration: $configPath"
Write-Host "Status: .\scripts\reviewer-status-windows.ps1"
