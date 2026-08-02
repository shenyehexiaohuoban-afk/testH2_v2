param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^run-[0-9]{3}$')]
    [string]$RunId
)

$ErrorActionPreference = 'Stop'
$SourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ModuleDir = Split-Path -Parent $SourceDir
$ProjectRoot = Split-Path -Parent $ModuleDir
$OutputRoot = Join-Path $ProjectRoot 'results\task-002-stage2b-b3-smoke\48-markov-transition-perturbation'
$RunDir = Join-Path $OutputRoot $RunId
$ExpectedBranch = 'task/002-stage2b-b3-smoke'
$ExpectedHead = '2468b931f8c2c57b82f8bc7605564c011c34762a'

$branch = (git -C $ProjectRoot branch --show-current).Trim()
$head = (git -C $ProjectRoot rev-parse HEAD).Trim()
$upstream = (git -C $ProjectRoot rev-parse '@{upstream}').Trim()
if ($branch -ne $ExpectedBranch -or $head -ne $ExpectedHead -or $upstream -ne $ExpectedHead) {
    throw "C3 Git gate failed before run creation: branch=$branch head=$head upstream=$upstream"
}
if (Test-Path -LiteralPath $RunDir) { throw "Refusing to overwrite existing run directory: $RunDir" }
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
} else { $MatlabPath = $MatlabCommand.Source }
$PythonCommand = Get-Command python -ErrorAction SilentlyContinue
if ($null -eq $PythonCommand) { throw 'Python executable was not found.' }
$PythonPath = $PythonCommand.Source

function Convert-ToMatlabLiteral([string]$Value) { return $Value.Replace("'", "''") }
$ProcessRows = [System.Collections.Generic.List[object]]::new()
$StatusPath = Join-Path $RunDir 'process_status.csv'
function Save-ProcessStatus { $ProcessRows | Export-Csv -LiteralPath $StatusPath -NoTypeInformation -Encoding UTF8 }
function Invoke-MatlabBatch {
    param([string]$Label, [string]$Expression, [string]$LogName)
    $started = Get-Date
    $logPath = Join-Path $ProcessLogDir $LogName
    & $MatlabPath -batch $Expression *> $logPath
    $exitCode = $LASTEXITCODE
    $ended = Get-Date
    $ProcessRows.Add([pscustomobject]@{
        process_label = $Label; process_type = 'MATLAB'
        started_at = $started.ToString('o'); ended_at = $ended.ToString('o')
        runtime_sec = ($ended - $started).TotalSeconds; exit_code = $exitCode
        status = $(if ($exitCode -eq 0) { 'PASS' } else { 'FAIL' }); log_path = $logPath
    })
    Save-ProcessStatus
    if ($exitCode -ne 0) { throw "$Label failed with exit code $exitCode. See $logPath" }
}

