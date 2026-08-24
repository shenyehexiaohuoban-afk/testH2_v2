param(
    [string]$RunId = 'run-001',
    [string]$FrozenCommit = '',
    [string]$LogPath = ''
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$matlab = 'D:\Program Files\MATLAB\R2022a\bin\matlab.exe'
$python = (Get-Command python -ErrorAction Stop).Source
$resultRoot = Join-Path $repo 'results\task-002-stage2b-b3-smoke\stage89q-pmax-dual-10iter-smoke'
$runDir = Join-Path $resultRoot $RunId
$driver = "addpath('fa_msp/current_hourly_stage89_adopted/launcher'); run_stage89q_pmax_dual_10iter_smoke_h2"
$createdRun = $false
if (-not $FrozenCommit) { $FrozenCommit = (& git -C $repo rev-parse HEAD).Trim() }
if ($LogPath) { Start-Transcript -LiteralPath $LogPath -Force | Out-Null }

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
    if ($live.Count -gt 0) {
        throw "Live MATLAB/Gurobi process at ${Boundary}: $($live.process_id -join ',')"
    }
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
    $dirs = @('01_preflight','04_comparison','05_summary','06_qa','07_manifests')
    foreach ($arm in @('02_arm_b0001','03_arm_b1011')) {
        foreach ($child in @('01_config','02_training','03_iteration_records','04_stage_site_diagnostics',
                '05_grid_diagnostics','06_checkpoint','07_issue_recheck','08_new_issue_scan','09_qa')) {
            $dirs += "$arm\$child"
        }
    }
    foreach ($dir in $dirs) { New-Item -ItemType Directory -Path (Join-Path $runDir $dir) -Force | Out-Null }
}

function Write-CommandRecord {
    $launcher = Join-Path $repo 'fa_msp\current_hourly_stage89_adopted\launcher\run_stage89q_pmax_dual_10iter_smoke_h2.m'
    $orchestrator = $PSCommandPath
    $base = "& '$matlab' -nojvm -nodesktop -nosplash -logfile <phase-log> -batch `"$driver`""
    $rows = @(
        [pscustomobject]@{key='WORKING_DIRECTORY';value=$repo},
        [pscustomobject]@{key='POWERSHELL_SCRIPT';value=$orchestrator},
        [pscustomobject]@{key='MATLAB_EXECUTABLE';value=$matlab},
        [pscustomobject]@{key='MATLAB_LAUNCHER';value=$launcher},
        [pscustomobject]@{key='MATLAB_ARGUMENTS';value="-nojvm -nodesktop -nosplash -logfile <phase-log> -batch `"$driver`""},
        [pscustomobject]@{key='ARM_B0001_COMMAND';value="STAGE89Q_PMAX_PHASE=TRAIN; STAGE89Q_PMAX_ARM=B0001; STAGE89Q_PMAX_VECTOR=300,200,120,187.5; $base"},
        [pscustomobject]@{key='ARM_B1011_COMMAND';value="STAGE89Q_PMAX_PHASE=TRAIN; STAGE89Q_PMAX_ARM=B1011; STAGE89Q_PMAX_VECTOR=375,200,150,187.5; $base"},
        [pscustomobject]@{key='B0001_OUTPUT_DIRECTORY';value=(Join-Path $runDir '02_arm_b0001')},
        [pscustomobject]@{key='B1011_OUTPUT_DIRECTORY';value=(Join-Path $runDir '03_arm_b1011')},
        [pscustomobject]@{key='FROZEN_COMMIT';value=$FrozenCommit}
    )
    $rows | Export-Csv -LiteralPath (Join-Path $runDir '01_preflight\executable_commands.csv') -NoTypeInformation -Encoding UTF8
    $rows | ForEach-Object { "$($_.key) = $($_.value)" } | Set-Content -LiteralPath (Join-Path $runDir '01_preflight\executable_commands.txt') -Encoding UTF8
}

function Invoke-MatlabPhase {
    param(
        [Parameter(Mandatory=$true)][string]$Phase,
        [string]$Arm = '',
        [string]$Pmax = '',
        [string]$CheckpointSha = ''
    )
    $label = if ($Arm) { "$($Phase.ToLowerInvariant())-$($Arm.ToLowerInvariant())" } else { $Phase.ToLowerInvariant() }
    Assert-NoLiveSolverProcess -Boundary "before $label"
    Write-ProcessSnapshot -Name "before_$($label.Replace('-','_'))"
    $env:STAGE89Q_PMAX_RUN_DIR = $runDir
    $env:STAGE89Q_PMAX_PHASE = $Phase
    $env:STAGE89Q_PMAX_ARM = $Arm
    $env:STAGE89Q_PMAX_VECTOR = $Pmax
    $env:STAGE89Q_PMAX_FROZEN_COMMIT = $FrozenCommit
    $env:STAGE89Q_PMAX_CHECKPOINT_SHA256 = $CheckpointSha
    $phaseLog = Join-Path $runDir "01_preflight\${label}_native_stdout.log"
    $started = Get-Date
    & $matlab -nojvm -nodesktop -nosplash -logfile $phaseLog -batch $driver
    $exitCode = $LASTEXITCODE
    $ended = Get-Date
    [pscustomobject]@{phase=$Phase;arm=$Arm;pmax=$Pmax;started_at=$started.ToString('o');ended_at=$ended.ToString('o');duration_s=($ended-$started).TotalSeconds;exit_code=$exitCode;log=$phaseLog} |
        Export-Csv -LiteralPath (Join-Path $runDir "01_preflight\phase_${label}.csv") -NoTypeInformation -Encoding UTF8
    if ($exitCode -ne 0) { throw "MATLAB phase $label failed with exit code $exitCode; log=$phaseLog" }
    Assert-NoLiveSolverProcess -Boundary "after $label"
    Write-ProcessSnapshot -Name "after_$($label.Replace('-','_'))"
}

