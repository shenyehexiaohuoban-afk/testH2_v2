$ErrorActionPreference = 'Stop'
$packageRoot = (Resolve-Path $PSScriptRoot).Path
$statusRoot = Join-Path $packageRoot 'status'
$logRoot = Join-Path $packageRoot 'logs'
New-Item -ItemType Directory -Force -Path $statusRoot,$logRoot | Out-Null
$watcherLock = Join-Path $statusRoot 'CHAIN_WATCHER.lock'
$watcherLog = Join-Path $logRoot 'chain_watcher.log'

function Log([string]$message) {
    Add-Content -LiteralPath $watcherLog -Value "[$((Get-Date).ToString('o'))] $message" -Encoding UTF8
}

if (Test-Path -LiteralPath $watcherLock) {
    $old = Get-Content -LiteralPath $watcherLock -Raw -ErrorAction SilentlyContinue
    $oldPid = 0
    if ($old -match 'PID=(\d+)') { $oldPid = [int]$Matches[1] }
    if ($oldPid -gt 0 -and (Get-Process -Id $oldPid -ErrorAction SilentlyContinue)) { throw "Chain watcher is already active (PID=$oldPid)." }
    Move-Item -LiteralPath $watcherLock -Destination (Join-Path $statusRoot ("STALE_CHAIN_WATCHER_LOCK_{0}.txt" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))) -Force
}
$lockStream = [System.IO.File]::Open($watcherLock,[System.IO.FileMode]::CreateNew,[System.IO.FileAccess]::ReadWrite,[System.IO.FileShare]::None)
$lockBytes = [System.Text.Encoding]::UTF8.GetBytes("PID=$PID`nSTARTED_AT=$((Get-Date).ToString('o'))`n")
$lockStream.Write($lockBytes,0,$lockBytes.Length); $lockStream.Flush()

try {
    Log "CHAIN_WATCHER_STARTED PID=$PID"
    $deadPolls = 0
    while ($true) {
        $analysisDone = Join-Path $statusRoot 'ANALYSIS_COMPLETED.txt'
        if (Test-Path -LiteralPath $analysisDone) {
            $doneText = Get-Content -LiteralPath $analysisDone -Raw
            if ($doneText -match 'ANALYSIS_STATUS = COMPLETED' -and $doneText -match 'MODE = C') {
                Log 'CHAIN_COMPLETE: Mode C analysis completion marker verified.'
                Set-Content -LiteralPath (Join-Path $statusRoot 'CHAIN_COMPLETED.txt') -Value "CHAIN_STATUS = COMPLETED`nCOMPLETED_AT = $((Get-Date).ToString('o'))" -Encoding UTF8
                break
            }
        }

        # OOS completion is an independent restart point. The OOS evaluator
        # updates CURRENT_STATUS away from the training clean-reload phase, so
        # a restarted watcher must not require the old training status again.
        $oosDone = Join-Path $statusRoot 'OOS_COMPLETED.txt'
        if (Test-Path -LiteralPath $oosDone) {
            $oosText = Get-Content -LiteralPath $oosDone -Raw
            if ($oosText -notmatch 'OOS_STATUS = COMPLETED' -or $oosText -notmatch 'MODE = C' -or $oosText -notmatch 'PATH_COUNT = 10000') {
                throw 'OOS completion marker exists but its identity gate is invalid.'
            }
            Log 'OOS_GATE_PASS; starting/resuming Mode C analysis.'
            & (Join-Path $packageRoot 'START_ANALYSIS.ps1') *>> (Join-Path $logRoot 'chain_analysis.log')
            continue
        }

        $currentStatus = Join-Path $statusRoot 'CURRENT_STATUS.txt'
        $statusText = if (Test-Path -LiteralPath $currentStatus) { Get-Content -LiteralPath $currentStatus -Raw } else { '' }
        if ($statusText -match 'STATUS = FAILED') { throw 'Formal training status is FAILED.' }

        $trainingDone = Join-Path $statusRoot 'TRAINING_COMPLETED.txt'
        $formalReady = $false
        if (Test-Path -LiteralPath $trainingDone) {
            $trainingText = Get-Content -LiteralPath $trainingDone -Raw
            $formalReady = $trainingText -match 'TRAINING_STATUS = COMPLETED' -and $trainingText -match 'MODE = FORMAL' -and $trainingText -match 'CLEAN_RELOAD = PASS' -and $statusText -match 'STATUS = COMPLETED' -and $statusText -match 'PHASE = CLEAN_RELOAD_PASS'
        }

        if ($formalReady) {
            Log 'FORMAL_TRAINING_GATE_PASS; starting Mode C OOS.'
            & (Join-Path $packageRoot 'START_OOS.ps1') *>> (Join-Path $logRoot 'chain_oos.log')
            if (-not (Test-Path -LiteralPath $oosDone)) { throw 'OOS launcher returned without OOS_COMPLETED.txt.' }
            continue
        }

        if ($statusText -match 'STATUS = RUNNING') {
            $matlabPid = 0
            if ($statusText -match 'MATLAB_PID = (\d+)') { $matlabPid = [int]$Matches[1] }
            if ($matlabPid -gt 0 -and (Get-Process -Id $matlabPid -ErrorAction SilentlyContinue)) { $deadPolls = 0 }
            else { $deadPolls++ }
            if ($deadPolls -ge 3) { throw 'Training status is RUNNING but MATLAB process was absent for three consecutive watcher polls.' }
        }
        Start-Sleep -Seconds 60
    }
} catch {
    Log "CHAIN_WATCHER_FAILED: $($_.Exception.ToString())"
    Set-Content -LiteralPath (Join-Path $statusRoot 'CHAIN_WATCHER_FAILED.txt') -Value $_.Exception.ToString() -Encoding UTF8
    throw
} finally {
    if ($lockStream) { $lockStream.Dispose() }
    Remove-Item -LiteralPath $watcherLock -Force -ErrorAction SilentlyContinue
    Log 'CHAIN_WATCHER_EXITED'
}
