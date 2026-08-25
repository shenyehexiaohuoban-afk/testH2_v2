param(
    [string]$RunId = 'run-001',
    [string]$FrozenCommit = '',
    [string]$LogPath = ''
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$matlab = 'D:\Program Files\MATLAB\R2022a\bin\matlab.exe'
$python = (Get-Command python -ErrorAction Stop).Source
$resultRoot = Join-Path $repo 'results\task-002-stage2b-b3-smoke\stage89q-pmax-dual-2p5h-training-10k-oos'
$runDir = Join-Path $resultRoot $RunId
$launcher = Join-Path $PSScriptRoot 'run_stage89q_pmax_dual_2p5h_10k_oos_h2.m'
$analysis = Join-Path $PSScriptRoot 'stage89q_pmax_long_analysis.py'
$driver = "addpath('fa_msp/current_hourly_stage89_adopted/launcher'); run_stage89q_pmax_dual_2p5h_10k_oos_h2"
$createdRun = $false
$transcriptStarted = $false

if (-not $FrozenCommit) { $FrozenCommit = (& git -C $repo rev-parse HEAD).Trim() }
if (-not (Test-Path -LiteralPath $matlab -PathType Leaf)) { throw "MATLAB executable missing: $matlab" }
if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) { throw "MATLAB launcher missing: $launcher" }
if (-not (Test-Path -LiteralPath $analysis -PathType Leaf)) { throw "Analysis script missing: $analysis" }

function Get-SolverProcessSnapshot {
    $rows = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -match '^(MATLAB|MATLABWindow|gurobi.*)\.exe$' })
    foreach ($row in $rows) {
        $workingSet = [int64]$row.WorkingSetSize
        $hasLiveResources = -not [string]::IsNullOrWhiteSpace([string]$row.ExecutablePath) -or
            -not [string]::IsNullOrWhiteSpace([string]$row.CommandLine) -or $workingSet -gt 1048576
        [pscustomobject]@{
            process_id = $row.ProcessId
            parent_process_id = $row.ParentProcessId
            name = $row.Name
            executable_path = [string]$row.ExecutablePath
            command_line = [string]$row.CommandLine
            working_set_bytes = $workingSet
            live_resource_gate = $hasLiveResources
            classification = if ($hasLiveResources) { 'LIVE_SOLVER_PROCESS' } else { 'EXITED_STALE_PROCESS_OBJECT' }
        }
    }
}

function Assert-NoLiveSolverProcess {
    param([Parameter(Mandatory=$true)][string]$Boundary)
    $snapshot = @(Get-SolverProcessSnapshot)
    $live = @($snapshot | Where-Object { $_.live_resource_gate })
    if ($live.Count -gt 0) { throw "Live MATLAB/Gurobi process at ${Boundary}: $($live.process_id -join ',')" }
}

function Write-ProcessSnapshot {
    param([Parameter(Mandatory=$true)][string]$Name)
    $snapshot = @(Get-SolverProcessSnapshot)
    $path = Join-Path $runDir "01_preflight\process_${Name}.csv"
    if ($snapshot.Count -eq 0) {
        [pscustomobject]@{process_id='';parent_process_id='';name='';executable_path='';command_line='';working_set_bytes=0;live_resource_gate=$false;classification='NO_SOLVER_PROCESS'} |
            Export-Csv -LiteralPath $path -NoTypeInformation -Encoding UTF8
    } else {
        $snapshot | Export-Csv -LiteralPath $path -NoTypeInformation -Encoding UTF8
    }
}

function Initialize-RunDirectories {
    if (Test-Path -LiteralPath $runDir) { throw "Refusing to overwrite $runDir" }
    New-Item -ItemType Directory -Path $runDir | Out-Null
    $script:createdRun = $true
    $dirs = @('01_preflight\common_bank','06_paired_analysis','07_figures','08_summary','09_qa','10_manifests')
    foreach ($arm in @('02_training_b0001','03_training_b1011')) {
        foreach ($child in @('config','iteration_trace','stage_site','grid','monitor','checkpoint','acceptance','qa')) { $dirs += "$arm\$child" }
    }
    foreach ($arm in @('04_oos_b0001','05_oos_b1011')) {
        foreach ($child in @('raw','hourly','summaries','qa','path_summary','hourly_site','grid_hourly','htt_od')) { $dirs += "$arm\$child" }
    }
    foreach ($dir in $dirs) { New-Item -ItemType Directory -Path (Join-Path $runDir $dir) -Force | Out-Null }
}