function Write-CheckpointManifest {
    param([Parameter(Mandatory=$true)][string]$ArmFolder,[Parameter(Mandatory=$true)][string]$Candidate)
    Assert-NoLiveSolverProcess -Boundary "external checkpoint hash $Candidate"
    $checkpoint = Join-Path $runDir "$ArmFolder\06_checkpoint\checkpoint_final.mat"
    if (-not (Test-Path -LiteralPath $checkpoint -PathType Leaf)) { throw "Missing checkpoint $checkpoint" }
    $info = Get-Item -LiteralPath $checkpoint
    $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $checkpoint).Hash.ToLowerInvariant()
    [pscustomobject]@{candidate=$Candidate;path=$checkpoint;size_bytes=$info.Length;sha256=$sha;hashed_after_matlab_exit=$true;source_commit=$FrozenCommit} |
        Export-Csv -LiteralPath (Join-Path $runDir "$ArmFolder\06_checkpoint\checkpoint_manifest.csv") -NoTypeInformation -Encoding UTF8
    return $sha
}

function Preserve-FailedRun {
    if (-not $createdRun -or -not (Test-Path -LiteralPath $runDir)) { return $null }
    $index = 1
    do {
        $failed = Join-Path $resultRoot ("$RunId.failed-{0:d3}" -f $index)
        $index++
    } while (Test-Path -LiteralPath $failed)
    Move-Item -LiteralPath $runDir -Destination $failed
    return $failed
}

try {
    Initialize-RunDirectories
    Write-CommandRecord
    Write-ProcessSnapshot -Name 'initial'
    Assert-NoLiveSolverProcess -Boundary 'initial preflight'
    & $python (Join-Path $PSScriptRoot 'stage89q_pmax_smoke_audit.py') prepare --repo $repo --run-dir $runDir --commit $FrozenCommit
    if ($LASTEXITCODE -ne 0) { throw 'Mechanical preflight/Pmax audit failed.' }

    Invoke-MatlabPhase -Phase 'BASE_IDENTITY'
    Invoke-MatlabPhase -Phase 'CONFIG' -Arm 'B0001' -Pmax '300,200,120,187.5'
    Invoke-MatlabPhase -Phase 'TRAIN' -Arm 'B0001' -Pmax '300,200,120,187.5'
    $shaB0001 = Write-CheckpointManifest -ArmFolder '02_arm_b0001' -Candidate 'ARM-B0001'
    Invoke-MatlabPhase -Phase 'RELOAD' -Arm 'B0001' -Pmax '300,200,120,187.5' -CheckpointSha $shaB0001

    Invoke-MatlabPhase -Phase 'CONFIG' -Arm 'B1011' -Pmax '375,200,150,187.5'
    Invoke-MatlabPhase -Phase 'TRAIN' -Arm 'B1011' -Pmax '375,200,150,187.5'
    $shaB1011 = Write-CheckpointManifest -ArmFolder '03_arm_b1011' -Candidate 'ARM-B1011'
    Invoke-MatlabPhase -Phase 'RELOAD' -Arm 'B1011' -Pmax '375,200,150,187.5' -CheckpointSha $shaB1011

    & $python (Join-Path $PSScriptRoot 'stage89q_pmax_smoke_audit.py') finalize --repo $repo --run-dir $runDir --commit $FrozenCommit
    if ($LASTEXITCODE -ne 0) { throw 'Final smoke QA failed.' }
    Set-Content -LiteralPath (Join-Path $runDir 'SMOKE_COMPLETE.txt') -Value "status=PASS`nsource_commit=$FrozenCommit" -Encoding UTF8
} catch {
    $message = ($_ | Out-String)
    if ($createdRun -and (Test-Path -LiteralPath $runDir)) {
        $message | Set-Content -LiteralPath (Join-Path $runDir 'ORCHESTRATOR_FAILURE.txt') -Encoding UTF8
        Write-ProcessSnapshot -Name 'failure'
    }
    $failedPath = Preserve-FailedRun
    if ($failedPath) { Write-Error "Smoke stopped; failure evidence preserved at $failedPath`n$message" } else { Write-Error $message }
} finally {
    Remove-Item Env:STAGE89Q_PMAX_RUN_DIR,Env:STAGE89Q_PMAX_PHASE,Env:STAGE89Q_PMAX_ARM,Env:STAGE89Q_PMAX_VECTOR,Env:STAGE89Q_PMAX_FROZEN_COMMIT,Env:STAGE89Q_PMAX_CHECKPOINT_SHA256 -ErrorAction SilentlyContinue
    if ($LogPath) { Stop-Transcript | Out-Null }
}
