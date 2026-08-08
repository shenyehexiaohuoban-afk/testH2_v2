param(
    [Parameter(Mandatory=$true)][string]$WorkDir,
    [Parameter(Mandatory=$true)][ValidateSet("A","B","C","D","E")][string]$Judgment
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$target = Join-Path $repo $WorkDir
if (-not (Test-Path -LiteralPath $target)) { throw "C6 work directory does not exist: $target" }
$statusPath = Join-Path $target "solve_progress_manifest.csv"
if (-not (Test-Path -LiteralPath $statusPath)) { throw "Missing C6 solve progress manifest" }
$statuses = @(Import-Csv -LiteralPath $statusPath)
$caseStatuses = @($statuses | Where-Object { $_.process_label -like "case-*" })
if ($caseStatuses.Count -ne 70 -or $statuses.Count -lt 71) {
    throw "Expected all 70 numerical case processes plus audited preparation before finalization; found $($caseStatuses.Count) cases and $($statuses.Count) total rows"
}
if (@($statuses | Where-Object { [int]$_.exit_code -ne 0 -or $_.pass -notin @("True","true","1") }).Count -ne 0) {
    throw "A numerical C6 process failed; finalization is forbidden"
}
if (@($statuses | Where-Object { $_.process_label -eq "finalize" }).Count -ne 0) {
    throw "Refusing to rerun C6 finalization in the same run directory"
}

$logs = Join-Path $target "process_logs"
$log = Join-Path $logs "finalize.txt"
$started = Get-Date
Push-Location $repo
try {
    & python terminalLoh_wdro/src/finalize_step04CC6_35state.py --work-dir $target --judgment $Judgment *> $log
    $code = $LASTEXITCODE
}
finally { Pop-Location }
$ended = Get-Date
$newRow = [pscustomobject]@{
    process_label="finalize"; process_type="PYTHON"; exit_code=$code
    started_at=$started.ToString("o"); ended_at=$ended.ToString("o")
    runtime_sec=($ended-$started).TotalSeconds; log_path=$log; pass=($code -eq 0)
}
@($statuses + $newRow) | Export-Csv -LiteralPath $statusPath -NoTypeInformation -Encoding UTF8
if ($code -ne 0) { throw "C6 Python finalizer failed (exit $code)" }
Write-Output "STEP04CC6_FINALIZATION_COMPLETE|run=$(Split-Path -Leaf $target)|judgment=$Judgment|process_count=$($statuses.Count+1)"
