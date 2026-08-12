param(
    [string]$RunId = 'run-001'
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$stageRoot = Join-Path $repo "results\task-002-stage2b-b3-smoke\71-stage-duration-capacity-sensitivity\$RunId"
$logRoot = Join-Path $stageRoot 'logs'
$stateRoot = Join-Path $stageRoot 'state'
$crossRoot = Join-Path $stageRoot 'cross_analysis\run-001'
$matlab = (Get-Command matlab -ErrorAction Stop).Source
$python = (Get-Command python -ErrorAction Stop).Source
$mainLog = Join-Path $logRoot 'sequential_runner.log'

New-Item -ItemType Directory -Force -Path $logRoot, $stateRoot | Out-Null

function Write-MainLog([string]$Message) {
    $line = "$(Get-Date -Format o) | $Message"
    Add-Content -LiteralPath $mainLog -Value $line -Encoding utf8
}

function Invoke-Matlab([string]$ScriptPath, [string]$LogPath) {
    $matlabPath = $ScriptPath.Replace('\', '/')
    $batch = "run('$matlabPath')"
    & $matlab -sd $repo -batch $batch *> $LogPath
    return $LASTEXITCODE
}

function Test-NonEmpty([string]$Path) {
    return (Test-Path -LiteralPath $Path -PathType Leaf) -and ((Get-Item -LiteralPath $Path).Length -gt 0)
}

function Test-CaseIntegrity([string]$CaseDir, [string]$Experiment, [string]$Mode) {
    $required = @(
        (Join-Path $CaseDir 'TRAIN_DONE.txt'),
        (Join-Path $CaseDir 'EVAL_DONE.txt'),
        (Join-Path $CaseDir 'parameter_identity.csv'),
        (Join-Path $CaseDir 'sensitivity_input.mat'),
        (Join-Path $CaseDir 'native_output\h2_workspace.mat'),
        (Join-Path $CaseDir 'stage71_oos_path_summary.csv'),
        (Join-Path $CaseDir 'stage71_oos_eval.mat')
    )
    foreach ($path in $required) {
        if (-not (Test-NonEmpty $path)) { return $false }
    }
    $identity = @(Import-Csv -LiteralPath (Join-Path $CaseDir 'parameter_identity.csv'))
    if ($identity.Count -ne 1 -or $identity[0].experiment -ne $Experiment -or $identity[0].terminal_mode -ne $Mode) {
        return $false
    }
    return $true
}

$launcher = @{
    'E1_8h' = Join-Path $repo 'terminalLoh_wdro\src\run_stage71_E1_8h_h2.m'
    'E2_6h_pmax_4over3' = Join-Path $repo 'terminalLoh_wdro\src\run_stage71_E2_6h_pmax_4over3_h2.m'
    'E3_8h_htt_4over3' = Join-Path $repo 'terminalLoh_wdro\src\run_stage71_E3_8h_htt_4over3_h2.m'
}
$evaluator = Join-Path $repo 'terminalLoh_wdro\src\run_stage71_oos_evaluator_h2.m'
$experiments = @('E1_8h', 'E2_6h_pmax_4over3', 'E3_8h_htt_4over3')
$modes = @('saa', 'chi2_eta003')
$caseStatus = @{}

Write-MainLog "RUNNER_START run_id=$RunId pid=$PID matlab=$matlab python=$python"

foreach ($experiment in $experiments) {
    foreach ($mode in $modes) {
        $caseKey = "${experiment}_${mode}"
        $caseDir = Join-Path $stageRoot "$experiment\case-$mode"
        $doneMarker = Join-Path $caseDir 'CASE_RUN_DONE.txt'
        $trainMarker = Join-Path $caseDir 'TRAIN_DONE.txt'
        $evalMarker = Join-Path $caseDir 'EVAL_DONE.txt'
        $trainLog = Join-Path $logRoot "${caseKey}_train.log"
        $evalLog = Join-Path $logRoot "${caseKey}_eval.log"

        if ((Test-Path -LiteralPath $doneMarker) -and (Test-CaseIntegrity $caseDir $experiment $mode)) {
            $caseStatus[$caseKey] = 'PASS_SKIPPED_ALREADY_COMPLETE'
            Write-MainLog "CASE_SKIP_COMPLETE case=$caseKey"
            continue
        }

        $env:STAGE71_RUN_ID = $RunId
        $env:STAGE71_TERMINAL_MODE = $mode
        $env:STAGE71_EXPERIMENT_ID = $experiment

        if (-not (Test-Path -LiteralPath $trainMarker)) {
            if (Test-Path -LiteralPath $caseDir) {
                $caseStatus[$caseKey] = 'FAIL_EXISTING_INCOMPLETE_TRAINING'
                Write-MainLog "CASE_FAIL_PRESERVED case=$caseKey reason=existing_directory_without_TRAIN_DONE"
                continue
            }
            Set-Content -LiteralPath (Join-Path $stateRoot "${experiment}_LAUNCHED.txt") -Value @(
                "experiment=$experiment", "terminal_mode=$mode", "launched_at=$(Get-Date -Format o)"
            ) -Encoding utf8
            Write-MainLog "TRAIN_START case=$caseKey launcher=$($launcher[$experiment])"
            $trainExit = Invoke-Matlab $launcher[$experiment] $trainLog
            Write-MainLog "TRAIN_EXIT case=$caseKey exit_code=$trainExit"
            if ($trainExit -ne 0 -or -not (Test-NonEmpty $trainMarker)) {
                $caseStatus[$caseKey] = "FAIL_TRAIN_EXIT_$trainExit"
                New-Item -ItemType Directory -Force -Path $caseDir | Out-Null
                Set-Content -LiteralPath (Join-Path $caseDir 'FAILED.txt') -Value @(
                    "phase=training", "exit_code=$trainExit", "log=$trainLog", "failed_at=$(Get-Date -Format o)"
                ) -Encoding utf8
                continue
            }
        } else {
            Write-MainLog "TRAIN_SKIP_EXISTING_PASS case=$caseKey"
        }

        if (-not (Test-Path -LiteralPath $evalMarker)) {
            Write-MainLog "EVAL_START case=$caseKey evaluator=$evaluator"
            $evalExit = Invoke-Matlab $evaluator $evalLog
            Write-MainLog "EVAL_EXIT case=$caseKey exit_code=$evalExit"
            if ($evalExit -ne 0 -or -not (Test-NonEmpty $evalMarker)) {
                $caseStatus[$caseKey] = "FAIL_EVAL_EXIT_$evalExit"
                Set-Content -LiteralPath (Join-Path $caseDir 'FAILED.txt') -Value @(
                    "phase=evaluation", "exit_code=$evalExit", "log=$evalLog", "failed_at=$(Get-Date -Format o)"
                ) -Encoding utf8
                continue
            }
        } else {
            Write-MainLog "EVAL_SKIP_EXISTING_PASS case=$caseKey"
        }

        if (Test-CaseIntegrity $caseDir $experiment $mode) {
            Set-Content -LiteralPath $doneMarker -Value @(
                'status=PASS', "experiment=$experiment", "terminal_mode=$mode",
                "train_log=$trainLog", "eval_log=$evalLog", "completed_at=$(Get-Date -Format o)"
            ) -Encoding utf8
            $caseStatus[$caseKey] = 'PASS'
            Write-MainLog "CASE_PASS case=$caseKey"
        } else {
            $caseStatus[$caseKey] = 'FAIL_MINIMAL_INTEGRITY'
            Set-Content -LiteralPath (Join-Path $caseDir 'FAILED.txt') -Value @(
                'phase=minimal_integrity', "failed_at=$(Get-Date -Format o)"
            ) -Encoding utf8
            Write-MainLog "CASE_FAIL case=$caseKey reason=minimal_integrity"
        }
    }

    $saaStatus = $caseStatus["${experiment}_saa"]
    $droStatus = $caseStatus["${experiment}_chi2_eta003"]
    $groupPass = ($saaStatus -like 'PASS*') -and ($droStatus -like 'PASS*')
    $groupShort = if ($experiment -eq 'E1_8h') {'E1'} elseif ($experiment -eq 'E2_6h_pmax_4over3') {'E2'} else {'E3'}
    $groupMarker = Join-Path $stageRoot "${groupShort}_RUN_DONE.txt"
    Set-Content -LiteralPath $groupMarker -Value @(
        "experiment=$experiment", "saa_status=$saaStatus", "dro_status=$droStatus",
        "group_pass=$groupPass", "completed_at=$(Get-Date -Format o)"
    ) -Encoding utf8
    Write-MainLog "GROUP_DONE experiment=$experiment pass=$groupPass"
}

$summaryLines = @(
    'Stage-71 numerical runs summary',
    "run_id=$RunId",
    "started_and_managed_by_pid=$PID",
    "completed_at=$(Get-Date -Format o)"
)
foreach ($experiment in $experiments) {
    foreach ($mode in $modes) {
        $key = "${experiment}_${mode}"
        $summaryLines += "$key=$($caseStatus[$key])"
        $caseDir = Join-Path $stageRoot "$experiment\case-$mode"
        $summaryLines += "$key.result_dir=$caseDir"
        $summaryLines += "$key.train_log=$(Join-Path $logRoot "${key}_train.log")"
        $summaryLines += "$key.eval_log=$(Join-Path $logRoot "${key}_eval.log")"
    }
    $identityPath = Join-Path $stageRoot "$experiment\case-saa\parameter_identity.csv"
    if (Test-Path -LiteralPath $identityPath) {
        $identity = @(Import-Csv -LiteralPath $identityPath)[0]
        $summaryLines += "$experiment.dt_h=$($identity.dt_h)"
        $summaryLines += "$experiment.rmax_kg=$($identity.rmax1_kg),$($identity.rmax2_kg),$($identity.rmax3_kg),$($identity.rmax4_kg)"
        $summaryLines += "$experiment.htt_capacity_kg_per_stage=$($identity.htt_capacity_kg_per_stage)"
    }
}
$numericalDone = Join-Path $stageRoot 'NUMERICAL_RUNS_DONE.txt'
Set-Content -LiteralPath $numericalDone -Value $summaryLines -Encoding utf8
Write-MainLog 'NUMERICAL_RUNS_DONE_WRITTEN'

$allPass = $true
foreach ($value in $caseStatus.Values) {
    if ($value -notlike 'PASS*') { $allPass = $false }
}
if (-not $allPass) {
    Set-Content -LiteralPath (Join-Path $stageRoot 'POSTPROCESS_SKIPPED_NUMERICAL_FAILURE.txt') -Value @(
        'Postprocessing was skipped because at least one numerical case failed.',
        "see=$numericalDone", "stopped_at=$(Get-Date -Format o)"
    ) -Encoding utf8
    Write-MainLog 'RUNNER_STOP numerical_failure'
    exit 2
}

$runRootRelative = "results/task-002-stage2b-b3-smoke/71-stage-duration-capacity-sensitivity/$RunId"
$crossRelative = "$runRootRelative/cross_analysis/run-001"
$postScript = Join-Path $repo 'terminalLoh_wdro\src\postprocess_stage71_all.py'
$verifyScript = Join-Path $repo 'terminalLoh_wdro\src\verify_stage71_sensitivity.py'
$postLog = Join-Path $logRoot 'postprocess_all.log'
$verifyLog = Join-Path $logRoot 'verification.log'

Write-MainLog 'POSTPROCESS_START'
& $python $postScript --run-root $runRootRelative --output $crossRelative *> $postLog
$postExit = $LASTEXITCODE
Write-MainLog "POSTPROCESS_EXIT exit_code=$postExit"
if ($postExit -ne 0) {
    Set-Content -LiteralPath (Join-Path $stageRoot 'POSTPROCESS_FAILED.txt') -Value @(
        "exit_code=$postExit", "log=$postLog", "failed_at=$(Get-Date -Format o)"
    ) -Encoding utf8
    exit 3
}

Write-MainLog 'VERIFICATION_START'
& $python $verifyScript --run-root $runRootRelative --output $crossRelative *> $verifyLog
$verifyExit = $LASTEXITCODE
Write-MainLog "VERIFICATION_EXIT exit_code=$verifyExit"
if ($verifyExit -ne 0) {
    Set-Content -LiteralPath (Join-Path $stageRoot 'VERIFICATION_FAILED.txt') -Value @(
        "exit_code=$verifyExit", "log=$verifyLog", "failed_at=$(Get-Date -Format o)"
    ) -Encoding utf8
    exit 4
}

Set-Content -LiteralPath (Join-Path $stageRoot 'ALL_DONE.txt') -Value @(
    'status=PASS', "numerical_summary=$numericalDone", "cross_analysis=$crossRoot",
    "main_log=$mainLog", "completed_at=$(Get-Date -Format o)",
    'git_commit_push=NOT_PERFORMED_BY_RUNNER'
) -Encoding utf8
Write-MainLog 'ALL_DONE_PASS'
exit 0
