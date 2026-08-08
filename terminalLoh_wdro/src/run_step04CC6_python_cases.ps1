param(
    [Parameter(Mandatory = $true)]
    [string]$WorkDir,
    [ValidateSet("State19", "Remaining")]
    [string]$Stage = "State19"
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$target = Join-Path $repo $WorkDir
$logs = Join-Path $target "process_logs"
$statusPath = Join-Path $target "solve_progress_manifest.csv"
$pythonExe = (Get-Command python -ErrorAction Stop).Source
$gurobiPath = Join-Path $repo "terminalLoh_wdro\output\step04cc6_python_runtime\gurobipy-12.0.1"
$caseScript = Join-Path $PSScriptRoot "run_step04CC6_35state_case.py"

if (-not (Test-Path -LiteralPath (Join-Path $gurobiPath "gurobipy"))) {
    throw "Missing local C6 gurobipy 12.0.1 runtime: $gurobiPath"
}
if (-not (Test-Path -LiteralPath $target)) { throw "C6 work directory does not exist: $target" }
if (-not (Test-Path -LiteralPath $logs)) { throw "C6 process log directory is missing: $logs" }
if (-not (Test-Path -LiteralPath $caseScript)) { throw "C6 Python case solver is missing: $caseScript" }

$prepareAudit = Join-Path $target "prepare_mechanical_audit.txt"
$preparedManifest = Join-Path $target "prepared_state_manifest.csv"
$caseGridPath = Join-Path $target "solve_case_grid.csv"
if (-not (Test-Path -LiteralPath $prepareAudit) -or
    -not (Select-String -LiteralPath $prepareAudit -Pattern '^status=PASS$' -Quiet) -or
    @(Import-Csv -LiteralPath $preparedManifest).Count -ne 35 -or
    @(Import-Csv -LiteralPath $caseGridPath).Count -ne 70) {
    throw "C6 preparation gate is incomplete or failed"
}

$statuses = New-Object System.Collections.Generic.List[object]
if (Test-Path -LiteralPath $statusPath) {
    foreach ($prior in @(Import-Csv -LiteralPath $statusPath)) { $statuses.Add($prior) }
}

function Invoke-IsolatedPythonCase {
    param([int]$CaseId)
    $gridRow = @(Import-Csv -LiteralPath $caseGridPath | Where-Object { [int]$_.case_id -eq $CaseId })
    if ($gridRow.Count -ne 1) { throw "C6 case grid lookup failed for case $CaseId" }
    $suffix = if ([double]$gridRow[0].eta -eq 0) { "saa" } else { "eta003" }
    $label = "case-{0:d3}-state{1:d3}-{2}" -f $CaseId,[int]$gridRow[0].state_id,$suffix
    $log = Join-Path $logs ($label + ".txt")
    if (Test-Path -LiteralPath $log) { throw "Refusing to overwrite C6 process log: $log" }
    $started = Get-Date
    $previousPythonPath = $env:PYTHONPATH
    $env:PYTHONPATH = if ([string]::IsNullOrWhiteSpace($previousPythonPath)) {
        $gurobiPath
    } else {
        $gurobiPath + [IO.Path]::PathSeparator + $previousPythonPath
    }
    $oldErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & $pythonExe $caseScript --work-dir $target --case-id $CaseId *> $log
    $code = $LASTEXITCODE
    $ErrorActionPreference = $oldErrorActionPreference
    $env:PYTHONPATH = $previousPythonPath
    $ended = Get-Date
    $statuses.Add([pscustomobject]@{
        process_label=$label; process_type="PYTHON"; exit_code=$code
        started_at=$started.ToString("o"); ended_at=$ended.ToString("o")
        runtime_sec=($ended-$started).TotalSeconds; log_path=$log; pass=($code -eq 0)
    })
    $statuses | Export-Csv -LiteralPath $statusPath -NoTypeInformation -Encoding UTF8
    if ($code -ne 0) { throw "Python process failed: $label (exit $code)" }
    $caseDir = Join-Path $target ("optimization_cases\case-{0:d3}" -f $CaseId)
    if (-not (Test-Path -LiteralPath (Join-Path $caseDir "CASE_COMPLETE.txt")) -or
        @(Import-Csv -LiteralPath (Join-Path $caseDir "solver_certificate.csv") |
            Where-Object { $_.certificate_pass -notin @("True","true","1") }).Count -ne 0) {
        throw "Python case completion/certificate gate failed: $label"
    }
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
        $reference = @($accepted | Where-Object { [math]::Abs([double]$_.eta-$eta) -le 1e-14 })
        $referenceCert = @($acceptedCert | Where-Object { [math]::Abs([double]$_.eta-$eta) -le 1e-14 })
        if ($reference.Count -ne 1 -or $referenceCert.Count -ne 1) { throw "C5C state19 reference lookup failed for eta=$eta" }
        $tDiff = @(
            [math]::Abs([double]$current.T1_kg-[double]$reference[0].T1_kg),
            [math]::Abs([double]$current.T2_kg-[double]$reference[0].T2_kg),
            [math]::Abs([double]$current.T3_kg-[double]$reference[0].T3_kg),
            [math]::Abs([double]$current.T4_kg-[double]$reference[0].T4_kg)
        ) | Measure-Object -Maximum
        $audit = [pscustomobject]@{
            state_id=19; eta=$eta; maximum_T_abs_difference_kg=$tDiff.Maximum
            total_inventory_abs_difference_kg=[math]::Abs([double]$current.TerminalLOH_total_kg-[double]$reference[0].TerminalLOH_total_kg)
            mean_shortage_abs_difference_kg=[math]::Abs([double]$current.mean_shortage_kg-[double]$reference[0].nominal_mean_shortage_kg)
            mean_EENS_abs_difference_kWh=[math]::Abs([double]$current.mean_EENS_kWh-[double]$reference[0].nominal_mean_EENS_kWh)
            nominal_economic_cost_abs_difference_yuan=[math]::Abs([double]$current.nominal_total_economic_cost_yuan-[double]$reference[0].nominal_mean_economic_total_yuan)
            LB_abs_difference_yuan=[math]::Abs([double]$currentCert.LB_yuan-[double]$referenceCert[0].LB_yuan)
            UB_abs_difference_yuan=[math]::Abs([double]$currentCert.UB_yuan-[double]$referenceCert[0].UB_yuan)
            secondary_distance_abs_difference=[math]::Abs([double]$current.secondary_expected_service_distance-[double]$reference[0].secondary_expected_service_distance)
        }
        $pass = $audit.maximum_T_abs_difference_kg -le 1e-5 -and
            $audit.total_inventory_abs_difference_kg -le 1e-5 -and
            $audit.mean_shortage_abs_difference_kg -le 1e-7 -and
            $audit.mean_EENS_abs_difference_kWh -le 1e-6 -and
            $audit.nominal_economic_cost_abs_difference_yuan -le 1e-4 -and
            $audit.LB_abs_difference_yuan -le 1e-3 -and
            $audit.UB_abs_difference_yuan -le 1e-3 -and
            $audit.secondary_distance_abs_difference -le 1e-5
        $audit | Add-Member -NotePropertyName reproduction_pass -NotePropertyValue $pass
        $rows.Add($audit)
    }
    $rows | Export-Csv -LiteralPath (Join-Path $target "state19_smoke_reproduction_gate.csv") -NoTypeInformation -Encoding UTF8
    if (@($rows | Where-Object { -not $_.reproduction_pass }).Count -ne 0) {
        throw "State19 C5C reproduction gate failed"
    }
}

