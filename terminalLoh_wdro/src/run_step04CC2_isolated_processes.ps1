param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^run-[0-9]{3}$')]
    [string]$RunId
)

$ErrorActionPreference = 'Stop'
$SourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ModuleDir = Split-Path -Parent $SourceDir
$ProjectRoot = Split-Path -Parent $ModuleDir
$OutputRoot = Join-Path $ProjectRoot 'results\task-002-stage2b-b3-smoke\47-flat-chi2-independent-path-validation'
$RunDir = Join-Path $OutputRoot $RunId

if (Test-Path -LiteralPath $RunDir) {
    throw "Refusing to overwrite existing run directory: $RunDir"
}
New-Item -ItemType Directory -Path $RunDir | Out-Null
$ProcessLogDir = Join-Path $RunDir 'process_logs'
New-Item -ItemType Directory -Path $ProcessLogDir | Out-Null

$MatlabCommand = Get-Command matlab -ErrorAction SilentlyContinue
if ($null -eq $MatlabCommand) {
    $candidates = @(
        'C:\Program Files\MATLAB\R2024b\bin\matlab.exe',
        'C:\Program Files\MATLAB\R2024a\bin\matlab.exe',
        'C:\Program Files\MATLAB\R2023b\bin\matlab.exe',
        'C:\Program Files\MATLAB\R2022a\bin\matlab.exe'
    )
    $MatlabPath = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($MatlabPath)) { throw 'MATLAB executable was not found.' }
} else {
    $MatlabPath = $MatlabCommand.Source
}
$PythonCommand = Get-Command python -ErrorAction SilentlyContinue
if ($null -eq $PythonCommand) { throw 'Python executable was not found.' }
$PythonPath = $PythonCommand.Source

function Convert-ToMatlabLiteral([string]$Value) { return $Value.Replace("'", "''") }

$ProcessRows = [System.Collections.Generic.List[object]]::new()
$StatusPath = Join-Path $RunDir 'process_status.csv'
function Save-ProcessStatus {
    $ProcessRows | Export-Csv -LiteralPath $StatusPath -NoTypeInformation -Encoding UTF8
}
function Invoke-MatlabBatch {
    param([string]$Label, [string]$Expression, [string]$LogName)
    $started = Get-Date
    $logPath = Join-Path $ProcessLogDir $LogName
    & $MatlabPath -batch $Expression *> $logPath
    $exitCode = $LASTEXITCODE
    $ended = Get-Date
    $ProcessRows.Add([pscustomobject]@{
        process_label = $Label
        process_type = 'MATLAB'
        started_at = $started.ToString('o')
        ended_at = $ended.ToString('o')
        runtime_sec = ($ended - $started).TotalSeconds
        exit_code = $exitCode
        status = $(if ($exitCode -eq 0) { 'PASS' } else { 'FAIL' })
        log_path = $logPath
    })
    Save-ProcessStatus
    if ($exitCode -ne 0) { throw "$Label failed with exit code $exitCode. See $logPath" }
}

$runLiteral = Convert-ToMatlabLiteral $RunDir
$sourceLiteral = Convert-ToMatlabLiteral $SourceDir
Invoke-MatlabBatch -Label 'prepare_independent_datasets' `
    -Expression "addpath('$sourceLiteral'); prepare_step04CC2_independent_inputs_h2('$runLiteral');" `
    -LogName 'prepare_process.txt'

$prepareAudit = Get-Content -LiteralPath (Join-Path $RunDir 'prepare_mechanical_audit.txt')
if ($prepareAudit -notcontains 'status=PASS') { throw 'Prepared input mechanical audit did not PASS.' }
$manifest = Import-Csv -LiteralPath (Join-Path $RunDir 'independent_dataset_manifest.csv')
$seedAudit = Import-Csv -LiteralPath (Join-Path $RunDir 'independent_seed_and_collision_audit.csv')
$reproAudit = Import-Csv -LiteralPath (Join-Path $RunDir 'independent_reproducibility_audit.csv')
if ($manifest.Count -ne 3 -or ($manifest | Where-Object { [int]$_.sample_count -ne 15000 }).Count -ne 0 -or `
        ($seedAudit | Where-Object { $_.status -ne 'PASS' }).Count -ne 0 -or `
        ($reproAudit | Where-Object { $_.path_replay_pass -notin @('1','True','true') -or $_.formal_replay_pass -notin @('1','True','true') }).Count -ne 0) {
    throw 'Preparation manifest/seed/reproducibility row gate failed.'
}

for ($datasetId = 1; $datasetId -le 3; $datasetId++) {
    Invoke-MatlabBatch -Label ("fixed_T_dataset_{0:D3}" -f $datasetId) `
        -Expression "addpath('$sourceLiteral'); run_step04CC2_fixed_T_dataset_h2('$runLiteral',$datasetId);" `
        -LogName ("dataset-{0:D3}_process.txt" -f $datasetId)

    $datasetDir = Join-Path $RunDir ("dataset-{0:D3}" -f $datasetId)
    $summary = Import-Csv -LiteralPath (Join-Path $datasetDir 'fixed_T_summary.csv')
    $certificate = Import-Csv -LiteralPath (Join-Path $datasetDir 'fixed_T_certificate.csv')
    $scenario = Import-Csv -LiteralPath (Join-Path $datasetDir 'scenario_results.csv')
    if ($summary.Count -ne 3 -or $certificate.Count -ne 3 -or $scenario.Count -ne 45000) {
        throw "Dataset $datasetId output row count check failed."
    }
    if (($summary | Where-Object { $_.solver_status -ne 'OPTIMAL' }).Count -ne 0 -or `
            ($certificate | Where-Object { $_.certificate_pass -notin @('1','True','true') -or [double]$_.maximum_mechanical_residual -gt 1e-7 }).Count -ne 0) {
        throw "Dataset $datasetId fixed-T certificate check failed."
    }
}

$finalizer = Join-Path $SourceDir 'finalize_step04CC2_independent_validation.py'
$finalizeLog = Join-Path $ProcessLogDir 'finalize_process.txt'
$finalizeStarted = Get-Date
& $PythonPath $finalizer $RunDir *> $finalizeLog
$finalizeExit = $LASTEXITCODE
$finalizeEnded = Get-Date
$ProcessRows.Add([pscustomobject]@{
    process_label = 'finalize_outputs'
    process_type = 'PYTHON'
    started_at = $finalizeStarted.ToString('o')
    ended_at = $finalizeEnded.ToString('o')
    runtime_sec = ($finalizeEnded - $finalizeStarted).TotalSeconds
    exit_code = $finalizeExit
    status = $(if ($finalizeExit -eq 0) { 'PASS' } else { 'FAIL' })
    log_path = $finalizeLog
})
Save-ProcessStatus
if ($finalizeExit -ne 0) { throw "Finalizer failed with exit code $finalizeExit. See $finalizeLog" }

$required = @(
    'independent_dataset_manifest.csv',
    'independent_seed_and_collision_audit.csv',
    'independent_path_overlap_audit.csv',
    'fixed_T_full_results.csv',
    'fixed_T_seedwise_comparison.csv',
    'fixed_T_paired_difference.csv',
    'fixed_T_paired_ci.csv',
    'cross_seed_stability_summary.csv',
    'candidate_tradeoff_summary.txt',
    'README.md',
    'LARGE_FILE_MANIFEST.md'
)
foreach ($name in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $RunDir $name))) {
        throw "Required output missing after finalization: $name"
    }
}
Write-Output "STEP04CC2_ISOLATED_RUN_PASS|run=$RunId|dir=$RunDir"
