param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$matlabExe = 'D:\Program Files\MATLAB\R2022a\bin\matlab.exe'
$pythonExe = (Get-Command python -ErrorAction Stop).Source
$runBase = Join-Path $repoRoot 'results\task-002-stage2b-b3-smoke\45-extreme-aware-dro-decision-value'
$workDir = Join-Path $runBase 'run-014.work'
$formalDir = Join-Path $runBase 'run-014'
$casesDir = Join-Path $workDir 'cases'
$preparedFile = Join-Path $workDir 'prepared_inputs.mat'

function Convert-ToMatlabPath([string]$Path) {
    return $Path.Replace('\', '/').Replace("'", "''")
}

function Test-Truth([object]$Value) {
    return @('1','true','yes','pass') -contains ([string]$Value).Trim().ToLowerInvariant()
}

function Invoke-IsolatedMatlab([string]$Expression, [string]$Token) {
    $guardedExpression = $Expression.TrimEnd(';') + '; System.Environment.Exit(0);'
    $quotedExpression = '"' + $guardedExpression.Replace('"', '\"') + '"'
    $process = Start-Process -FilePath $matlabExe -ArgumentList @('-batch', $quotedExpression) `
        -WorkingDirectory $repoRoot -WindowStyle Hidden -Wait -PassThru
    $exitCode = $process.ExitCode
    Start-Sleep -Milliseconds 750
    $orphans = @(Get-CimInstance Win32_Process | Where-Object {
        $_.Name -match '^MATLAB\.exe$|^matlab\.exe$' -and
        $_.CommandLine -and $_.CommandLine.Contains($Token)
    })
    if ($orphans.Count -gt 0) {
        foreach ($orphan in $orphans) {
            Stop-Process -Id $orphan.ProcessId -Force -ErrorAction SilentlyContinue
        }
        throw "MATLAB process was not released for token $Token."
    }
    if ($exitCode -ne 0) {
        throw "MATLAB process failed for token $Token with exit code $exitCode."
    }
}

function Assert-CasePass([int]$CaseId, [string]$CaseDir) {
    $summaryFile = Join-Path $CaseDir 'case_summary.csv'
    $auditFile = Join-Path $CaseDir 'case_fixed_audit.csv'
    if (!(Test-Path -LiteralPath $summaryFile) -or !(Test-Path -LiteralPath $auditFile)) {
        throw "Case $CaseId did not produce required summary/audit files."
    }
    $summary = Import-Csv -LiteralPath $summaryFile
    $audit = Import-Csv -LiteralPath $auditFile
    if ($summary.Count -ne 1 -or $audit.Count -ne 1) {
        throw "Case $CaseId summary/audit row count failed."
    }
    if ($summary.solver_status -ne 'OPTIMAL' -or !(Test-Truth $summary.mechanical_pass) -or
        !(Test-Truth $audit.fixed_audit_pass)) {
        throw "Case $CaseId status or mechanical audit failed."
    }
    $absoluteGap = [double]$summary.absolute_gap
    $relativeGap = [double]$summary.relative_gap
    if ($absoluteGap -gt 1e-4 -and $relativeGap -gt 1e-8) {
        throw "Case $CaseId convergence certificate failed."
    }
    Write-Output ("CASE_PASS|case={0}|eta={1}|design={2}|kappa={3}|gap={4}|iterations={5}" -f `
        $CaseId,$summary.eta,$summary.design,$summary.kappa,$summary.absolute_gap,$summary.iterations)
}

if (Test-Path -LiteralPath $formalDir) {
    throw "Formal run directory already exists: $formalDir"
}
if (Test-Path -LiteralPath $workDir) {
    throw "Work directory already exists: $workDir"
}
New-Item -ItemType Directory -Path $casesDir -Force | Out-Null

