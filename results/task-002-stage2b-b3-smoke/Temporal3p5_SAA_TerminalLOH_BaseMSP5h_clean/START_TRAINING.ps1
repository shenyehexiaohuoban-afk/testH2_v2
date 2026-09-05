param([ValidateSet('FORMAL','SMOKE')][string]$Mode='FORMAL')
$ErrorActionPreference = 'Stop'
$packageRoot = (Resolve-Path $PSScriptRoot).Path
$statusRoot = Join-Path $packageRoot 'status'
$runsRoot = Join-Path $packageRoot 'training\runs'

function Read-Config([string]$path) {
    $cfg = @{}
    foreach ($line in Get-Content -LiteralPath $path) {
        if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
        $parts = $line -split '=', 2
        $cfg[$parts[0].Trim()] = $parts[1].Trim()
    }
    return $cfg
}
function Write-Status([string]$text) {
    Set-Content -LiteralPath (Join-Path $statusRoot 'CURRENT_STATUS.txt') -Value $text -Encoding UTF8
}
function Get-Sha256([string]$path) {
    $stream = [System.IO.File]::OpenRead($path)
    try {
        $hasher = [System.Security.Cryptography.SHA256]::Create()
        try { return ([System.BitConverter]::ToString($hasher.ComputeHash($stream))).Replace('-','').ToLowerInvariant() }
        finally { $hasher.Dispose() }
    } finally { $stream.Dispose() }
}

$cfg = Read-Config (Join-Path $packageRoot 'RUN_CONFIG.txt')
if ($cfg.CANDIDATE_ID -ne 'TEMPORAL3P5_SAA_BASEMSP5H_CANDIDATE') { throw 'Candidate identity mismatch.' }
if ($cfg.PMAX_KW -ne '300,200,120,150') { throw 'Formal Base Pmax identity mismatch.' }
if ([double]$cfg.TRAIN_HOURS -ne 5.0 -or [int]$cfg.TRAINING_DURATION_SECONDS -ne 18000) { throw 'Formal fixed 5h budget mismatch.' }
if ($cfg.START_MODE -ne 'FRESH' -or $cfg.RUN_TRAINING -ne '1') { throw 'Training must remain enabled and FRESH.' }
if ($cfg.RUN_TESTING -ne '0') { throw 'Formal OOS must remain disabled during training.' }
$matlab = $cfg.MATLAB_EXE
if (-not (Test-Path -LiteralPath $matlab -PathType Leaf)) { throw "MATLAB_EXE does not exist: $matlab" }
$programRoot = (Resolve-Path (Join-Path $packageRoot $cfg.PROGRAM_ROOT)).Path
$trainingEntryRoot = Join-Path $packageRoot 'training'
New-Item -ItemType Directory -Force -Path $statusRoot,$runsRoot | Out-Null

$lockPath = Join-Path $statusRoot 'TRAINING.lock'
if (Test-Path -LiteralPath $lockPath) {
    $oldText = Get-Content -LiteralPath $lockPath -Raw
    $oldPid = 0
    if ($oldText -match 'PID=(\d+)') { $oldPid = [int]$Matches[1] }
    if (Get-Process -Id $oldPid -ErrorAction SilentlyContinue) { throw "Training is already active (PID=$oldPid)." }
    Move-Item -LiteralPath $lockPath -Destination (Join-Path $statusRoot ("STALE_LOCK_{0}.txt" -f (Get-Date -Format 'yyyyMMdd_HHmmss')))
}

$budget = if ($Mode -eq 'FORMAL') { 18000 } else { 1 }
$prefix = if ($Mode -eq 'FORMAL') { 'run' } else { 'smoke' }
$runId = $prefix + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
$runDir = Join-Path $runsRoot $runId
$caseDir = Join-Path $runDir 'training'
foreach ($dir in @($runDir,$caseDir,(Join-Path $caseDir 'checkpoint'),(Join-Path $caseDir 'iteration_trace'),(Join-Path $caseDir 'stage_site'),(Join-Path $caseDir 'grid'),(Join-Path $caseDir 'monitor'),(Join-Path $caseDir 'qa'),(Join-Path $caseDir 'config'),(Join-Path $caseDir 'acceptance'),(Join-Path $runDir 'logs'))) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

$started = Get-Date
Set-Content -LiteralPath $lockPath -Value "CANDIDATE=TEMPORAL3P5`nPID=$PID`nRUN_ID=$runId`nSTART_TIME=$($started.ToString('o'))" -Encoding UTF8
foreach ($staleMarker in @('TRAINING_COMPLETED.txt','OOS_COMPLETED.txt','ANALYSIS_COMPLETED.txt')) {
    Remove-Item -LiteralPath (Join-Path $statusRoot $staleMarker) -Force -ErrorAction SilentlyContinue
}
Write-Status "CANDIDATE = TEMPORAL3P5`nPMAX_KW = [300,200,120,150]`nRUN_ID = $runId`nSTATUS = RUNNING`nPHASE = TRAIN`nTARGET_TRAINING_SECONDS = $budget`nSTART_TIME = $($started.ToString('o'))"

