param(
    [string]$WorkDir = "results/task-002-stage2b-b3-smoke/52-eta-response-saturation-audit/run-001"
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$target = Join-Path $repo $WorkDir
if (Test-Path -LiteralPath $target) { throw "Refusing to overwrite existing C5C run directory: $target" }
New-Item -ItemType Directory -Path $target | Out-Null
$logs = Join-Path $target "process_logs"
New-Item -ItemType Directory -Path $logs | Out-Null
$statuses = New-Object System.Collections.Generic.List[object]

function Invoke-IsolatedMatlab {
    param([string]$Label, [string]$Expression)
    $log = Join-Path $logs ($Label + ".txt")
    $started = Get-Date
    & matlab -batch $Expression *> $log
    $code = $LASTEXITCODE
    $ended = Get-Date
    $statuses.Add([pscustomobject]@{
        process_label=$Label; process_type="MATLAB"; exit_code=$code
        started_at=$started.ToString("o"); ended_at=$ended.ToString("o")
        runtime_sec=($ended-$started).TotalSeconds; log_path=$log; pass=($code -eq 0)
    })
    $statuses | Export-Csv -LiteralPath (Join-Path $target "process_status.csv") -NoTypeInformation -Encoding UTF8
    if ($code -ne 0) { throw "MATLAB process failed: $Label (exit $code)" }
}
function Quote-Matlab([string]$Value) { return $Value.Replace("'", "''").Replace("\", "/") }

$matTarget = Quote-Matlab $target
Push-Location $repo
try {
    Invoke-IsolatedMatlab "prepare" "addpath('terminalLoh_wdro/src'); prepare_step04CC5C_eta_response_inputs_h2('$matTarget');"
    for ($case=1; $case -le 6; $case++) {
        Invoke-IsolatedMatlab ("opt-{0:d3}" -f $case) "addpath('terminalLoh_wdro/src'); run_step04CC5C_eta_optimization_case_h2('$matTarget',$case);"
    }
    for ($case=1; $case -le 11; $case++) {
        Invoke-IsolatedMatlab ("validation-{0:d3}" -f $case) "addpath('terminalLoh_wdro/src'); run_step04CC5C_fixed_T_validation_case_h2('$matTarget',$case);"
    }
    $pyStarted = Get-Date
    $pyLog = Join-Path $logs "finalize.txt"
    & python terminalLoh_wdro/src/finalize_step04CC5C_eta_response.py --work-dir $target *> $pyLog
    $pyCode = $LASTEXITCODE
    $pyEnded = Get-Date
    $statuses.Add([pscustomobject]@{
        process_label="finalize"; process_type="PYTHON"; exit_code=$pyCode
        started_at=$pyStarted.ToString("o"); ended_at=$pyEnded.ToString("o")
        runtime_sec=($pyEnded-$pyStarted).TotalSeconds; log_path=$pyLog; pass=($pyCode -eq 0)
    })
    $statuses | Export-Csv -LiteralPath (Join-Path $target "process_status.csv") -NoTypeInformation -Encoding UTF8
    if ($pyCode -ne 0) { throw "Python finalizer failed (exit $pyCode)" }
}
finally { Pop-Location }

Write-Output "STEP04CC5C_NUMERICAL_PROCESSES_COMPLETE|run=$(Split-Path -Leaf $target)|count=$($statuses.Count)"