try {
    $rootMatlab = Convert-ToMatlabPath $repoRoot
    $workMatlab = Convert-ToMatlabPath $workDir
    $preparedMatlab = Convert-ToMatlabPath $preparedFile
    Write-Output 'STEP04CB_ISOLATED|phase=prepare'
    $prepareExpr = "cd('$rootMatlab'); addpath(pwd); addpath('terminalLoh_wdro/src'); prepare_step04CB_isolated_inputs_h2('$workMatlab');"
    Invoke-IsolatedMatlab -Expression $prepareExpr -Token 'prepare_step04CB_isolated_inputs_h2'
    if (!(Test-Path -LiteralPath $preparedFile)) {
        throw 'Prepared input MAT was not produced.'
    }
    $prepareAudit = Get-Content -LiteralPath (Join-Path $workDir 'prepare_mechanical_audit.txt') -Raw
    if (!$prepareAudit.Contains('status=PASS') -or !$prepareAudit.Contains('other_initial_states=0')) {
        throw 'Preparation mechanical audit failed.'
    }

    for ($caseId = 1; $caseId -le 30; $caseId++) {
        $caseDir = Join-Path $casesDir ('case-{0:D3}' -f $caseId)
        $caseMatlab = Convert-ToMatlabPath $caseDir
        $previousIteration = -1
        $optimizationComplete = $false
        for ($batchId = 1; $batchId -le 50; $batchId++) {
            Write-Output ("STEP04CB_ISOLATED|phase=optimize|case={0}|batch={1}" -f $caseId,$batchId)
            $caseExpr = "cd('$rootMatlab'); addpath(pwd); addpath('terminalLoh_wdro/src'); run_step04CB_isolated_case_h2('$preparedMatlab',$caseId,'$caseMatlab');"
            Invoke-IsolatedMatlab -Expression $caseExpr -Token "run_step04CB_isolated_case_h2('$preparedMatlab',$caseId"
            if (Test-Path -LiteralPath (Join-Path $caseDir 'case_summary.csv')) {
                $optimizationComplete = $true
                break
            }
            $caseWorkDir = $caseDir + '.work'
            $batchStatusFile = Join-Path $caseWorkDir ('batch-{0:D3}_status.csv' -f $batchId)
            if (!(Test-Path -LiteralPath $batchStatusFile)) {
                throw "Case $caseId batch $batchId produced neither a final summary nor a batch certificate."
            }
            $batchStatus = Import-Csv -LiteralPath $batchStatusFile
            $currentIteration = [int]$batchStatus.iterations
            if ($batchStatus.Count -ne 1 -or $batchStatus.status -ne 'BATCH_LIMIT' -or
                $currentIteration -le $previousIteration) {
                throw "Case $caseId batch $batchId continuation certificate failed."
            }
            $previousIteration = $currentIteration
        }
        if (!$optimizationComplete) {
            throw "Case $caseId exceeded the certified batch limit without a final solution."
        }
        $summary = Import-Csv -LiteralPath (Join-Path $caseDir 'case_summary.csv')
        if ($summary.Count -ne 1 -or $summary.solver_status -ne 'OPTIMAL') {
            throw "Case $caseId optimization did not finish OPTIMAL."
        }

        Write-Output ("STEP04CB_ISOLATED|phase=fixed_audit|case={0}" -f $caseId)
        $auditExpr = "cd('$rootMatlab'); addpath(pwd); addpath('terminalLoh_wdro/src'); audit_step04CB_isolated_case_h2('$preparedMatlab','$caseMatlab');"
        Invoke-IsolatedMatlab -Expression $auditExpr -Token "audit_step04CB_isolated_case_h2('$preparedMatlab','$caseMatlab'"
        Assert-CasePass -CaseId $caseId -CaseDir $caseDir
    }

    $fullDir = Join-Path $workDir 'full_capacity_audit'
    $fullMatlab = Convert-ToMatlabPath $fullDir
    Write-Output 'STEP04CB_ISOLATED|phase=full_capacity_audit'
    $fullExpr = "cd('$rootMatlab'); addpath(pwd); addpath('terminalLoh_wdro/src'); audit_step04CB_full_capacity_h2('$preparedMatlab','$fullMatlab');"
    Invoke-IsolatedMatlab -Expression $fullExpr -Token 'audit_step04CB_full_capacity_h2'
    $fullAudit = Import-Csv -LiteralPath (Join-Path $fullDir 'full_capacity_fixed_audit.csv')
    if ($fullAudit.Count -ne 6 -or @($fullAudit | Where-Object { !(Test-Truth $_.fixed_audit_pass) }).Count -ne 0) {
        throw 'FULL_CAPACITY audit failed.'
    }

    Write-Output 'STEP04CB_ISOLATED|phase=finalize_without_solver'
    $finalizer = Join-Path $PSScriptRoot 'finalize_step04CB_isolated.py'
    $python = Start-Process -FilePath $pythonExe -ArgumentList @(
        ('"{0}"' -f $finalizer), ('"{0}"' -f $repoRoot), ('"{0}"' -f $workDir)
    ) -WorkingDirectory $repoRoot -WindowStyle Hidden -Wait -PassThru
    if ($python.ExitCode -ne 0) {
        throw "Python finalizer failed with exit code $($python.ExitCode)."
    }
    $mechanicalFile = Join-Path $workDir 'mechanical_audit.txt'
    if (!(Test-Path -LiteralPath $mechanicalFile) -or
        !(Get-Content -LiteralPath $mechanicalFile -Raw).Contains('status=PASS')) {
        throw 'Overall mechanical audit did not pass.'
    }
    $required = @(
        'README.md','conclusion.txt','next_stage_plan.md','extreme_aware_formulation.md',
        'convexity_and_subgradient_audit.md','state19_extreme_set_manifest.csv',
        'beta_scale_design.csv','enhanced_model_results.csv','convergence_and_bounds.csv',
        'active_extreme_cuts.csv','saa_chi2_extreme_full_comparison.csv',
        'extreme_headroom_audit.csv','recoverable_risk_fraction.csv',
        'nominal_performance_tradeoff.csv','extreme_loss_and_shortage_summary.csv',
        'terminalLOH_capacity_binding.csv','decision_value_conclusion.md',
        'runtime_and_solver_calls.csv','mechanical_audit.txt','LARGE_FILE_MANIFEST.md'
    )
    $missing = @($required | Where-Object { !(Test-Path -LiteralPath (Join-Path $workDir $_)) })
    if ($missing.Count -ne 0) {
        throw "Final output files missing: $($missing -join ', ')"
    }
    Move-Item -LiteralPath $workDir -Destination $formalDir
    Write-Output "STEP04CB_ISOLATED_COMPLETE|status=PASS|output=$formalDir|cases=30"
}
catch {
    if (Test-Path -LiteralPath $workDir) {
        $index = 1
        do {
            $failedDir = Join-Path $runBase ('run-014.failed-{0:D3}' -f $index)
            $index++
        } while (Test-Path -LiteralPath $failedDir)
        Move-Item -LiteralPath $workDir -Destination $failedDir
        Write-Error "Step-04C-B isolated run failed and was preserved at $failedDir. $($_.Exception.Message)"
    }
    throw
}
