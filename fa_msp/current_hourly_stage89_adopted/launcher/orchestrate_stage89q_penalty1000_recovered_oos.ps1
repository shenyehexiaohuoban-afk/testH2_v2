param([string]$RunId='run-003')

$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$matlab='D:\Program Files\MATLAB\R2022a\bin\matlab.exe'
$runDir=Join-Path $repo "results\task-002-stage2b-b3-smoke\stage89q-penalty1000-vs1500-long-training\$RunId"
$largeDir=Join-Path $repo "hourly_grid_h2\output\stage89q_penalty1000_vs1500_long_training\$RunId"
$checkpoint=Join-Path $repo 'hourly_grid_h2\output\stage89q_penalty1000_vs1500_long_training\run-002\penalty1000\checkpoint\checkpoint_final.mat'
$manifest=Join-Path $runDir 'checkpoint_recovery_manifest.csv'
$marker=Join-Path $runDir 'CHECKPOINT_RECOVERY_ACCEPTED.marker'
$driver="addpath('fa_msp/current_hourly_stage89_adopted/launcher'); run_stage89q_penalty1000_vs1500_5h_hourly_h2"

function Get-LiveSolverProcesses {
    $result=@()
    Get-Process -ErrorAction SilentlyContinue|Where-Object{$_.ProcessName -match '^(MATLAB|MATLABWorker|mps_worker|gurobi|gurobi_cl|grb.*)$'}|ForEach-Object{
        $hasExited=$true;$threads=0;$handles=0;$ws=0;$vm=0
        try{$hasExited=$_.HasExited}catch{};try{$threads=@($_.Threads).Count}catch{};try{$handles=$_.HandleCount}catch{};try{$ws=$_.WorkingSet64}catch{};try{$vm=$_.VirtualMemorySize64}catch{}
        if((-not $hasExited)-and($threads-gt 0-or$handles-gt 0-or$ws-gt 0-or$vm-gt 0)){$result+=$_}
    }
    return @($result)
}
function Assert-LiveZero([string]$Boundary){$live=@(Get-LiveSolverProcesses);if($live.Count-ne 0){$live|Format-Table -AutoSize;throw "LIVE solver process count is not zero at $Boundary"}}
function Invoke-Phase([string]$Phase,[string]$Arm='',[string]$Sha=''){
    Assert-LiveZero "before $Phase"
    $env:STAGE89Q_RUN_ID=$RunId;$env:STAGE89Q_FROZEN_COMMIT='cfa789f262b323de1775e5e2376a2d23978753ef';$env:STAGE89Q_PHASE=$Phase;$env:STAGE89Q_ARM=$Arm;$env:STAGE89Q_CHECKPOINT_SHA256=$Sha;$env:STAGE89Q_RECOVERED_CHECKPOINT=$checkpoint
    $log=Join-Path $runDir "logs\$($Phase.ToLowerInvariant())-matlab.log"
    try{& $matlab -nojvm -nodesktop -nosplash -logfile $log -batch $driver;$code=$LASTEXITCODE}finally{Remove-Item Env:STAGE89Q_RUN_ID,Env:STAGE89Q_FROZEN_COMMIT,Env:STAGE89Q_PHASE,Env:STAGE89Q_ARM,Env:STAGE89Q_CHECKPOINT_SHA256,Env:STAGE89Q_RECOVERED_CHECKPOINT -ErrorAction SilentlyContinue}
    if($code-ne 0){throw "MATLAB phase $Phase failed with exit code $code; log=$log"}
    Assert-LiveZero "after $Phase"
}

if(-not(Test-Path $marker)-or-not((Get-Content -Raw $marker).Contains('ACCEPTED_FOR_TESTING'))){throw 'Checkpoint recovery is not accepted.'}
$identity=@(Import-Csv $manifest);if($identity.Count-ne 1-or$identity[0].accepted_for-ne'TESTING_ONLY'){throw 'Checkpoint recovery manifest is invalid.'}
$sha=(Get-FileHash -Algorithm SHA256 $checkpoint).Hash.ToLowerInvariant();if($sha-ne$identity[0].sha256){throw 'Checkpoint SHA changed after recovery audit.'}
Assert-LiveZero 'OOS orchestration start'

$lightDirs=@('03_oos\common','03_oos\penalty1000');foreach($dir in $lightDirs){New-Item -ItemType Directory -Path (Join-Path $runDir $dir) -Force|Out-Null}
$rawDirs=@('common','penalty1000\hourly_site','penalty1000\htt_od','penalty1000\grid_hourly','penalty1000\stage7_inventory','penalty1000\path_summary');foreach($dir in $rawDirs){New-Item -ItemType Directory -Path (Join-Path $largeDir $dir) -Force|Out-Null}
if(Test-Path (Join-Path $runDir '03_oos\common\BANK_LOCKED.txt')){throw 'OOS bank phase already exists; refusing to overwrite.'}
Invoke-Phase 'BANK_SINGLE'
Invoke-Phase 'OOS_RECOVERED' 'P1000' $sha
$after=(Get-FileHash -Algorithm SHA256 $checkpoint).Hash.ToLowerInvariant();if($after-ne$sha){throw 'Checkpoint changed after OOS.'}
'PENALTY1000_RAW_OOS_COMPLETE=true'|Set-Content -LiteralPath (Join-Path $runDir 'PENALTY1000_RAW_OOS_COMPLETE.marker') -Encoding ASCII
[pscustomobject]@{checkpoint_sha256_before=$sha;checkpoint_sha256_after=$after;checkpoint_unchanged=($sha-eq$after);live_solver_process_count_after=0;penalty1500_started=$false;pass=$true}|Export-Csv -LiteralPath (Join-Path $runDir '03_oos\penalty1000\external_oos_lifecycle_audit.csv') -NoTypeInformation -Encoding UTF8
