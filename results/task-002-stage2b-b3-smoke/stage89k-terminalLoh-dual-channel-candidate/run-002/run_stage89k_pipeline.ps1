param(
    [ValidateSet('Audit','Smoke','Formal','Finalize','All')]
    [string]$Stage = 'All'
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
$resultDir = $PSScriptRoot
$largeDir = Join-Path $repo 'terminalLoh_wdro\output\stage89k_terminalLoh_dual_channel_candidate\run-002'
$script = Join-Path $resultDir 'run_stage89k_terminal_loh.py'
$runtime = Join-Path $repo 'terminalLoh_wdro\output\step04cc6_python_runtime\gurobipy-12.0.1'
$logDir = Join-Path $largeDir 'process_logs'
$progress = Join-Path $resultDir 'solve_progress_manifest.csv'

if (-not (Test-Path -LiteralPath (Join-Path $runtime 'gurobipy'))) { throw "Missing frozen gurobipy runtime: $runtime" }
if (-not (Test-Path -LiteralPath $script)) { throw "Missing Stage89K runner: $script" }
New-Item -ItemType Directory -Force -Path $largeDir, $logDir | Out-Null
$priorPythonPath = $env:PYTHONPATH
$env:PYTHONPATH = if ([string]::IsNullOrWhiteSpace($priorPythonPath)) { $runtime } else { $runtime + [IO.Path]::PathSeparator + $priorPythonPath }
$statuses = [System.Collections.Generic.List[object]]::new()
if (Test-Path -LiteralPath $progress) { foreach ($row in @(Import-Csv -LiteralPath $progress)) { $statuses.Add($row) } }

function Next-Log([string]$Label) {
    for ($attempt = 1; $attempt -le 999; $attempt++) {
        $candidate = Join-Path $logDir ("{0}-attempt-{1:d3}.txt" -f $Label, $attempt)
        if (-not (Test-Path -LiteralPath $candidate)) { return $candidate }
    }
    throw "Too many log attempts for $Label"
}

function Invoke-Stage89K([string]$Label, [string[]]$Arguments) {
    $log = Next-Log $Label
    $started = Get-Date
    $prior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & python $script @Arguments *> $log
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prior
    $ended = Get-Date
    $statuses.Add([pscustomobject]@{
        process_label=$Label; exit_code=$code; started_at=$started.ToString('o'); ended_at=$ended.ToString('o')
        runtime_sec=($ended-$started).TotalSeconds; log_path=$log; pass=($code -eq 0)
    })
    $statuses | Export-Csv -LiteralPath $progress -NoTypeInformation -Encoding UTF8
    if ($code -ne 0) {
        Get-Content -LiteralPath $log -Tail 80
        throw "Stage89K process failed: $Label (exit $code)"
    }
    Get-Content -LiteralPath $log -Tail 5
}

function Common-Args() {
    return @('--repo',$repo,'--result-dir',$resultDir,'--large-dir',$largeDir)
}

Push-Location $repo
try {
    if ($Stage -in @('Audit','All')) {
        Invoke-Stage89K 'audit-input' (@('audit-input') + (Common-Args))
        if ($Stage -eq 'Audit') { return }
    }

    if ($Stage -in @('Smoke','All')) {
        foreach ($state in @(4,25,32)) {
            foreach ($mode in @('SAA','DRO')) {
                $complete = Join-Path $largeDir ("smoke_cases\{0}\state-{1:d3}\CASE_COMPLETE.txt" -f $mode.ToLowerInvariant(), $state)
                if (Test-Path -LiteralPath $complete) { continue }
                Invoke-Stage89K ("smoke-{0}-state-{1:d3}" -f $mode.ToLowerInvariant(),$state) (@('case') + (Common-Args) + @('--phase','smoke','--state',[string]$state,'--mode',$mode))
            }
        }
        if ($Stage -eq 'Smoke') { return }
    }

    if ($Stage -in @('Formal','All')) {
        foreach ($state in 1..35) {
            foreach ($mode in @('SAA','DRO')) {
                $complete = Join-Path $largeDir ("formal_cases\{0}\state-{1:d3}\CASE_COMPLETE.txt" -f $mode.ToLowerInvariant(), $state)
                if (Test-Path -LiteralPath $complete) { continue }
                Invoke-Stage89K ("formal-{0}-state-{1:d3}" -f $mode.ToLowerInvariant(),$state) (@('case') + (Common-Args) + @('--phase','formal','--state',[string]$state,'--mode',$mode))
            }
        }
        if ($Stage -eq 'Formal') { return }
    }

    if ($Stage -in @('Finalize','All')) {
        Invoke-Stage89K 'finalize' (@('finalize') + (Common-Args))
    }
}
finally {
    Pop-Location
    $env:PYTHONPATH = $priorPythonPath
}
