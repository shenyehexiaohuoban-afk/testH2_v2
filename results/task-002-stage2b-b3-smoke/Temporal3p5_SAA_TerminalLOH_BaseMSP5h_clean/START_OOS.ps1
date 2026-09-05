$ErrorActionPreference = 'Stop'
function Get-Sha256([string]$path) {
    $stream = [System.IO.File]::OpenRead($path)
    try {
        $hasher = [System.Security.Cryptography.SHA256]::Create()
        try { return ([System.BitConverter]::ToString($hasher.ComputeHash($stream))).Replace('-','').ToLowerInvariant() }
        finally { $hasher.Dispose() }
    } finally { $stream.Dispose() }
}
$packageRoot = (Resolve-Path $PSScriptRoot).Path
$projectRoot = (Resolve-Path (Join-Path $packageRoot '..\..\..')).Path
$statusRoot = Join-Path $packageRoot 'status'
$trainingComplete = Join-Path $statusRoot 'TRAINING_COMPLETED.txt'
if (-not (Test-Path -LiteralPath $trainingComplete)) { throw 'Formal training completion gate is missing.' }
$trainingText = Get-Content -LiteralPath $trainingComplete -Raw
foreach ($required in @('TRAINING_STATUS = COMPLETED','MODE = FORMAL','CLEAN_RELOAD = PASS')) {
    if ($trainingText -notmatch [regex]::Escape($required)) { throw "Formal training gate failed: $required" }
}
$currentStatusPath = Join-Path $statusRoot 'CURRENT_STATUS.txt'
if (-not (Test-Path -LiteralPath $currentStatusPath -PathType Leaf)) { throw 'Current training status gate is missing.' }
$currentStatusText = Get-Content -LiteralPath $currentStatusPath -Raw
foreach ($required in @('STATUS = COMPLETED','PHASE = CLEAN_RELOAD_PASS')) {
    if ($currentStatusText -notmatch [regex]::Escape($required)) { throw "Current training status gate failed: $required" }
}
$completedRunId = ([regex]::Match($trainingText,'(?m)^RUN_ID = (.+)$')).Groups[1].Value.Trim()
$currentRunId = ([regex]::Match($currentStatusText,'(?m)^RUN_ID = (.+)$')).Groups[1].Value.Trim()
if ([string]::IsNullOrWhiteSpace($completedRunId) -or $completedRunId -ne $currentRunId) { throw 'Training completion/current-status run ID mismatch.' }
$checkpoint = ([regex]::Match($trainingText,'(?m)^CHECKPOINT = (.+)$')).Groups[1].Value.Trim()
$sha = ([regex]::Match($trainingText,'(?m)^SHA256 = ([0-9a-fA-F]{64})$')).Groups[1].Value.ToLowerInvariant()
if (-not (Test-Path -LiteralPath $checkpoint -PathType Leaf)) { throw "Frozen checkpoint is missing: $checkpoint" }
if ((Get-Sha256 $checkpoint) -ne $sha) { throw 'Frozen checkpoint SHA mismatch.' }

$runDir = Split-Path (Split-Path (Split-Path $checkpoint -Parent) -Parent) -Parent
if ((Split-Path $runDir -Leaf) -ne $completedRunId) { throw 'Frozen checkpoint run directory does not match completed RUN_ID.' }
$caseDir = Join-Path $runDir 'training'
$frozen = Join-Path $caseDir 'acceptance\CHECKPOINT_FROZEN.txt'
if (-not (Test-Path -LiteralPath $frozen)) { throw 'Checkpoint freeze manifest is missing.' }
$freezeText = Get-Content -LiteralPath $frozen -Raw
if ($freezeText -notmatch 'MODE=FORMAL' -or $freezeText -notmatch 'TERMINALLOH_SHA256=b74433fe8a19caedb75ac3071225480e279c136f3d1285ba503a184f12c5fcdc') { throw 'Checkpoint freeze identity gate failed.' }

