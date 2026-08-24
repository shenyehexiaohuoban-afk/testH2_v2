param([string]$RunId='run-003')

$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$matlab='D:\Program Files\MATLAB\R2022a\bin\matlab.exe'
$runRoot=Join-Path $repo 'results\task-002-stage2b-b3-smoke\stage89q-penalty1000-vs1500-long-training'
$runDir=Join-Path $runRoot $RunId
$checkpoint=Join-Path $repo 'hourly_grid_h2\output\stage89q_penalty1000_vs1500_long_training\run-002\penalty1000\checkpoint\checkpoint_final.mat'
$summaryPath=Join-Path $runRoot 'run-002\02_training\penalty1000\training_summary.csv'
$finishPath=Join-Path $runRoot 'run-002\02_training\penalty1000\TRAINING_FINISHED.txt'
$statusPath=Join-Path $runRoot 'run-002\RUNNING_STATUS.txt'
$auditPath=Join-Path $runDir 'run003_checkpoint_recovery_audit.csv'

function Get-LiveSolverProcesses {
    $result=@()
    Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^(MATLAB|MATLABWorker|mps_worker|gurobi|gurobi_cl|grb.*)$' } | ForEach-Object {
        $hasExited=$true;$threads=0;$handles=0;$ws=0;$vm=0
        try{$hasExited=$_.HasExited}catch{};try{$threads=@($_.Threads).Count}catch{};try{$handles=$_.HandleCount}catch{};try{$ws=$_.WorkingSet64}catch{};try{$vm=$_.VirtualMemorySize64}catch{}
        if((-not $hasExited) -and ($threads -gt 0 -or $handles -gt 0 -or $ws -gt 0 -or $vm -gt 0)){$result += $_}
    }
    return @($result)
}

function Add-AuditRow([array]$Rows,[string]$Check,[string]$Observed,[string]$Expected,[bool]$Pass,[string]$Evidence) {
    return @($Rows)+[pscustomobject]@{check=$Check;observed=$Observed;expected=$Expected;pass=$Pass;evidence=$Evidence}
}

if(Test-Path -LiteralPath $runDir){throw "Refusing to overwrite $runDir"}
if(@(Get-LiveSolverProcesses).Count -ne 0){throw 'LIVE solver process count is not zero before recovery audit.'}
New-Item -ItemType Directory -Path $runDir,(Join-Path $runDir 'logs') -Force|Out-Null

$stale=@(Get-Process -Name MATLAB -ErrorAction SilentlyContinue|Where-Object{$_.HasExited})
$preflight=@()
foreach($process in $stale){$preflight += [pscustomobject]@{pid=$process.Id;classification='EXITED_STALE_PROCESS_OBJECT';has_exited=$process.HasExited;threads=@($process.Threads).Count;working_set_bytes=$process.WorkingSet64;virtual_memory_bytes=$process.VirtualMemorySize64;handle_count=$process.HandleCount}}
if($preflight.Count -eq 0){$preflight += [pscustomobject]@{pid='';classification='NO_STALE_MATLAB_OBJECT';has_exited=$true;threads=0;working_set_bytes=0;virtual_memory_bytes=0;handle_count=0}}
$preflight|Export-Csv -LiteralPath (Join-Path $runDir 'live_process_preflight.csv') -NoTypeInformation -Encoding UTF8

$summary=@(Import-Csv -LiteralPath $summaryPath);$checkpointInfo=Get-Item -LiteralPath $checkpoint
$finishText=Get-Content -Raw -LiteralPath $finishPath;$statusText=Get-Content -Raw -LiteralPath $statusPath
$saveReturned=$summary.Count -eq 1 -and [int]$summary[0].completed_iterations -eq 346 -and [long]$summary[0].checkpoint_bytes -eq $checkpointInfo.Length -and $finishText.Contains('Arm-A_TRAINING_FINISHED=true') -and $statusText.Contains('PHASE=TRAIN_FINISHED') -and $checkpointInfo.LastWriteTime -le (Get-Item $summaryPath).LastWriteTime -and $checkpointInfo.LastWriteTime -le (Get-Item $finishPath).LastWriteTime
if(-not $saveReturned){throw 'Run-002 evidence does not prove checkpoint save returned before teardown.'}

