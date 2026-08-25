param([string]$RunId='run-001',[string]$SourceCommit='')
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$matlab='D:\Program Files\MATLAB\R2022a\bin\matlab.exe'
$resultRoot=Join-Path $repo 'results\task-002-stage2b-b3-smoke\stage90b-base-pmax-fresh-zero-cut-10iter'
$runDir=Join-Path $resultRoot $RunId
$driver="addpath('fa_msp/current_hourly_stage90_candidate/launcher'); run_stage90b_base_pmax_fresh_zero_cut_10iter_h2"
$created=$false
if(-not $SourceCommit){$SourceCommit=(& git -C $repo rev-parse HEAD).Trim()}

function Snapshot {
    $rows=@(Get-CimInstance Win32_Process | Where-Object {$_.Name -match '^(MATLAB|MATLABWindow|gurobi.*)\.exe$'} | ForEach-Object {
        $ws=[int64]$_.WorkingSetSize
        [pscustomobject]@{process_id=$_.ProcessId;name=$_.Name;working_set_bytes=$ws;
            live_resource_gate=(-not [string]::IsNullOrWhiteSpace([string]$_.ExecutablePath) -or
                -not [string]::IsNullOrWhiteSpace([string]$_.CommandLine) -or $ws -gt 1048576)}
    })
    return $rows
}
function Assert-Clean([string]$where) {
    $live=@(Snapshot | Where-Object {$_.live_resource_gate})
    if($live.Count -gt 0){throw ('Live MATLAB/Gurobi process at '+$where+': '+($live.process_id -join ','))}
}
function Save-Snapshot([string]$name) {
    $path=Join-Path $runDir ('01_preflight\process_'+$name+'.csv')
    $rows=@(Snapshot)
    if($rows.Count -eq 0){[pscustomobject]@{process_id='';name='';working_set_bytes=0;live_resource_gate=$false}|Export-Csv $path -NoTypeInformation}
    else{$rows|Export-Csv $path -NoTypeInformation}
}
function Init {
    if(Test-Path $runDir){throw ('Refusing to overwrite '+$runDir)}
    New-Item -ItemType Directory -Force -Path $runDir|Out-Null;$script:created=$true
    foreach($d in @('01_preflight','02_config','03_training','04_terminal_diagnostics','05_stage_site','06_checkpoint','07_reload','08_qa','09_manifest')){New-Item -ItemType Directory -Force -Path (Join-Path $runDir $d)|Out-Null}
    [pscustomobject]@{source_commit=$SourceCommit;candidate='BASE-PMAX-STAGE90B';pmax_kw='[300,200,120,150]';terminal_recourse_mode='TERMINAL_REDISTRIBUTION';K_terminal_kg=160;penalty=1000;seed=20260513;iterations=10;fresh_zero_cuts=$true}|Export-Csv (Join-Path $runDir '01_preflight\executable_config.csv') -NoTypeInformation
}
function Phase([string]$name) {
    Assert-Clean ('before '+$name);Save-Snapshot ('before_'+$name.ToLower())
    $env:STAGE90B_RUN_DIR=$runDir;$env:STAGE90B_PHASE=$name;$env:STAGE90B_SOURCE_COMMIT=$SourceCommit
    $log=Join-Path $runDir ('01_preflight\'+$name.ToLower()+'_native_stdout.log')
    & $matlab -nojvm -nodesktop -nosplash -logfile $log -batch $driver
    $exit=$LASTEXITCODE
    [pscustomobject]@{phase=$name;exit_code=$exit;log=$log}|Export-Csv (Join-Path $runDir ('01_preflight\phase_'+$name.ToLower()+'.csv')) -NoTypeInformation
    if($exit -ne 0){throw ('MATLAB phase '+$name+' failed; log='+$log)}
    Assert-Clean ('after '+$name);Save-Snapshot ('after_'+$name.ToLower())
}
function Hash-Checkpoint {
    $path=Join-Path $runDir '06_checkpoint\checkpoint_final.mat'
    if(-not(Test-Path $path)){throw 'Checkpoint missing'}
    Assert-Clean 'checkpoint hash'
    $item=Get-Item $path;$sha=(Get-FileHash -Algorithm SHA256 $path).Hash.ToLower()
    [pscustomobject]@{candidate='BASE-PMAX-STAGE90B';path=$path;size_bytes=$item.Length;sha256=$sha;hashed_after_matlab_exit=$true;source_commit=$SourceCommit}|Export-Csv (Join-Path $runDir '06_checkpoint\checkpoint_manifest.csv') -NoTypeInformation
}
function Final-QA {
    $trace=@(Import-Csv (Join-Path $runDir '03_training\training_iteration_trace.csv'))
    $checks=@(
        [pscustomobject]@{check='config_pass';pass=Test-Path (Join-Path $runDir '02_config\CONFIG_PASS.txt')},
        [pscustomobject]@{check='training_pass';pass=Test-Path (Join-Path $runDir '03_training\TRAINING_FINISHED.txt')},
        [pscustomobject]@{check='reload_pass';pass=Test-Path (Join-Path $runDir '07_reload\RELOAD_PASS.txt')},
        [pscustomobject]@{check='exactly_10_iterations';pass=$trace.Count -eq 10},
        [pscustomobject]@{check='cut_growth';pass=(($trace|Where-Object{[int]$_.cuts_added -gt 0}).Count -eq 10)},
        [pscustomobject]@{check='finite_LB';pass=(($trace|Where-Object{[double]$_.LB -ne [double]$_.LB}).Count -eq 0)},
        [pscustomobject]@{check='no_failure_marker';pass=(-not(Test-Path (Join-Path $runDir 'ORCHESTRATOR_FAILURE.txt')))}
    )
    $checks|Export-Csv (Join-Path $runDir '08_qa\stage90b_qa.csv') -NoTypeInformation
    if(($checks|Where-Object{-not $_.pass}).Count -gt 0){throw 'Stage90B QA failed'}
    $files=Get-ChildItem $runDir -Recurse -File|Where-Object{$_.FullName -notmatch '\\06_checkpoint\\checkpoint_final\.mat$'}
    $manifest=@();foreach($f in $files){$manifest += [pscustomobject]@{path=$f.FullName.Substring($repo.Length+1);bytes=$f.Length;sha256=(Get-FileHash -Algorithm SHA256 $f.FullName).Hash.ToLower()}}
    $manifest|Export-Csv (Join-Path $runDir '09_manifest\artifact_manifest.csv') -NoTypeInformation
    Set-Content (Join-Path $runDir 'SMOKE_COMPLETE.txt') ('status=PASS'+[Environment]::NewLine+'source_commit='+$SourceCommit) -Encoding UTF8
}
function Preserve {
    if(-not $created -or -not(Test-Path $runDir)){return}
    $i=1;do{$failed=Join-Path $resultRoot ($RunId+'.failed-'+('{0:d3}'-f $i));$i++}while(Test-Path $failed)
    Move-Item $runDir $failed;Write-Error ('Stage90B failure preserved at '+$failed)
}
try{Init;Save-Snapshot 'initial';Assert-Clean 'initial';Phase 'CONFIG';Phase 'TRAIN';Hash-Checkpoint;Phase 'RELOAD';Final-QA}
catch{$msg=$_ | Out-String;if($created -and(Test-Path $runDir)){$msg|Set-Content (Join-Path $runDir 'ORCHESTRATOR_FAILURE.txt');Save-Snapshot 'failure'};Preserve;throw}
finally{Remove-Item Env:STAGE90B_RUN_DIR,Env:STAGE90B_PHASE,Env:STAGE90B_SOURCE_COMMIT -ErrorAction SilentlyContinue}