$env:CANDIDATE_PROGRAM_ROOT = $programRoot
$env:CANDIDATE_STATUS_ROOT = $statusRoot
$env:STAGE89Q_PMAX_LONG_RUN_DIR = $runDir
$env:STAGE89Q_PMAX_LONG_PHASE = 'TRAIN'
$env:STAGE89Q_PMAX_LONG_ARM = 'TEMPORAL3P5'
$env:STAGE89Q_PMAX_LONG_VECTOR = '300,200,120,150'
$env:STAGE89Q_PMAX_LONG_FROZEN_COMMIT = 'TEMPORAL3P5_SAA_BASEMSP5H_CANDIDATE'
$env:STAGE89Q_PMAX_LONG_BUDGET_S = [string]$budget
$entryRoot = $trainingEntryRoot.Replace("'", "''")
$programForMatlab = $programRoot.Replace("'", "''")
$expr = "addpath('$entryRoot'); addpath('$programForMatlab'); run_candidate_formal_h2"

try {
    Push-Location $programRoot
    & $matlab -nojvm -nodesktop -nosplash -batch $expr 2>&1 | Tee-Object -FilePath (Join-Path $runDir 'logs\training_console.log')
    $trainExit = $LASTEXITCODE
    Pop-Location
    if ($trainExit -ne 0) { throw "MATLAB training failed with exit code $trainExit." }
    $checkpoint = Join-Path $caseDir 'checkpoint\checkpoint_final.mat'
    if (-not (Test-Path -LiteralPath $checkpoint -PathType Leaf)) { throw "Missing final checkpoint: $checkpoint" }
    $sha = Get-Sha256 $checkpoint
    $env:STAGE89Q_PMAX_LONG_PHASE = 'RELOAD'
    $env:STAGE89Q_PMAX_LONG_CHECKPOINT_SHA256 = $sha
    Push-Location $programRoot
    & $matlab -nojvm -nodesktop -nosplash -batch $expr 2>&1 | Tee-Object -FilePath (Join-Path $runDir 'logs\reload_console.log')
    $reloadExit = $LASTEXITCODE
    Pop-Location
    if ($reloadExit -ne 0) { throw "Clean reload failed with exit code $reloadExit." }
    $ended = Get-Date
    Set-Content -LiteralPath (Join-Path $caseDir 'acceptance\CHECKPOINT_FROZEN.txt') -Value "CHECKPOINT=$checkpoint`nSHA256=$sha`nTERMINALLOH_SHA256=b74433fe8a19caedb75ac3071225480e279c136f3d1285ba503a184f12c5fcdc`nMODE=$Mode`nSTART=$($started.ToString('o'))`nEND=$($ended.ToString('o'))" -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $statusRoot 'TRAINING_COMPLETED.txt') -Value "TRAINING_STATUS = COMPLETED`nMODE = $Mode`nRUN_ID = $runId`nCHECKPOINT = $checkpoint`nSHA256 = $sha`nCLEAN_RELOAD = PASS`nCOMPLETED_AT = $($ended.ToString('o'))" -Encoding UTF8
    Write-Status "CANDIDATE = TEMPORAL3P5`nRUN_ID = $runId`nSTATUS = COMPLETED`nPHASE = CLEAN_RELOAD_PASS`nLATEST_VALID_CHECKPOINT = $checkpoint`nCHECKPOINT_SHA256 = $sha`nLAST_UPDATE = $($ended.ToString('o'))"
    Write-Output "RUN_DIR=$runDir"
    Write-Output "CHECKPOINT=$checkpoint"
    Write-Output "CHECKPOINT_SHA256=$sha"
} catch {
    if ((Get-Location).Path -eq $programRoot) { Pop-Location -ErrorAction SilentlyContinue }
    Set-Content -LiteralPath (Join-Path $runDir 'FAILURE.txt') -Value $_.Exception.ToString() -Encoding UTF8
    Write-Status "CANDIDATE = TEMPORAL3P5`nRUN_ID = $runId`nSTATUS = FAILED`nMESSAGE = $($_.Exception.Message)`nLAST_UPDATE = $((Get-Date).ToString('o'))"
    throw
} finally {
    Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
    Remove-Item Env:CANDIDATE_PROGRAM_ROOT,Env:CANDIDATE_STATUS_ROOT,Env:STAGE89Q_PMAX_LONG_RUN_DIR,Env:STAGE89Q_PMAX_LONG_PHASE,Env:STAGE89Q_PMAX_LONG_ARM,Env:STAGE89Q_PMAX_LONG_VECTOR,Env:STAGE89Q_PMAX_LONG_FROZEN_COMMIT,Env:STAGE89Q_PMAX_LONG_BUDGET_S,Env:STAGE89Q_PMAX_LONG_CHECKPOINT_SHA256 -ErrorAction SilentlyContinue
}