$sha=(Get-FileHash -Algorithm SHA256 -LiteralPath $checkpoint).Hash.ToLowerInvariant()
$env:STAGE89Q_RECOVERY_CHECKPOINT=$checkpoint;$env:STAGE89Q_RECOVERY_SHA256=$sha;$env:STAGE89Q_RECOVERY_AUDIT_FILE=$auditPath
$driver="addpath('fa_msp/current_hourly_stage89_adopted/launcher'); run_stage89q_run002_checkpoint_recovery_audit_h2"
$log=Join-Path $runDir 'logs\checkpoint_recovery_matlab.log'
try {
    & $matlab -nojvm -nodesktop -nosplash -logfile $log -batch $driver
    $exitCode=$LASTEXITCODE
} finally {
    Remove-Item Env:STAGE89Q_RECOVERY_CHECKPOINT,Env:STAGE89Q_RECOVERY_SHA256,Env:STAGE89Q_RECOVERY_AUDIT_FILE -ErrorAction SilentlyContinue
}

$liveAfter=@(Get-LiveSolverProcesses);$rows=if(Test-Path $auditPath){@(Import-Csv -LiteralPath $auditPath)}else{@()}
$rows=Add-AuditRow $rows 'run002_save_returned_before_teardown' ([string]$saveReturned) 'true' $saveReturned 'checkpoint timestamp precedes summary and finish marker; TRAIN_FINISHED status exists'
$rows=Add-AuditRow $rows 'checkpoint_size_bytes' ([string]$checkpointInfo.Length) '332032355' ($checkpointInfo.Length -eq 332032355) 'external filesystem metadata'
$rows=Add-AuditRow $rows 'checkpoint_sha256' $sha '64 lowercase hex' ($sha -match '^[0-9a-f]{64}$') 'external PowerShell Get-FileHash before MATLAB load'
$rows=Add-AuditRow $rows 'matlab_exit_code' ([string]$exitCode) '0' ($exitCode -eq 0) 'fresh recovery MATLAB process'
$rows=Add-AuditRow $rows 'live_solver_process_count_after_recovery' ([string]$liveAfter.Count) '0' ($liveAfter.Count -eq 0) 'EXITED_STALE_PROCESS_OBJECT excluded by explicit live-resource gate'
$pass=$exitCode -eq 0 -and $liveAfter.Count -eq 0 -and $rows.Count -gt 5 -and @($rows|Where-Object{$_.pass.ToString().ToLowerInvariant() -notin @('true','1')}).Count -eq 0
$rows=Add-AuditRow $rows 'RUN002_PENALTY1000_CHECKPOINT' $(if($pass){'ACCEPTED_FOR_TESTING'}else{'REJECTED'}) 'ACCEPTED_FOR_TESTING' $pass 'post-restart validated recovery; not a run-002 clean-exit claim'
$rows|Export-Csv -LiteralPath $auditPath -NoTypeInformation -Encoding UTF8
if(-not $pass){throw "RUN002_PENALTY1000_CHECKPOINT = REJECTED; audit=$auditPath"}
'RUN002_PENALTY1000_CHECKPOINT=ACCEPTED_FOR_TESTING'|Set-Content -LiteralPath (Join-Path $runDir 'CHECKPOINT_RECOVERY_ACCEPTED.marker') -Encoding ASCII
[pscustomobject]@{checkpoint_file=$checkpoint;size_bytes=$checkpointInfo.Length;sha256=$sha;source_head='cfa789f262b323de1775e5e2376a2d23978753ef';classification='post-restart validated recovery';accepted_for='TESTING_ONLY';warm_start_allowed=$false}|Export-Csv -LiteralPath (Join-Path $runDir 'checkpoint_recovery_manifest.csv') -NoTypeInformation -Encoding UTF8
