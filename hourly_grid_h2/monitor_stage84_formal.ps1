param([string]$RunId = 'run-001')
$repo = Split-Path -Parent $PSScriptRoot
$runDir = Join-Path $repo "results\task-002-stage2b-b3-smoke\84-hourly-grid-formal-training-oos\$RunId"
$status = Join-Path $runDir 'RUNNING_STATUS.txt'
$launch = Get-ChildItem -LiteralPath (Split-Path -Parent $runDir) -Filter "$RunId-launch-record*.txt" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
$pidValue = $null
if (Test-Path -LiteralPath $status) {
    $line = Get-Content -LiteralPath $status | Where-Object { $_ -like 'MATLAB_PID=*' } | Select-Object -First 1
    if ($line) { $pidValue = [int]($line -replace '^MATLAB_PID=','') }
} elseif ($launch) {
    $line = Get-Content -LiteralPath $launch.FullName | Where-Object { $_ -like 'START_PROCESS_PID=*' } | Select-Object -First 1
    if ($line) { $pidValue = [int]($line -replace '^START_PROCESS_PID=','') }
}
"CHECK_TIME=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
"PROCESS_ALIVE=$([bool]($pidValue -and (Get-Process -Id $pidValue -ErrorAction SilentlyContinue)))"
if (Test-Path -LiteralPath $status) { Get-Content -LiteralPath $status }
$trace = Get-ChildItem -LiteralPath $runDir -Filter training_trace.csv -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($trace) { 'TRACE_TAIL='; Get-Content -LiteralPath $trace.FullName -Tail 4 }
$diary = Join-Path $runDir 'logs\stage84_matlab_diary.txt'
if (Test-Path -LiteralPath $diary) { 'DIARY_TAIL='; Get-Content -LiteralPath $diary -Tail 80 }
$critical = @('ERROR','infeasible','unbounded','NaN','Gurobi error','checkpoint failed','balance violation','voltage violation','branch violation','dimension error')
if (Test-Path -LiteralPath $diary) {
    $tail = Get-Content -LiteralPath $diary -Tail 100
    "CRITICAL_MATCHES=$((Select-String -InputObject $tail -Pattern $critical -SimpleMatch).Count)"
}
$drive = Get-PSDrive -Name ([IO.Path]::GetPathRoot($repo).Substring(0,1))
"FREE_GB=$([math]::Round($drive.Free/1GB,2))"