$caseRoot = Join-Path $target "optimization_cases"
if ($Stage -eq "State19") {
    if (Test-Path -LiteralPath $caseRoot) { throw "Refusing to overwrite an existing C6 case set" }
    Invoke-IsolatedPythonCase 37
    Invoke-IsolatedPythonCase 38
    Invoke-State19Gate
    Write-Output "STEP04CC6_PYTHON_STATE19_GATE_COMPLETE|run=$(Split-Path -Leaf $target)"
    exit 0
}

if (-not (Test-Path -LiteralPath (Join-Path $caseRoot "case-037\CASE_COMPLETE.txt")) -or
    -not (Test-Path -LiteralPath (Join-Path $caseRoot "case-038\CASE_COMPLETE.txt")) -or
    -not (Test-Path -LiteralPath (Join-Path $target "state19_smoke_reproduction_gate.csv")) -or
    @(Import-Csv -LiteralPath (Join-Path $target "state19_smoke_reproduction_gate.csv") |
        Where-Object { $_.reproduction_pass -notin @("True","true","1") }).Count -ne 0) {
    throw "State19 reproduction gate is incomplete or failed"
}
$existing = @(Get-ChildItem -LiteralPath $caseRoot -Directory)
if (@($existing | Where-Object { $_.Name -notin @("case-037","case-038") }).Count -ne 0) {
    throw "Refusing to resume a partial remaining case set; use a new run directory"
}
for ($caseId=1; $caseId -le 70; $caseId++) {
    if ($caseId -in @(37,38)) { continue }
    Invoke-IsolatedPythonCase $caseId
}
Write-Output "STEP04CC6_PYTHON_NUMERICAL_PROCESSES_COMPLETE|run=$(Split-Path -Leaf $target)|cases=70"
