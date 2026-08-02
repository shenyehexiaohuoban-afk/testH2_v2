param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^run-[0-9]{3}$')]
    [string]$RunId
)

$ErrorActionPreference = 'Stop'
$SourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ModuleDir = Split-Path -Parent $SourceDir
$ProjectRoot = Split-Path -Parent $ModuleDir
$OutputRoot = Join-Path $ProjectRoot 'results\task-002-stage2b-b3-smoke\46-flat-chi2-eta-calibration'
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
    if ([string]::IsNullOrWhiteSpace($MatlabPath)) {
        throw 'MATLAB executable was not found.'
    }
} else {
    $MatlabPath = $MatlabCommand.Source
}
$PythonCommand = Get-Command python -ErrorAction SilentlyContinue
if ($null -eq $PythonCommand) {
    throw 'Python executable was not found.'
}
$PythonPath = $PythonCommand.Source

function Convert-ToMatlabLiteral([string]$Value) {
    return $Value.Replace("'", "''")
}

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
    if ($exitCode -ne 0) {
        throw "$Label failed with exit code $exitCode. See $logPath"
    }
}

$runLiteral = Convert-ToMatlabLiteral $RunDir
$sourceLiteral = Convert-ToMatlabLiteral $SourceDir
Invoke-MatlabBatch -Label 'prepare_inputs' `
    -Expression "addpath('$sourceLiteral'); prepare_step04CC1_eta_inputs_h2('$runLiteral');" `
    -LogName 'prepare_process.txt'

$prepareAudit = Get-Content -LiteralPath (Join-Path $RunDir 'prepare_mechanical_audit.txt')
if ($prepareAudit -notcontains 'status=PASS') {
    throw 'Prepared input mechanical audit did not PASS.'
}

for ($caseId = 1; $caseId -le 8; $caseId++) {
    Invoke-MatlabBatch -Label ("eta_case_{0:D3}" -f $caseId) `
        -Expression "addpath('$sourceLiteral'); run_step04CC1_eta_case_h2('$runLiteral',$caseId);" `
        -LogName ("case-{0:D3}_process.txt" -f $caseId)

    $caseDir = Join-Path $RunDir ("cases\case-{0:D3}" -f $caseId)
    $summary = Import-Csv -LiteralPath (Join-Path $caseDir 'case_summary.csv')
    $certificate = Import-Csv -LiteralPath (Join-Path $caseDir 'solver_certificate.csv')
    $dataset = Import-Csv -LiteralPath (Join-Path $caseDir 'dataset_metrics.csv')
    $stress = Import-Csv -LiteralPath (Join-Path $caseDir 'stress_metrics.csv')
    if ($summary.Count -ne 1 -or $certificate.Count -ne 1 -or `
            $dataset.Count -ne 3 -or $stress.Count -ne 1) {
        throw "Case $caseId output row count check failed."
    }
    if ($summary[0].solver_status -ne 'OPTIMAL' -or `
            $summary[0].audit_status -ne 'PASS' -or `
            $summary[0].case_pass -notin @('1','True','true')) {
        throw "Case $caseId solver/audit status check failed."
    }
    if ($certificate[0].certificate_pass -notin @('1','True','true') -or `
            [double]$certificate[0].UB -lt [double]$certificate[0].LB -or `
            (([double]$certificate[0].absolute_gap -gt 0.0001000001) -and `
             ([double]$certificate[0].relative_gap -gt 1.0001e-8)) -or `
            [double]$certificate[0].iteration_count -lt 1 -or `
            [double]$certificate[0].maximum_mechanical_residual -gt 1e-5) {
        throw "Case $caseId LB/UB/gap/iteration/mechanical certificate check failed."
    }
}

$finalizer = Join-Path $SourceDir 'finalize_step04CC1_eta_screening.py'
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
if ($finalizeExit -ne 0) {
    throw "Finalizer failed with exit code $finalizeExit. See $finalizeLog"
}

$required = @(
    'eta_full_results.csv',
    'eta_validation_comparison.csv',
    'eta_stress_test_comparison.csv',
    'eta_solver_certificate.csv',
    'eta_decision_stability.csv',
    'eta_screening_summary.txt',
    'README.md',
    'LARGE_FILE_MANIFEST.md'
)
foreach ($name in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $RunDir $name))) {
        throw "Required output missing after finalization: $name"
    }
}
Write-Output "STEP04CC1_ISOLATED_RUN_PASS|run=$RunId|dir=$RunDir"
