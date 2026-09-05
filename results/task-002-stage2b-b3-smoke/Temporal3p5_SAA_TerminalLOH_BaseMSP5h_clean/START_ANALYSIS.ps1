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
$oosComplete = Join-Path $statusRoot 'OOS_COMPLETED.txt'
if (-not (Test-Path -LiteralPath $oosComplete -PathType Leaf)) { throw 'Mode C OOS completion gate is missing.' }
$oosText = Get-Content -LiteralPath $oosComplete -Raw
foreach ($required in @('OOS_STATUS = COMPLETED','MODE = C','PATH_COUNT = 10000')) {
    if ($oosText -notmatch [regex]::Escape($required)) { throw "Mode C OOS gate failed: $required" }
}
$runDir = ([regex]::Match($oosText,'(?m)^RUN_DIR = (.+)$')).Groups[1].Value.Trim()
$candidateCheckpoint = ([regex]::Match($oosText,'(?m)^CHECKPOINT = (.+)$')).Groups[1].Value.Trim()
$candidateSha = ([regex]::Match($oosText,'(?m)^CHECKPOINT_SHA256 = ([0-9a-fA-F]{64})$')).Groups[1].Value.ToLowerInvariant()
if (-not (Test-Path -LiteralPath $candidateCheckpoint -PathType Leaf)) { throw 'Candidate checkpoint is missing.' }
if ((Get-Sha256 $candidateCheckpoint) -ne $candidateSha) { throw 'Candidate checkpoint SHA gate failed.' }

$candidateOos = Join-Path $runDir 'oos_modeC'
$candidateMetadata = Join-Path $candidateOos 'oos_metadata.csv'
$candidateMarker = Join-Path $candidateOos 'OOS_RAW_COMPLETED.marker'
if (-not (Test-Path -LiteralPath $candidateMetadata) -or -not (Test-Path -LiteralPath $candidateMarker)) { throw 'Candidate Mode C raw completion evidence is missing.' }
$candidateMeta = Import-Csv -LiteralPath $candidateMetadata
if ($candidateMeta.Count -ne 1 -or [int]$candidateMeta[0].completed_paths -ne 10000 -or [int]$candidateMeta[0].pass -ne 1) { throw 'Candidate OOS metadata gate failed.' }
if ($candidateMeta[0].checkpoint_sha256_before.ToLowerInvariant() -ne $candidateSha -or $candidateMeta[0].checkpoint_sha256_after.ToLowerInvariant() -ne $candidateSha) { throw 'Candidate OOS readonly checkpoint gate failed.' }

$baseOos = Join-Path $projectRoot 'hourly_grid_h2\output\stage89q_penalty1000_vs1500_long_training\run-003\penalty1000'
$baseCheckpoint = Join-Path $projectRoot 'hourly_grid_h2\output\stage89q_penalty1000_vs1500_long_training\run-002\penalty1000\checkpoint\checkpoint_final.mat'
$bank = Join-Path $projectRoot 'results\task-002-stage2b-b3-smoke\89H-stage85r-single-loc4-stage88-dro-gap1000-10iter-oos10000\run-003\oos\loc4\oos_path_bank.mat'
$trainingMetadata = Join-Path $statusRoot 'TRAINING_COMPLETED.txt'
foreach ($path in @($baseCheckpoint,$bank,$trainingMetadata,(Join-Path $baseOos 'oos_metadata.csv'))) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required analysis input is missing: $path" }
}
$expectedBankSha = '6bf3d1190a402ded052b8d3d08ed369042236e151f562bdd9fd4db7b8ff386c6'
if ((Get-Sha256 $bank) -ne $expectedBankSha) { throw 'Common ordered OOS bank SHA gate failed.' }

$lockPath = Join-Path $statusRoot 'ANALYSIS.lock'
if (Test-Path -LiteralPath $lockPath) {
    $lockText = Get-Content -LiteralPath $lockPath -Raw -ErrorAction SilentlyContinue
    $lockPid = 0
    if ($lockText -match 'PID=(\d+)') { $lockPid = [int]$Matches[1] }
    if ($lockPid -gt 0 -and (Get-Process -Id $lockPid -ErrorAction SilentlyContinue)) { throw "Mode C analysis is already active (PID=$lockPid)." }
    Move-Item -LiteralPath $lockPath -Destination (Join-Path $statusRoot ("STALE_ANALYSIS_LOCK_{0}.txt" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))) -Force
}
try {
    $lockStream = [System.IO.File]::Open($lockPath,[System.IO.FileMode]::CreateNew,[System.IO.FileAccess]::ReadWrite,[System.IO.FileShare]::None)
    $lockBytes = [System.Text.Encoding]::UTF8.GetBytes("PID=$PID`nRUN_DIR=$runDir`nSTARTED_AT=$((Get-Date).ToString('o'))`n")
    $lockStream.Write($lockBytes,0,$lockBytes.Length); $lockStream.Flush()
} catch {
    throw "Unable to acquire exclusive Mode C analysis lock: $($_.Exception.Message)"
}
try {
    $analysisRoot = Join-Path $runDir 'oos_analysis'
    $comparisonRoot = Join-Path $runDir 'comparisons'
    New-Item -ItemType Directory -Force -Path $analysisRoot,$comparisonRoot | Out-Null
    $script = Join-Path $packageRoot 'analysis\python\run_temporal3p5_mode_c_analysis.py'
    & python $script --base-root $baseOos --candidate-root $candidateOos --output-root $analysisRoot --base-checkpoint $baseCheckpoint --candidate-checkpoint $candidateCheckpoint --bank $bank --training-metadata $trainingMetadata
    if ($LASTEXITCODE -ne 0) { throw "Mode C analysis failed with exit code $LASTEXITCODE." }
    $closeout = Join-Path $analysisRoot 'C_MODE_CLOSEOUT.txt'
    if (-not (Test-Path -LiteralPath $closeout) -or (Get-Content -LiteralPath $closeout -Raw) -notmatch 'OVERALL_DELIVERY=COMPLETE') { throw 'Mode C closeout gate failed.' }
    foreach ($name in @('paired_kpi_with_ci.csv','paired_binary_outcome_with_ci.csv','terminal_classification_summary.csv','mass_weighted_service_summary.csv','station_level_service_summary.csv','terminal_type_transition.csv','target_group_performance.csv','base_frozen_tail_summary.csv','historical_issue_status.csv','00_plain_language_summary_zh.md')) {
        Copy-Item -LiteralPath (Join-Path $analysisRoot $name) -Destination (Join-Path $comparisonRoot $name) -Force
    }
    Set-Content -LiteralPath (Join-Path $statusRoot 'ANALYSIS_COMPLETED.txt') -Value "ANALYSIS_STATUS = COMPLETED`nMODE = C`nRUN_DIR = $runDir`nOUTPUT = $analysisRoot`nCOMPLETED_AT = $((Get-Date).ToString('o'))" -Encoding UTF8
    Write-Output "MODE_C_ANALYSIS_OUTPUT=$analysisRoot"
} finally {
    if ($lockStream) { $lockStream.Dispose() }
    Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
}
