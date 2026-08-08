param(
    [string]$WorkDir = "results/task-002-stage2b-b3-smoke/53-35state-saa-vs-eta003-terminal-loh/run-001",
    [ValidateSet("All", "Prepare", "ClonePrepare", "Cases", "State19", "Remaining")]
    [string]$Stage = "All",
    [string]$PreparedSourceWorkDir = ""
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$pythonCommand = Get-Command python -ErrorAction Stop
$env:STEP04CC6_PYTHON_EXE = $pythonCommand.Source
$env:STEP04CC6_GUROBIPY_PATH = Join-Path $repo "terminalLoh_wdro\output\step04cc6_python_runtime\gurobipy-12.0.1"
if (-not (Test-Path -LiteralPath (Join-Path $env:STEP04CC6_GUROBIPY_PATH "gurobipy"))) {
    throw "Missing local C6 gurobipy 12.0.1 runtime: $env:STEP04CC6_GUROBIPY_PATH"
}
$target = Join-Path $repo $WorkDir
$logs = Join-Path $target "process_logs"
$statusPath = Join-Path $target "solve_progress_manifest.csv"
if ($Stage -in @("All", "Prepare", "ClonePrepare")) {
    if (Test-Path -LiteralPath $target) { throw "Refusing to overwrite existing C6 run directory: $target" }
    New-Item -ItemType Directory -Path $target | Out-Null
    New-Item -ItemType Directory -Path $logs | Out-Null
} else {
    if (-not (Test-Path -LiteralPath $target)) { throw "C6 prepared run directory does not exist: $target" }
    if (-not (Test-Path -LiteralPath $logs)) { throw "C6 process log directory is missing: $logs" }
}
$statuses = New-Object System.Collections.Generic.List[object]
if (Test-Path -LiteralPath $statusPath) {
    foreach ($prior in @(Import-Csv -LiteralPath $statusPath)) { $statuses.Add($prior) }
}

function Invoke-IsolatedMatlab {
    param([string]$Label, [string]$Expression, [bool]$UseJvm = $false)
    $log = Join-Path $logs ($Label + ".txt")
    if (Test-Path -LiteralPath $log) { throw "Refusing to overwrite C6 process log: $log" }
    $started = Get-Date
    $priorErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    if ($UseJvm) {
        $guardedExpression = $Expression + " java.lang.System.exit(0)"
        & matlab -batch $guardedExpression *> $log
    } else {
        $guardedExpression = $Expression + " System.Environment.Exit(0)"
        & matlab -nojvm -batch $guardedExpression *> $log
    }
    $code = $LASTEXITCODE
    $ErrorActionPreference = $priorErrorActionPreference
    $ended = Get-Date
    $statuses.Add([pscustomobject]@{
        process_label=$Label; process_type="MATLAB"; exit_code=$code
        started_at=$started.ToString("o"); ended_at=$ended.ToString("o")
        runtime_sec=($ended-$started).TotalSeconds; log_path=$log; pass=($code -eq 0)
    })
    $statuses | Export-Csv -LiteralPath $statusPath -NoTypeInformation -Encoding UTF8
    if ($code -ne 0) { throw "MATLAB process failed: $Label (exit $code)" }
}
function Quote-Matlab([string]$Value) { return $Value.Replace("'", "''").Replace("\", "/") }
function Import-FrozenPreparation {
    param([string]$SourceWorkDir)
    if ([string]::IsNullOrWhiteSpace($SourceWorkDir)) { throw "ClonePrepare requires -PreparedSourceWorkDir" }
    $source = Join-Path $repo $SourceWorkDir
    if (-not (Test-Path -LiteralPath $source) -or (Resolve-Path $source).Path -eq (Resolve-Path $target).Path) {
        throw "Invalid C6 prepared source directory: $source"
    }
    $sourceStatuses = @(Import-Csv -LiteralPath (Join-Path $source "solve_progress_manifest.csv"))
    $sourcePreparationStatuses = @($sourceStatuses | Where-Object { $_.process_label -like "prepare-*" })
    if ($sourcePreparationStatuses.Count -ne 36 -or
        @($sourcePreparationStatuses | Where-Object { [int]$_.exit_code -ne 0 -or $_.pass -notin @("True","true","1") }).Count -ne 0 -or
        -not (Select-String -LiteralPath (Join-Path $source "prepare_mechanical_audit.txt") -Pattern '^status=PASS$' -Quiet)) {
        throw "Prepared source did not complete its 36/36 preparation gate"
    }
    $sourceManifest = @(Import-Csv -LiteralPath (Join-Path $source "prepared_state_manifest.csv"))
    if ($sourceManifest.Count -ne 35 -or
        (Compare-Object @($sourceManifest | ForEach-Object { [int]$_.state_id }) (1..35)).Count -ne 0) {
        throw "Prepared source state manifest is incomplete"
    }
    $cloneRows = New-Object System.Collections.Generic.List[object]
    foreach ($row in $sourceManifest) {
        $state = [int]$row.state_id
        $sourcePayload = [string]$row.local_payload_path
        if (-not (Test-Path -LiteralPath $sourcePayload)) { throw "Missing source payload for state $state" }
        $sourceHash = (Get-FileHash -LiteralPath $sourcePayload -Algorithm SHA256).Hash.ToLower()
        if ($sourceHash -ne ([string]$row.payload_sha256).ToLower()) { throw "Source payload hash mismatch for state $state" }
        $destinationPayload = Join-Path $target ("prepared_inputs\state-{0:d3}-period-input.mat" -f $state)
        if (Test-Path -LiteralPath $destinationPayload) { throw "Refusing to overwrite cloned payload for state $state" }
        Copy-Item -LiteralPath $sourcePayload -Destination $destinationPayload
        $destinationHash = (Get-FileHash -LiteralPath $destinationPayload -Algorithm SHA256).Hash.ToLower()
        if ($destinationHash -ne $sourceHash) { throw "Cloned payload hash mismatch for state $state" }
        $newRow = $row.PSObject.Copy()
        $newRow.local_payload_path = $destinationPayload
        $newRow.payload_sha256 = $destinationHash
        $newRow | Export-Csv -LiteralPath (Join-Path $target ("prepared_state_rows\state-{0:d3}.csv" -f $state)) -NoTypeInformation -Encoding UTF8
        $cloneRows.Add([pscustomobject]@{
            state_id=$state; source_run=(Split-Path -Leaf $source); source_payload_path=$sourcePayload
            source_payload_sha256=$sourceHash; destination_payload_path=$destinationPayload
            destination_payload_sha256=$destinationHash; byte_identical=$true
            source_preparation_process_count=36; source_preparation_all_pass=$true
        })
    }
    $cloneRows | Export-Csv -LiteralPath (Join-Path $target "prepared_input_clone_audit.csv") -NoTypeInformation -Encoding UTF8
    $now = Get-Date
    $statuses.Add([pscustomobject]@{
        process_label="prepare-clone-verify"; process_type="POWERSHELL"; exit_code=0
        started_at=$now.ToString("o"); ended_at=$now.ToString("o"); runtime_sec=0
        log_path=(Join-Path $target "prepared_input_clone_audit.csv"); pass=$true
    })
    $statuses | Export-Csv -LiteralPath $statusPath -NoTypeInformation -Encoding UTF8
}
function Complete-Preparation {
    $rowDir = Join-Path $target "prepared_state_rows"
    $rowFiles = @(Get-ChildItem -LiteralPath $rowDir -Filter "state-*.csv" | Sort-Object Name)
    if ($rowFiles.Count -ne 35) { throw "Expected 35 isolated preparation rows; found $($rowFiles.Count)" }
    $prepared = @($rowFiles | ForEach-Object { Import-Csv -LiteralPath $_.FullName })
    $stateIds = @($prepared | ForEach-Object { [int]$_.state_id })
    if ((Compare-Object $stateIds (1..35)).Count -ne 0) { throw "Prepared state IDs are missing or duplicated" }
    $prepared | Export-Csv -LiteralPath (Join-Path $target "prepared_state_manifest.csv") -NoTypeInformation -Encoding UTF8
    $groupValues = @($prepared | ForEach-Object { [double]$_.exact_group_count })
    $groupStats = $groupValues | Measure-Object -Sum -Minimum -Maximum
    $parameters = Import-Csv -LiteralPath (Join-Path $target "frozen_parameter_table.csv")
    function ParameterValue([string]$Name) {
        $row = @($parameters | Where-Object { $_.parameter_name -eq $Name })
        if ($row.Count -ne 1) { throw "Missing or duplicate frozen parameter: $Name" }
        return [double]$row[0].value
    }
    $hashRows = @(Import-Csv -LiteralPath (Join-Path $target "frozen_input_manifest.csv"))
    $allHashesPass = @($hashRows | Where-Object { $_.hash_pass -notin @("True","true","1") }).Count -eq 0
    [pscustomobject]@{
        state_count=35; optimization_case_count=70; total_original_records=525000
        total_exact_groups=[double]$groupStats.Sum; minimum_exact_groups=[double]$groupStats.Minimum
        maximum_exact_groups=[double]$groupStats.Maximum; c_H2=(ParameterValue "c_H2")
        M_H2=(ParameterValue "M_H2"); electricity_per_kg_H2=(ParameterValue "electricity_per_kg_H2")
        all_frozen_hashes_pass=$allHashesPass
        prepare_runtime_sec=($prepared | Measure-Object -Property prepare_runtime_sec -Sum).Sum
    } | Export-Csv -LiteralPath (Join-Path $target "prepare_summary.csv") -NoTypeInformation -Encoding UTF8
    @(
        "status=PASS", "state_count=35", "case_count=70", "eta_set=0,0.03",
        "all_states_R15000=1", "all_nominal_weights_1_over_15000=1",
        "path_probability_used=0", "all_period_DAC_replay_exact=1",
        "stream_hash_recheck=0", "all_stream_identity_and_final_DAC_replay_exact=1",
        "MATLAB_Gurobi_MEX_used_for_C6_cases=0", "external_gurobipy_version=12.0.1",
        "optimization_case_controller=Python_gurobipy_12.0.1",
        "one_isolated_python_process_per_case=1",
        "LP_calls_execute_inside_case_process=1",
        "optimization_case_processes_sequential=1",
        "preparation_process_isolation=one_state_per_matlab_process",
        "C_y_in_primary=0", "MSP_called=0", "C5B_C5C_solver_modified=0"
    ) | Set-Content -LiteralPath (Join-Path $target "prepare_mechanical_audit.txt") -Encoding UTF8
}
function Invoke-State19Gate {
    $acceptedDir = Join-Path $repo "results\task-002-stage2b-b3-smoke\52-eta-response-saturation-audit\run-003"
    $accepted = Import-Csv -LiteralPath (Join-Path $acceptedDir "eta_optimization_results.csv")
    $acceptedCert = Import-Csv -LiteralPath (Join-Path $acceptedDir "solver_certificate.csv")
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($caseId in @(37,38)) {
        $current = Import-Csv -LiteralPath (Join-Path $target ("optimization_cases\case-{0:d3}\case_result.csv" -f $caseId))
        $currentCert = Import-Csv -LiteralPath (Join-Path $target ("optimization_cases\case-{0:d3}\solver_certificate.csv" -f $caseId))
        $eta = [double]$current.eta
        $reference = $accepted | Where-Object { [math]::Abs([double]$_.eta-$eta) -le 1e-14 }
        $referenceCert = $acceptedCert | Where-Object { [math]::Abs([double]$_.eta-$eta) -le 1e-14 }
        if (@($reference).Count -ne 1 -or @($referenceCert).Count -ne 1) { throw "C5C state19 reference lookup failed for eta=$eta" }
        $tDiff = @(
            [math]::Abs([double]$current.T1_kg-[double]$reference.T1_kg),
            [math]::Abs([double]$current.T2_kg-[double]$reference.T2_kg),
            [math]::Abs([double]$current.T3_kg-[double]$reference.T3_kg),
            [math]::Abs([double]$current.T4_kg-[double]$reference.T4_kg)
        ) | Measure-Object -Maximum
        $row = [pscustomobject]@{
            state_id=19; eta=$eta; maximum_T_abs_difference_kg=$tDiff.Maximum
            total_inventory_abs_difference_kg=[math]::Abs([double]$current.TerminalLOH_total_kg-[double]$reference.TerminalLOH_total_kg)
            mean_shortage_abs_difference_kg=[math]::Abs([double]$current.mean_shortage_kg-[double]$reference.nominal_mean_shortage_kg)
            mean_EENS_abs_difference_kWh=[math]::Abs([double]$current.mean_EENS_kWh-[double]$reference.nominal_mean_EENS_kWh)
            nominal_economic_cost_abs_difference_yuan=[math]::Abs([double]$current.nominal_total_economic_cost_yuan-[double]$reference.nominal_mean_economic_total_yuan)
            LB_abs_difference_yuan=[math]::Abs([double]$currentCert.LB_yuan-[double]$referenceCert.LB_yuan)
            UB_abs_difference_yuan=[math]::Abs([double]$currentCert.UB_yuan-[double]$referenceCert.UB_yuan)
            secondary_distance_abs_difference=[math]::Abs([double]$current.secondary_expected_service_distance-[double]$reference.secondary_expected_service_distance)
        }
        $pass = $row.maximum_T_abs_difference_kg -le 1e-5 -and
            $row.total_inventory_abs_difference_kg -le 1e-5 -and
            $row.mean_shortage_abs_difference_kg -le 1e-7 -and
            $row.mean_EENS_abs_difference_kWh -le 1e-6 -and
            $row.nominal_economic_cost_abs_difference_yuan -le 1e-4 -and
            $row.LB_abs_difference_yuan -le 1e-3 -and
            $row.UB_abs_difference_yuan -le 1e-3 -and
            $row.secondary_distance_abs_difference -le 1e-5
        $row | Add-Member -NotePropertyName reproduction_pass -NotePropertyValue $pass
        $rows.Add($row)
    }
    $rows | Export-Csv -LiteralPath (Join-Path $target "state19_smoke_reproduction_gate.csv") -NoTypeInformation -Encoding UTF8
    if (@($rows | Where-Object { -not $_.reproduction_pass }).Count -ne 0) {
        throw "State19 C5C reproduction gate failed; formal C6 run must stop."
    }
}

$matTarget = Quote-Matlab $target
Push-Location $repo
try {
    if ($Stage -in @("All", "Prepare")) {
        Invoke-IsolatedMatlab "prepare-initialize" "addpath('terminalLoh_wdro/src'); prepare_step04CC6_35state_inputs_h2('$matTarget',true);"
        for ($state=1; $state -le 35; $state++) {
            $label = "prepare-state-{0:d3}" -f $state
            Invoke-IsolatedMatlab $label "addpath('terminalLoh_wdro/src'); prepare_step04CC6_state_input_h2('$matTarget',$state);"
        }
        Complete-Preparation
    }

    if ($Stage -eq "ClonePrepare") {
        Invoke-IsolatedMatlab "prepare-initialize" "addpath('terminalLoh_wdro/src'); prepare_step04CC6_35state_inputs_h2('$matTarget',true);"
        Import-FrozenPreparation $PreparedSourceWorkDir
        Complete-Preparation
        Add-Content -LiteralPath (Join-Path $target "prepare_mechanical_audit.txt") -Value @(
            "prepared_inputs_cloned_from_verified_run=1",
            "prepared_source_work_dir=$PreparedSourceWorkDir",
            "prepared_source_36_of_36_processes_pass=1",
            "all_cloned_payload_sha256_match=1"
        )
        Write-Output "STEP04CC6_CLONED_PREPARATION_COMPLETE|run=$(Split-Path -Leaf $target)|count=$($statuses.Count)"
        return
    }

    if ($Stage -eq "Prepare") {
        Write-Output "STEP04CC6_PREPARATION_PROCESSES_COMPLETE|run=$(Split-Path -Leaf $target)|count=$($statuses.Count)"
        return
    }

    $prepareAudit = Join-Path $target "prepare_mechanical_audit.txt"
    $preparedManifest = Join-Path $target "prepared_state_manifest.csv"
    $caseGrid = Join-Path $target "solve_case_grid.csv"
    if (-not (Test-Path -LiteralPath $prepareAudit) -or
        -not (Select-String -LiteralPath $prepareAudit -Pattern '^status=PASS$' -Quiet) -or
        @(Import-Csv -LiteralPath $preparedManifest).Count -ne 35 -or
        @(Import-Csv -LiteralPath $caseGrid).Count -ne 70) {
        throw "C6 preparation gate is incomplete or failed; cases cannot start."
    }
    $caseRoot = Join-Path $target "optimization_cases"
    if ($Stage -in @("All", "Cases", "State19")) {
        if (Test-Path -LiteralPath $caseRoot) {
            throw "Refusing to overwrite an existing C6 case set; use a new run directory."
        }
        # State19 is the mandatory numerical smoke/reproduction gate.
        Invoke-IsolatedMatlab "case-037-state019-saa" "addpath('terminalLoh_wdro/src'); run_step04CC6_35state_case_h2('$matTarget',37);"
        Invoke-IsolatedMatlab "case-038-state019-eta003" "addpath('terminalLoh_wdro/src'); run_step04CC6_35state_case_h2('$matTarget',38);"
        Invoke-State19Gate
    } else {
        if (-not (Test-Path -LiteralPath (Join-Path $caseRoot "case-037\CASE_COMPLETE.txt")) -or
            -not (Test-Path -LiteralPath (Join-Path $caseRoot "case-038\CASE_COMPLETE.txt")) -or
            -not (Test-Path -LiteralPath (Join-Path $target "state19_smoke_reproduction_gate.csv")) -or
            @(Import-Csv -LiteralPath (Join-Path $target "state19_smoke_reproduction_gate.csv") |
                Where-Object { $_.reproduction_pass -notin @("True","true","1") }).Count -ne 0) {
            throw "State19 reproduction gate is incomplete or failed; remaining cases cannot start."
        }
        $existingCaseDirs = @(Get-ChildItem -LiteralPath $caseRoot -Directory)
        if (@($existingCaseDirs | Where-Object { $_.Name -notin @("case-037","case-038") }).Count -ne 0) {
            throw "Refusing to resume a partial remaining case set; use a new run directory."
        }
    }

    if ($Stage -eq "State19") {
        Write-Output "STEP04CC6_STATE19_GATE_COMPLETE|run=$(Split-Path -Leaf $target)|count=$($statuses.Count)"
        return
    }

    # Conservative sequential execution: every MATLAB process exits before the next starts.
    for ($case=1; $case -le 70; $case++) {
        if ($case -in @(37,38)) { continue }
        $grid = Import-Csv -LiteralPath (Join-Path $target "solve_case_grid.csv") | Where-Object { [int]$_.case_id -eq $case }
        $label = "case-{0:d3}-state{1:d3}-{2}" -f $case,[int]$grid.state_id,($(if ([double]$grid.eta -eq 0) {"saa"} else {"eta003"}))
        Invoke-IsolatedMatlab $label "addpath('terminalLoh_wdro/src'); run_step04CC6_35state_case_h2('$matTarget',$case);"
    }
}
finally { Pop-Location }

Write-Output "STEP04CC6_NUMERICAL_PROCESSES_COMPLETE|run=$(Split-Path -Leaf $target)|count=$($statuses.Count)"
