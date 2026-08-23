param(
    [string]$RunId = 'run-001',
    [string]$FrozenCommit = '',
    [switch]$SmokeOnly,
    [string]$LogPath = ''
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$matlab = 'D:\Program Files\MATLAB\R2022a\bin\matlab.exe'
$runRoot = Join-Path $repo 'results\task-002-stage2b-b3-smoke\stage89q-penalty1000-vs1500-long-training'
$runDir = Join-Path $runRoot $RunId
$largeDir = Join-Path $repo "hourly_grid_h2\output\stage89q_penalty1000_vs1500_long_training\$RunId"
$driver = "addpath('fa_msp/current_hourly_stage89_adopted/launcher'); run_stage89q_penalty1000_vs1500_5h_hourly_h2"
if (-not $FrozenCommit) { $FrozenCommit = (& git -C $repo rev-parse HEAD).Trim() }
if ($LogPath) { Start-Transcript -LiteralPath $LogPath -Force | Out-Null }

function Assert-NoSolverProcess {
    param([Parameter(Mandatory=$true)][string]$Boundary)
    $active = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^(MATLAB|MATLABWindow|gurobi)' }
    if ($active) { throw "MATLAB/Gurobi already active at $Boundary" }
}

function Invoke-Phase {
    param([Parameter(Mandatory=$true)][string]$Phase,[string]$Arm='',[string]$CheckpointSha='')
    Assert-NoSolverProcess -Boundary "before $Phase $Arm"
    $env:STAGE89Q_RUN_ID = $RunId
    $env:STAGE89Q_FROZEN_COMMIT = $FrozenCommit
    $env:STAGE89Q_PHASE = $Phase
    $env:STAGE89Q_ARM = $Arm
    $env:STAGE89Q_CHECKPOINT_SHA256 = $CheckpointSha
    $suffix = if ($Arm) { "-$($Arm.ToLowerInvariant())" } else { '' }
    $phaseLog = Join-Path $runRoot "$RunId-$($Phase.ToLowerInvariant())$suffix-matlab.log"
    & $matlab -nojvm -nodesktop -nosplash -logfile $phaseLog -batch $driver
    if ($LASTEXITCODE -ne 0) { throw "MATLAB phase $Phase $Arm failed with exit code $LASTEXITCODE; log=$phaseLog" }
    Assert-NoSolverProcess -Boundary "after $Phase $Arm"
}

function Get-CheckpointPath {
    param([Parameter(Mandatory=$true)][int]$Penalty)
    Join-Path $largeDir "penalty$Penalty\checkpoint\checkpoint_final.mat"
}

function Write-TrainingExternalAudit {
    param([Parameter(Mandatory=$true)][string]$Arm,[Parameter(Mandatory=$true)][int]$Penalty)
    Assert-NoSolverProcess -Boundary "checkpoint hash penalty$Penalty"
    $checkpoint = Get-CheckpointPath -Penalty $Penalty
    $shaWatch = [Diagnostics.Stopwatch]::StartNew()
    $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $checkpoint).Hash.ToLowerInvariant()
    $shaWatch.Stop()
    $info = Get-Item -LiteralPath $checkpoint
    $trainDir = Join-Path $runDir "02_training\penalty$Penalty"
    $summary = Import-Csv -LiteralPath (Join-Path $trainDir 'training_summary.csv')
    [pscustomobject]@{
        arm = $Arm; penalty = $Penalty; checkpoint_file = $checkpoint; size_bytes = $info.Length
        sha256 = $sha; external_sha_seconds = $shaWatch.Elapsed.TotalSeconds
        training_duration_seconds = [double]$summary.actual_training_wall_time_s
        iterations = [int]$summary.completed_iterations; source_head = $FrozenCommit
        training_seed = 20260513; save_timestamp = $info.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss zzz')
    } | Export-Csv -LiteralPath (Join-Path $trainDir 'checkpoint_manifest.csv') -NoTypeInformation -Encoding UTF8
    [pscustomobject]@{
        arm = $Arm; training_matlab_exited = $true; matlab_process_count_after_training = 0
        external_sha_completed = $true; checkpoint_loaded_during_training = $false; pass = $true
    } | Export-Csv -LiteralPath (Join-Path $trainDir 'process_lifecycle_audit.csv') -NoTypeInformation -Encoding UTF8

    $progress = Import-Csv -LiteralPath (Join-Path $trainDir 'training_progress.csv')
    $targets = @(3600,7200,10800,14400)
    $snapshots = foreach ($target in $targets) {
        $eligible = @($progress | Where-Object { [double]$_.elapsed_seconds -le $target })
        if ($eligible.Count -eq 0) { $row = $progress[0] } else { $row = $eligible[-1] }
        [pscustomobject]@{wallclock_hour=$target/3600;latest_iteration=$row.iteration;lower_bound=$row.lower_bound;cut_count=$row.cut_count;Stage1_production=$row.stage1_total_production;Stage1_end_inventory=$row.stage1_end_inventory_total;Stage2_end_inventory=$row.stage2_end_inventory_total;Stage3_end_inventory=$row.stage3_end_inventory_total}
    }
    $row = $progress[-1]
    $snapshots += [pscustomobject]@{wallclock_hour=[double]$row.elapsed_seconds/3600;latest_iteration=$row.iteration;lower_bound=$row.lower_bound;cut_count=$row.cut_count;Stage1_production=$row.stage1_total_production;Stage1_end_inventory=$row.stage1_end_inventory_total;Stage2_end_inventory=$row.stage2_end_inventory_total;Stage3_end_inventory=$row.stage3_end_inventory_total}
    $snapshots | Export-Csv -LiteralPath (Join-Path $trainDir 'training_hourly_snapshot.csv') -NoTypeInformation -Encoding UTF8
    return $sha
}