function Write-CommandRecord {
    $base = "& '$matlab' -nojvm -nodesktop -nosplash -logfile <phase-log> -batch `"$driver`""
    $rows = @(
        [pscustomobject]@{key='WORKING_DIRECTORY';value=$repo},
        [pscustomobject]@{key='POWERSHELL_SCRIPT';value=$PSCommandPath},
        [pscustomobject]@{key='MATLAB_EXECUTABLE';value=$matlab},
        [pscustomobject]@{key='MATLAB_LAUNCHER';value=$launcher},
        [pscustomobject]@{key='ANALYSIS_SCRIPT';value=$analysis},
        [pscustomobject]@{key='BASE_IDENTITY_COMMAND';value="STAGE89Q_PMAX_LONG_PHASE=BASE_IDENTITY; $base"},
        [pscustomobject]@{key='B0001_TRAIN_COMMAND';value="STAGE89Q_PMAX_LONG_PHASE=TRAIN; STAGE89Q_PMAX_LONG_ARM=B0001; STAGE89Q_PMAX_LONG_VECTOR=300,200,120,187.5; $base"},
        [pscustomobject]@{key='B1011_TRAIN_COMMAND';value="STAGE89Q_PMAX_LONG_PHASE=TRAIN; STAGE89Q_PMAX_LONG_ARM=B1011; STAGE89Q_PMAX_LONG_VECTOR=375,200,150,187.5; $base"},
        [pscustomobject]@{key='BANK_COMMAND';value="STAGE89Q_PMAX_LONG_PHASE=BANK; $base"},
        [pscustomobject]@{key='B0001_OOS_COMMAND';value="STAGE89Q_PMAX_LONG_PHASE=OOS; STAGE89Q_PMAX_LONG_ARM=B0001; $base"},
        [pscustomobject]@{key='B1011_OOS_COMMAND';value="STAGE89Q_PMAX_LONG_PHASE=OOS; STAGE89Q_PMAX_LONG_ARM=B1011; $base"},
        [pscustomobject]@{key='FROZEN_COMMIT';value=$FrozenCommit},
        [pscustomobject]@{key='RUN_DIRECTORY';value=$runDir}
    )
    $rows | Export-Csv -LiteralPath (Join-Path $runDir '01_preflight\executable_commands.csv') -NoTypeInformation -Encoding UTF8
    $rows | ForEach-Object { "$($_.key) = $($_.value)" } | Set-Content -LiteralPath (Join-Path $runDir '01_preflight\executable_commands.txt') -Encoding UTF8
}

function Get-PhaseLogPath {
    param([string]$Phase,[string]$Arm)
    $name = $Phase.ToLowerInvariant()
    if ($Arm) { $name = "${name}_$($Arm.ToLowerInvariant())" }
    $trainingFolder = if ($Arm -eq 'B0001') { '02_training_b0001' } else { '03_training_b1011' }
    $oosFolder = if ($Arm -eq 'B0001') { '04_oos_b0001' } else { '05_oos_b1011' }
    switch ($Phase) {
        'TRAIN' { return Join-Path $runDir "$trainingFolder\monitor\${name}_native_stdout.log" }
        'CONFIG' { return Join-Path $runDir "$trainingFolder\monitor\${name}_native_stdout.log" }
        'RELOAD' { return Join-Path $runDir "$trainingFolder\monitor\${name}_native_stdout.log" }
        'OOS' { return Join-Path $runDir "$oosFolder\qa\${name}_native_stdout.log" }
        default { return Join-Path $runDir "01_preflight\${name}_native_stdout.log" }
    }
}

function Invoke-MatlabPhase {
    param([Parameter(Mandatory=$true)][string]$Phase,[string]$Arm = '',[string]$Pmax = '',[string]$CheckpointSha = '')
    $label = if ($Arm) { "$($Phase.ToLowerInvariant())-$($Arm.ToLowerInvariant())" } else { $Phase.ToLowerInvariant() }
    Assert-NoLiveSolverProcess -Boundary "before $label"
    Write-ProcessSnapshot -Name "before_$($label.Replace('-','_'))"
    $env:STAGE89Q_PMAX_LONG_RUN_DIR = $runDir
    $env:STAGE89Q_PMAX_LONG_PHASE = $Phase
    $env:STAGE89Q_PMAX_LONG_ARM = $Arm
    $env:STAGE89Q_PMAX_LONG_VECTOR = $Pmax
    $env:STAGE89Q_PMAX_LONG_FROZEN_COMMIT = $FrozenCommit
    $env:STAGE89Q_PMAX_LONG_CHECKPOINT_SHA256 = $CheckpointSha
    $phaseLog = Get-PhaseLogPath -Phase $Phase -Arm $Arm
    $started = Get-Date
    Push-Location $repo
    try { & $matlab -nojvm -nodesktop -nosplash -logfile $phaseLog -batch $driver; $exitCode = $LASTEXITCODE } finally { Pop-Location }
    $ended = Get-Date
    [pscustomobject]@{phase=$Phase;arm=$Arm;pmax=$Pmax;started_at=$started.ToString('o');ended_at=$ended.ToString('o');duration_s=($ended-$started).TotalSeconds;exit_code=$exitCode;log=$phaseLog} |
        Export-Csv -LiteralPath (Join-Path $runDir "01_preflight\phase_${label}.csv") -NoTypeInformation -Encoding UTF8
    if ($exitCode -ne 0) { throw "MATLAB phase $label failed with exit code $exitCode; log=$phaseLog" }
    Assert-NoLiveSolverProcess -Boundary "after $label"
    Write-ProcessSnapshot -Name "after_$($label.Replace('-','_'))"
}

function Invoke-AnalysisPhase {
    param([Parameter(Mandatory=$true)][string]$Mode,[string]$Arm = '')
    $arguments = @($analysis,$Mode,'--repo',$repo,'--run-dir',$runDir,'--commit',$FrozenCommit)
    if ($Arm) { $arguments += @('--arm',$Arm) }
    & $python @arguments
    if ($LASTEXITCODE -ne 0) { throw "Python analysis phase $Mode $Arm failed with exit code $LASTEXITCODE" }
}

function Write-CheckpointManifest {
    param([Parameter(Mandatory=$true)][string]$Arm,[Parameter(Mandatory=$true)][string]$Candidate)
    Assert-NoLiveSolverProcess -Boundary "external checkpoint hash $Candidate"
    $folder = if ($Arm -eq 'B0001') { '02_training_b0001' } else { '03_training_b1011' }
    $checkpoint = Join-Path $runDir "$folder\checkpoint\checkpoint_final.mat"
    if (-not (Test-Path -LiteralPath $checkpoint -PathType Leaf)) { throw "Missing checkpoint $checkpoint" }
    $info = Get-Item -LiteralPath $checkpoint
    $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $checkpoint).Hash.ToLowerInvariant()
    [pscustomobject]@{candidate=$Candidate;path=$checkpoint;size_bytes=$info.Length;sha256=$sha;hashed_after_matlab_exit=$true;source_commit=$FrozenCommit} |
        Export-Csv -LiteralPath (Join-Path $runDir "$folder\checkpoint\checkpoint_manifest.csv") -NoTypeInformation -Encoding UTF8
    return $sha
}

function Assert-OosAcceptance {
    param([Parameter(Mandatory=$true)][string]$Arm,[Parameter(Mandatory=$true)][string]$CheckpointSha)
    $folder = if ($Arm -eq 'B0001') { '04_oos_b0001' } else { '05_oos_b1011' }
    $metaPath = Join-Path $runDir "$folder\oos_metadata.csv"
    if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) { throw "$Arm OOS metadata missing" }
    $meta = @(Import-Csv -LiteralPath $metaPath)
    $truth = @('1','true','True','TRUE')
    if ($meta.Count -ne 1 -or [int]$meta[0].completed_paths -ne 10000 -or $truth -notcontains [string]$meta[0].pass -or
        $truth -notcontains [string]$meta[0].cuts_unchanged -or $truth -notcontains [string]$meta[0].checkpoint_unchanged -or
        [string]$meta[0].checkpoint_sha256_before -ne $CheckpointSha -or [string]$meta[0].checkpoint_sha256_after -ne $CheckpointSha) {
        throw "$Arm OOS acceptance failed"
    }
}

function Preserve-FailedRun {
    if (-not $createdRun -or -not (Test-Path -LiteralPath $runDir)) { return $null }
    $index = 1
    do { $failed = Join-Path $resultRoot ("$RunId.failed-{0:d3}" -f $index); $index++ } while (Test-Path -LiteralPath $failed)
    Move-Item -LiteralPath $runDir -Destination $failed
    return $failed
}

try {
    Initialize-RunDirectories
    if ($LogPath) { Start-Transcript -LiteralPath $LogPath -Force | Out-Null; $transcriptStarted = $true }
    Write-CommandRecord
    Write-ProcessSnapshot -Name 'initial'
    Assert-NoLiveSolverProcess -Boundary 'initial preflight'
    Invoke-AnalysisPhase -Mode 'prepare'
    Invoke-MatlabPhase -Phase 'BASE_IDENTITY'

    Invoke-MatlabPhase -Phase 'CONFIG' -Arm 'B0001' -Pmax '300,200,120,187.5'
    Invoke-MatlabPhase -Phase 'TRAIN' -Arm 'B0001' -Pmax '300,200,120,187.5'
    $shaB0001 = Write-CheckpointManifest -Arm 'B0001' -Candidate 'ARM-B0001'
    Invoke-MatlabPhase -Phase 'RELOAD' -Arm 'B0001' -Pmax '300,200,120,187.5' -CheckpointSha $shaB0001
    Invoke-AnalysisPhase -Mode 'accept' -Arm 'B0001'

    Invoke-MatlabPhase -Phase 'CONFIG' -Arm 'B1011' -Pmax '375,200,150,187.5'
    Invoke-MatlabPhase -Phase 'TRAIN' -Arm 'B1011' -Pmax '375,200,150,187.5'
    $shaB1011 = Write-CheckpointManifest -Arm 'B1011' -Candidate 'ARM-B1011'
    Invoke-MatlabPhase -Phase 'RELOAD' -Arm 'B1011' -Pmax '375,200,150,187.5' -CheckpointSha $shaB1011
    Invoke-AnalysisPhase -Mode 'accept' -Arm 'B1011'

    Set-Content -LiteralPath (Join-Path $runDir 'BOTH_TRAININGS_COMPLETE.txt') -Value "BOTH_TRAININGS_COMPLETE=true`nB0001_ACCEPTANCE=PASS`nB1011_ACCEPTANCE=PASS" -Encoding UTF8
    Invoke-MatlabPhase -Phase 'BANK'
    Invoke-MatlabPhase -Phase 'OOS' -Arm 'B0001' -Pmax '300,200,120,187.5' -CheckpointSha $shaB0001
    Assert-OosAcceptance -Arm 'B0001' -CheckpointSha $shaB0001
    Invoke-MatlabPhase -Phase 'OOS' -Arm 'B1011' -Pmax '375,200,150,187.5' -CheckpointSha $shaB1011
    Assert-OosAcceptance -Arm 'B1011' -CheckpointSha $shaB1011
    Invoke-AnalysisPhase -Mode 'finalize'
    Set-Content -LiteralPath (Join-Path $runDir 'WORKFLOW_COMPLETE.txt') -Value "status=PASS`nsource_commit=$FrozenCommit" -Encoding UTF8
} catch {
    $message = ($_ | Out-String)
    if ($createdRun -and (Test-Path -LiteralPath $runDir)) {
        $message | Set-Content -LiteralPath (Join-Path $runDir 'ORCHESTRATOR_FAILURE.txt') -Encoding UTF8
        Write-ProcessSnapshot -Name 'failure'
    }
    if ($transcriptStarted) { Stop-Transcript | Out-Null; $transcriptStarted = $false }
    $failedPath = Preserve-FailedRun
    if ($failedPath) { throw "Stage89Q Pmax long workflow stopped; failure evidence preserved at $failedPath`n$message" }
    throw $message
} finally {
    Remove-Item Env:STAGE89Q_PMAX_LONG_RUN_DIR,Env:STAGE89Q_PMAX_LONG_PHASE,Env:STAGE89Q_PMAX_LONG_ARM,Env:STAGE89Q_PMAX_LONG_VECTOR,Env:STAGE89Q_PMAX_LONG_FROZEN_COMMIT,Env:STAGE89Q_PMAX_LONG_CHECKPOINT_SHA256 -ErrorAction SilentlyContinue
    if ($transcriptStarted) { Stop-Transcript | Out-Null }
}