$oosRoot = Join-Path $runDir 'oos_modeC'
$bankDir = Join-Path $runDir '01_preflight\common_bank'
foreach ($dir in @($oosRoot,(Join-Path $oosRoot 'path_summary'),(Join-Path $oosRoot 'hourly_site'),(Join-Path $oosRoot 'grid_hourly'),(Join-Path $oosRoot 'htt_od'),(Join-Path $oosRoot 'qa'),$bankDir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

$matlab = 'D:\Program Files\MATLAB\R2022a\bin\matlab.exe'
$programRoot = Join-Path $packageRoot 'program'
$testingRoot = Join-Path $packageRoot 'testing'
$env:CANDIDATE_PROGRAM_ROOT = $programRoot
$env:CANDIDATE_STATUS_ROOT = $statusRoot
$env:STAGE89Q_PROJECT_ROOT = $projectRoot
$env:STAGE89Q_PMAX_LONG_RUN_DIR = $runDir
$env:STAGE89Q_PMAX_LONG_ARM = 'TEMPORAL3P5'
$env:STAGE89Q_PMAX_LONG_VECTOR = '300,200,120,150'
$env:STAGE89Q_PMAX_LONG_FROZEN_COMMIT = 'TEMPORAL3P5_SAA_BASEMSP5H_CANDIDATE'
$env:STAGE89Q_PMAX_LONG_CHECKPOINT_SHA256 = $sha
$env:STAGE89Q_EXTERNAL_CHECKPOINT = $checkpoint
$env:STAGE89Q_OOS_PATH_COUNT = '10000'
$testingForMatlab = $testingRoot.Replace("'", "''")
$programForMatlab = $programRoot.Replace("'", "''")
$expr = "addpath('$testingForMatlab'); addpath('$programForMatlab'); run_temporal3p5_oos_mode_c"
$lockPath = Join-Path $statusRoot 'OOS.lock'
if (Test-Path -LiteralPath $lockPath) {
    $lockText = Get-Content -LiteralPath $lockPath -Raw -ErrorAction SilentlyContinue
    $lockPid = 0
    if ($lockText -match 'PID=(\d+)') { $lockPid = [int]$Matches[1] }
    if ($lockPid -gt 0 -and (Get-Process -Id $lockPid -ErrorAction SilentlyContinue)) { throw "Mode C OOS is already active (PID=$lockPid)." }
    Move-Item -LiteralPath $lockPath -Destination (Join-Path $statusRoot ("STALE_OOS_LOCK_{0}.txt" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))) -Force
}
try {
    $lockStream = [System.IO.File]::Open($lockPath,[System.IO.FileMode]::CreateNew,[System.IO.FileAccess]::ReadWrite,[System.IO.FileShare]::None)
    $lockBytes = [System.Text.Encoding]::UTF8.GetBytes("PID=$PID`nRUN_DIR=$runDir`nSTARTED_AT=$((Get-Date).ToString('o'))`n")
    $lockStream.Write($lockBytes,0,$lockBytes.Length); $lockStream.Flush()
} catch {
    throw "Unable to acquire exclusive Mode C OOS lock: $($_.Exception.Message)"
}
try {
    $env:STAGE89Q_PMAX_LONG_PHASE = 'BANK'
    Push-Location $programRoot
    & $matlab -nojvm -nodesktop -nosplash -batch $expr 2>&1 | Tee-Object -FilePath (Join-Path $runDir 'logs\oos_bank_console.log')
    $bankExit = $LASTEXITCODE
    Pop-Location
    if ($bankExit -ne 0) { throw "Mode C bank gate failed with exit code $bankExit." }
    $env:STAGE89Q_PMAX_LONG_PHASE = 'OOS'
    Push-Location $programRoot
    & $matlab -nojvm -nodesktop -nosplash -batch $expr 2>&1 | Tee-Object -FilePath (Join-Path $runDir 'logs\oos_console.log')
    $oosExit = $LASTEXITCODE
    Pop-Location
    if ($oosExit -ne 0) { throw "Mode C OOS failed with exit code $oosExit." }
    Set-Content -LiteralPath (Join-Path $statusRoot 'OOS_COMPLETED.txt') -Value "OOS_STATUS = COMPLETED`nMODE = C`nRUN_DIR = $runDir`nCHECKPOINT = $checkpoint`nCHECKPOINT_SHA256 = $sha`nPATH_COUNT = 10000`nCOMPLETED_AT = $((Get-Date).ToString('o'))" -Encoding UTF8
    Write-Output "OOS_RUN_DIR=$oosRoot"
} finally {
    if ((Get-Location).Path -eq $programRoot) { Pop-Location -ErrorAction SilentlyContinue }
    Remove-Item Env:CANDIDATE_PROGRAM_ROOT,Env:CANDIDATE_STATUS_ROOT,Env:STAGE89Q_PROJECT_ROOT,Env:STAGE89Q_PMAX_LONG_RUN_DIR,Env:STAGE89Q_PMAX_LONG_ARM,Env:STAGE89Q_PMAX_LONG_VECTOR,Env:STAGE89Q_PMAX_LONG_FROZEN_COMMIT,Env:STAGE89Q_PMAX_LONG_CHECKPOINT_SHA256,Env:STAGE89Q_EXTERNAL_CHECKPOINT,Env:STAGE89Q_OOS_PATH_COUNT,Env:STAGE89Q_PMAX_LONG_PHASE -ErrorAction SilentlyContinue
    if ($lockStream) { $lockStream.Dispose() }
    Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
}
