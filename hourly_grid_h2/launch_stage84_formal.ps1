param(
    [Parameter(Mandatory=$true)][string]$FrozenCommit,
    [string]$RunId = 'run-001'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$matlab = 'D:\Program Files\MATLAB\R2022a\bin\matlab.exe'
$runDir = Join-Path $repo "results\task-002-stage2b-b3-smoke\84-hourly-grid-formal-training-oos\$RunId"
if (-not (Test-Path -LiteralPath $matlab)) { throw "MATLAB not found: $matlab" }
if (Test-Path -LiteralPath $runDir) { throw "Refusing to overwrite $runDir" }
$head = (git -C $repo rev-parse HEAD).Trim()
if ($head -ne $FrozenCommit) { throw "HEAD $head does not match frozen commit $FrozenCommit" }
if (Get-Process MATLAB -ErrorAction SilentlyContinue) { throw 'A MATLAB process is already running.' }

$oldRun = $env:STAGE84_RUN_ID
$oldCommit = $env:STAGE84_FROZEN_COMMIT
$env:STAGE84_RUN_ID = $RunId
$env:STAGE84_FROZEN_COMMIT = $FrozenCommit
try {
    $expr = "cd('$($repo.Replace('\','/'))'); addpath('hourly_grid_h2'); run_stage84_formal_training_oos_h2"
    $launchDir = Split-Path -Parent $runDir
    if (-not (Test-Path -LiteralPath $launchDir)) { New-Item -ItemType Directory -Path $launchDir | Out-Null }
    $attempt = 1
    do {
        $suffix = if ($attempt -eq 1) { '' } else { "-$('{0:D3}' -f $attempt)" }
        $recordFile = Join-Path $launchDir "$RunId-launch-record$suffix.txt"
        $matlabLog = Join-Path $launchDir "$RunId-matlab-launch$suffix.log"
        $attempt++
    } while ((Test-Path -LiteralPath $recordFile) -or (Test-Path -LiteralPath $matlabLog))
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $matlab
    $psi.WorkingDirectory = $repo
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $false
    $psi.RedirectStandardError = $false
    $psi.ArgumentList.Add('-logfile')
    $psi.ArgumentList.Add($matlabLog)
    $psi.ArgumentList.Add('-batch')
    $psi.ArgumentList.Add($expr)
    $p = [System.Diagnostics.Process]::new()
    $p.StartInfo = $psi
    if (-not $p.Start()) { throw 'Failed to start MATLAB.' }
} finally {
    $env:STAGE84_RUN_ID = $oldRun
    $env:STAGE84_FROZEN_COMMIT = $oldCommit
}
$record = @(
    "START_PROCESS_PID=$($p.Id)"
    "START_TIME=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    "RUN_DIR=$runDir"
    "FORMAL_FROZEN_COMMIT=$FrozenCommit"
    "RUN_ID=$RunId"
    "MATLAB_LOG=$matlabLog"
) -join "`r`n"
Set-Content -LiteralPath $recordFile -Value $record -Encoding UTF8
$record