try {
    if ($SmokeOnly) {
        if (Test-Path -LiteralPath $runDir) { throw "Refusing to overwrite $runDir" }
        Invoke-Phase -Phase 'INIT'
        Invoke-Phase -Phase 'SERIALIZER_SMOKE'
        return
    }

    if (-not (Test-Path -LiteralPath $runDir -PathType Container)) {
        throw "Stage89Q run must pass -SmokeOnly before formal training: $runDir"
    }
    $smokePath = Join-Path $runDir '04_qa\hourly_serializer_regression.csv'
    $closurePath = Join-Path $runDir '04_qa\serializer_smoke_closure.csv'
    if (-not (Test-Path -LiteralPath $smokePath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $closurePath -PathType Leaf)) {
        throw 'Serializer smoke evidence is missing; formal training is forbidden.'
    }
    $smoke = @(Import-Csv -LiteralPath $smokePath)
    $closure = @(Import-Csv -LiteralPath $closurePath)
    $truthy = @('1', 'true')
    if ($smoke.Count -eq 0 -or $closure.Count -ne 1 -or
        @($smoke | Where-Object { $truthy -notcontains $_.pass.ToLowerInvariant() }).Count -gt 0 -or
        @($smoke | Where-Object { $truthy -notcontains $_.smoke_pass.ToLowerInvariant() }).Count -gt 0 -or
        $truthy -notcontains $closure[0].pass.ToLowerInvariant()) {
        throw 'HOURLY_SERIALIZER_REGRESSION is not PASS; formal training is forbidden.'
    }
    if (Test-Path -LiteralPath (Join-Path $runDir 'FAILURE.txt')) {
        throw 'Run contains a MATLAB failure record; use the next legal run number.'
    }
    if ((Test-Path -LiteralPath (Join-Path $runDir '02_training\penalty1000\training_progress.csv')) -or
        (Test-Path -LiteralPath (Join-Path $runDir '02_training\penalty1500\training_progress.csv')) -or
        (Test-Path -LiteralPath (Get-CheckpointPath 1000)) -or
        (Test-Path -LiteralPath (Get-CheckpointPath 1500))) {
        throw 'Formal Stage89Q output already exists; refusing to overwrite or resume training.'
    }
    $currentHead = (& git -C $repo rev-parse HEAD).Trim()
    if ($currentHead -ne $FrozenCommit) { throw "HEAD $currentHead does not match frozen commit $FrozenCommit" }
    [pscustomobject]@{
        source_head = $FrozenCommit
        serializer_smoke_pass = $true
        serializer_regression_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $smokePath).Hash.ToLowerInvariant()
        serializer_closure_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $closurePath).Hash.ToLowerInvariant()
        frozen_at = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss zzz')
    } | Export-Csv -LiteralPath (Join-Path $runDir '00_identity\source_identity.csv') -NoTypeInformation -Encoding UTF8

    Invoke-Phase -Phase 'TRAIN' -Arm 'P1000'
    $sha1000 = Write-TrainingExternalAudit -Arm 'Arm-A' -Penalty 1000
    Invoke-Phase -Phase 'TRAIN' -Arm 'P1500'
    $sha1500 = Write-TrainingExternalAudit -Arm 'Arm-B' -Penalty 1500
    "P1000_TRAINING_COMPLETE=true`nP1500_TRAINING_COMPLETE=true`nBOTH_TRAININGS_COMPLETE=true" | Set-Content -LiteralPath (Join-Path $runDir 'BOTH_TRAININGS_COMPLETE.txt') -Encoding UTF8

    Invoke-Phase -Phase 'BANK'
    Invoke-Phase -Phase 'OOS' -Arm 'P1000' -CheckpointSha $sha1000
    $post1000 = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-CheckpointPath 1000)).Hash.ToLowerInvariant()
    if ($post1000 -ne $sha1000) { throw 'Penalty1000 checkpoint changed after OOS' }
    Invoke-Phase -Phase 'OOS' -Arm 'P1500' -CheckpointSha $sha1500
    $post1500 = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-CheckpointPath 1500)).Hash.ToLowerInvariant()
    if ($post1500 -ne $sha1500) { throw 'Penalty1500 checkpoint changed after OOS' }
    "BOTH_RAW_OOS_COMPLETE=true" | Set-Content -LiteralPath (Join-Path $runDir 'BOTH_RAW_OOS_COMPLETE.txt') -Encoding UTF8
} catch {
    if (Test-Path -LiteralPath $runDir) { ($_ | Out-String) | Set-Content -LiteralPath (Join-Path $runDir 'ORCHESTRATOR_FAILURE.txt') -Encoding UTF8 }
    throw
} finally {
    Remove-Item Env:STAGE89Q_RUN_ID,Env:STAGE89Q_FROZEN_COMMIT,Env:STAGE89Q_PHASE,Env:STAGE89Q_ARM,Env:STAGE89Q_CHECKPOINT_SHA256 -ErrorAction SilentlyContinue
    if ($LogPath) { Stop-Transcript | Out-Null }
}