try {
    $runLiteral = Convert-ToMatlabLiteral $RunDir
    $sourceLiteral = Convert-ToMatlabLiteral $SourceDir
    Invoke-MatlabBatch -Label 'prepare_markov_datasets' `
        -Expression "addpath('$sourceLiteral'); prepare_step04CC3_markov_inputs_h2('$runLiteral');" `
        -LogName 'prepare_process.txt'

    $prepareAudit = Get-Content -LiteralPath (Join-Path $RunDir 'prepare_mechanical_audit.txt')
    if ($prepareAudit -notcontains 'status=PASS') { throw 'C3 preparation mechanical audit did not PASS.' }
    $manifest = Import-Csv -LiteralPath (Join-Path $RunDir 'dataset_manifest.csv')
    $matrixAudit = Import-Csv -LiteralPath (Join-Path $RunDir 'transition_matrix_audit.csv')
    $frequencyAudit = Import-Csv -LiteralPath (Join-Path $RunDir 'transition_frequency_audit.csv')
    $seedAudit = Import-Csv -LiteralPath (Join-Path $RunDir 'seed_and_collision_audit.csv')
    $reproAudit = Import-Csv -LiteralPath (Join-Path $RunDir 'dataset_reproducibility_audit.csv')
    $crnAudit = Import-Csv -LiteralPath (Join-Path $RunDir 'common_random_numbers_audit.csv')
    if ($manifest.Count -ne 21 -or ($manifest | Where-Object { [int]$_.sample_count -ne 15000 -or [math]::Abs([double]$_.weight_sum - 1) -gt 1e-12 }).Count -ne 0) {
        throw 'C3 dataset manifest row/weight gate failed.'
    }
    if (($matrixAudit | Where-Object { $_.audit_pass -notin @('1','True','true') }).Count -ne 0 -or `
        ($frequencyAudit | Where-Object { $_.frequency_audit_pass -notin @('1','True','true') }).Count -ne 0 -or `
        ($seedAudit | Where-Object { $_.status -ne 'PASS' }).Count -ne 0 -or `
        ($reproAudit | Where-Object { $_.path_replay_pass -notin @('1','True','true') -or $_.formal_replay_pass -notin @('1','True','true') }).Count -ne 0 -or `
        ($crnAudit | Where-Object { $_.wind_CRN_matches_nominal -notin @('1','True','true') -or $_.line_resistance_CRN_matches_nominal -notin @('1','True','true') -or $_.road_resistance_CRN_matches_nominal -notin @('1','True','true') }).Count -ne 0) {
        throw 'C3 preparation matrix/seed/replay/CRN gate failed.'
    }

    for ($seedId = 1; $seedId -le 3; $seedId++) {
        for ($distributionId = 1; $distributionId -le 7; $distributionId++) {
            $label = "fixed_T_seed{0:D3}_dist{1:D3}" -f $seedId, $distributionId
            Invoke-MatlabBatch -Label $label `
                -Expression "addpath('$sourceLiteral'); run_step04CC3_fixed_T_dataset_h2('$runLiteral',$seedId,$distributionId);" `
                -LogName ("seed-{0:D3}_dist-{1:D3}_process.txt" -f $seedId, $distributionId)
            $caseDir = Join-Path $RunDir ("case-seed{0:D3}-dist{1:D3}" -f $seedId, $distributionId)
            $summary = Import-Csv -LiteralPath (Join-Path $caseDir 'fixed_T_summary.csv')
            $certificate = Import-Csv -LiteralPath (Join-Path $caseDir 'fixed_T_certificate.csv')
            $scenario = Import-Csv -LiteralPath (Join-Path $caseDir 'scenario_results.csv')
            if ($summary.Count -ne 3 -or $certificate.Count -ne 3 -or $scenario.Count -ne 45000) {
                throw "C3 case seed=$seedId distribution=$distributionId row-count gate failed."
            }
            if (($summary | Where-Object { $_.solver_status -ne 'OPTIMAL' }).Count -ne 0 -or `
                ($certificate | Where-Object { $_.certificate_pass -notin @('1','True','true') -or [double]$_.maximum_mechanical_residual -gt 1e-7 }).Count -ne 0) {
                throw "C3 case seed=$seedId distribution=$distributionId fixed-T certificate failed."
            }
        }
    }

    $finalizer = Join-Path $SourceDir 'finalize_step04CC3_markov_validation.py'
    $finalizeLog = Join-Path $ProcessLogDir 'finalize_process.txt'
    $finalizeStarted = Get-Date
    & $PythonPath $finalizer $RunDir *> $finalizeLog
    $finalizeExit = $LASTEXITCODE
    $finalizeEnded = Get-Date
    $ProcessRows.Add([pscustomobject]@{
        process_label = 'finalize_outputs'; process_type = 'PYTHON'
        started_at = $finalizeStarted.ToString('o'); ended_at = $finalizeEnded.ToString('o')
        runtime_sec = ($finalizeEnded - $finalizeStarted).TotalSeconds; exit_code = $finalizeExit
        status = $(if ($finalizeExit -eq 0) { 'PASS' } else { 'FAIL' }); log_path = $finalizeLog
    })
    Save-ProcessStatus
    if ($finalizeExit -ne 0) { throw "C3 finalizer failed with exit code $finalizeExit. See $finalizeLog" }

    $required = @(
        'markov_perturbation_spec.csv','perturbed_transition_matrices.csv',
        'transition_matrix_audit.csv','seed_and_collision_audit.csv','dataset_manifest.csv',
        'fixed_T_full_results.csv','seedwise_paired_comparison.csv','paired_difference_ci.csv',
        'perturbation_trend_summary.csv','candidate_value_summary.txt','README.md','LARGE_FILE_MANIFEST.md'
    )
    foreach ($name in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $RunDir $name))) { throw "Required C3 output missing: $name" }
    }
    if ($ProcessRows.Count -ne 23 -or ($ProcessRows | Where-Object { $_.status -ne 'PASS' }).Count -ne 0) {
        throw 'C3 process status count/pass gate failed.'
    }
    Write-Output "STEP04CC3_ISOLATED_RUN_PASS|run=$RunId|dir=$RunDir"
} catch {
    $failurePath = Join-Path $RunDir 'RUN_FAILED.txt'
    @(
        'status=FAILED',
        ('failed_at=' + (Get-Date).ToString('o')),
        ('message=' + $_.Exception.Message),
        'accepted=0',
        'retry_rule=use_a_new_run_id'
    ) | Set-Content -LiteralPath $failurePath -Encoding UTF8
    throw
}
