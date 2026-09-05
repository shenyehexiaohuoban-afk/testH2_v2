param([string]$RunId = 'run-20260901-020054')
$ErrorActionPreference = 'Stop'
$packageRoot = (Resolve-Path $PSScriptRoot).Path
$statusRoot = Join-Path $packageRoot 'status'
$runDir = Join-Path $packageRoot (Join-Path 'training\runs' $RunId)
$caseDir = Join-Path $runDir 'training'
$checkpoint = Join-Path $caseDir 'checkpoint\checkpoint_final.mat'

function Get-Sha256([string]$path) {
    $stream = [System.IO.File]::OpenRead($path)
    try {
        $hasher = [System.Security.Cryptography.SHA256]::Create()
        try { return ([System.BitConverter]::ToString($hasher.ComputeHash($stream))).Replace('-','').ToLowerInvariant() }
        finally { $hasher.Dispose() }
    } finally { $stream.Dispose() }
}
function Write-Status([string]$text) {
    Set-Content -LiteralPath (Join-Path $statusRoot 'CURRENT_STATUS.txt') -Value $text -Encoding UTF8
}

if (-not (Test-Path -LiteralPath $checkpoint -PathType Leaf)) { throw "Existing final checkpoint is missing: $checkpoint" }
$finished = Join-Path $caseDir 'acceptance\TRAINING_FINISHED.txt'
$summaryPath = Join-Path $caseDir 'acceptance\training_summary.csv'
if (-not (Test-Path -LiteralPath $finished -PathType Leaf) -or -not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) { throw '5h training completion evidence is missing.' }
$summary = Import-Csv -LiteralPath $summaryPath
if ($summary.Count -ne 1 -or [double]$summary[0].budget_s -ne 18000 -or [double]$summary[0].actual_training_wall_time_s -lt 18000 -or [int]$summary[0].error_count -ne 0 -or [int]$summary[0].full_cut_audit_pass -ne 1) {
    throw 'Existing checkpoint does not satisfy the formal 5h training completion gate.'
}
$sha = Get-Sha256 $checkpoint
$matlab = 'D:\Program Files\MATLAB\R2022a\bin\matlab.exe'
$programRoot = Join-Path $packageRoot 'program'
$trainingRoot = Join-Path $packageRoot 'training'
$env:CANDIDATE_PROGRAM_ROOT = $programRoot
$env:CANDIDATE_STATUS_ROOT = $statusRoot
$env:STAGE89Q_PMAX_LONG_RUN_DIR = $runDir
$env:STAGE89Q_PMAX_LONG_PHASE = 'RELOAD'
$env:STAGE89Q_PMAX_LONG_ARM = 'TEMPORAL3P5'
$env:STAGE89Q_PMAX_LONG_VECTOR = '300,200,120,150'
$env:STAGE89Q_PMAX_LONG_FROZEN_COMMIT = 'TEMPORAL3P5_DRO_BASEMSP5H_CANDIDATE'
$env:STAGE89Q_PMAX_LONG_BUDGET_S = '18000'
$env:STAGE89Q_PMAX_LONG_CHECKPOINT_SHA256 = $sha
$trainingForMatlab = $trainingRoot.Replace("'", "''")
$programForMatlab = $programRoot.Replace("'", "''")
$expr = "addpath('$trainingForMatlab'); addpath('$programForMatlab'); run_candidate_formal_h2"
$started = Get-Date
Write-Status "CANDIDATE = TEMPORAL3P5`nRUN_ID = $RunId`nSTATUS = RUNNING`nPHASE = CLEAN_RELOAD_RECOVERY`nLATEST_VALID_CHECKPOINT = $checkpoint`nCHECKPOINT_SHA256 = $sha`nLAST_UPDATE = $($started.ToString('o'))"
try {
    Push-Location $programRoot
    & $matlab -nojvm -nodesktop -nosplash -batch $expr 2>&1 | Tee-Object -FilePath (Join-Path $runDir 'logs\reload_console.log')
    $exitCode = $LASTEXITCODE
    Pop-Location
    if ($exitCode -ne 0) { throw "Clean reload recovery failed with exit code $exitCode." }
    $ended = Get-Date
    Set-Content -LiteralPath (Join-Path $caseDir 'acceptance\CHECKPOINT_FROZEN.txt') -Value "CHECKPOINT=$checkpoint`nSHA256=$sha`nTERMINALLOH_SHA256=70e02fe1b46d09b4cf77fcf1fbfa1f1c4ab98c8200c52b51d6bdd7ac2205dae5`nMODE=FORMAL`nSTART=$started`nEND=$($ended.ToString('o'))`nRECOVERY=POST_TRAIN_HASH_FINALIZATION_ONLY" -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $statusRoot 'TRAINING_COMPLETED.txt') -Value "TRAINING_STATUS = COMPLETED`nMODE = FORMAL`nRUN_ID = $RunId`nCHECKPOINT = $checkpoint`nSHA256 = $sha`nCLEAN_RELOAD = PASS`nCOMPLETED_AT = $($ended.ToString('o'))`nRECOVERY = POST_TRAIN_HASH_FINALIZATION_ONLY" -Encoding UTF8
    Write-Status "CANDIDATE = TEMPORAL3P5`nRUN_ID = $RunId`nSTATUS = COMPLETED`nPHASE = CLEAN_RELOAD_PASS`nLATEST_VALID_CHECKPOINT = $checkpoint`nCHECKPOINT_SHA256 = $sha`nLAST_UPDATE = $($ended.ToString('o'))"
    Remove-Item -LiteralPath (Join-Path $statusRoot 'CHAIN_WATCHER_FAILED.txt') -Force -ErrorAction SilentlyContinue
    Write-Output "CHECKPOINT=$checkpoint"
    Write-Output "CHECKPOINT_SHA256=$sha"
} catch {
    if ((Get-Location).Path -eq $programRoot) { Pop-Location -ErrorAction SilentlyContinue }
    Write-Status "CANDIDATE = TEMPORAL3P5`nRUN_ID = $RunId`nSTATUS = FAILED`nPHASE = CLEAN_RELOAD_RECOVERY`nMESSAGE = $($_.Exception.Message)`nLAST_UPDATE = $((Get-Date).ToString('o'))"
    throw
} finally {
    Remove-Item Env:CANDIDATE_PROGRAM_ROOT,Env:CANDIDATE_STATUS_ROOT,Env:STAGE89Q_PMAX_LONG_RUN_DIR,Env:STAGE89Q_PMAX_LONG_PHASE,Env:STAGE89Q_PMAX_LONG_ARM,Env:STAGE89Q_PMAX_LONG_VECTOR,Env:STAGE89Q_PMAX_LONG_FROZEN_COMMIT,Env:STAGE89Q_PMAX_LONG_BUDGET_S,Env:STAGE89Q_PMAX_LONG_CHECKPOINT_SHA256 -ErrorAction SilentlyContinue
}
