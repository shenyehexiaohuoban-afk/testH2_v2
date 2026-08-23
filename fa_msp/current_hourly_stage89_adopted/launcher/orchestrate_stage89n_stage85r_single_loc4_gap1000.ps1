param(
    [string]$RunId = 'run-001',
    [string]$FrozenCommit = '',
    [string]$LogPath = ''
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$matlab = 'D:\Program Files\MATLAB\R2022a\bin\matlab.exe'
$runRoot = Join-Path $repo 'results\task-002-stage2b-b3-smoke\stage89n-stage89k-adopted-loc4-fresh-8h-retraining'
$runDir = Join-Path $runRoot $RunId
$checkpointRoot = Join-Path $repo 'terminalLoh_wdro\output\stage89n_stage89k_adopted_loc4_fresh_8h_retraining'
$checkpoint = Join-Path (Join-Path $checkpointRoot $RunId) 'checkpoint_final.mat'
$driver = "addpath('fa_msp/current_hourly_stage89_adopted/launcher'); run_stage89n_stage85r_single_loc4_gap1000_h2"
if (-not $FrozenCommit) { $FrozenCommit = (& git -C $repo rev-parse HEAD).Trim() }
if ($LogPath) { Start-Transcript -LiteralPath $LogPath -Force | Out-Null }

function Assert-NoSolverProcess {
    param([Parameter(Mandatory=$true)][string]$Boundary)
    $active = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^(MATLAB|MATLABWindow|gurobi)' }
    if ($active) { throw "MATLAB/Gurobi already active at $Boundary" }
}

function Invoke-Phase {
    param([Parameter(Mandatory=$true)][string]$Phase)
    Assert-NoSolverProcess -Boundary "before $Phase"
    $env:STAGE89N_RUN_ID = $RunId
    $env:STAGE89N_FROZEN_COMMIT = $FrozenCommit
    $env:STAGE89N_PHASE = $Phase
    $phaseLog = Join-Path $runRoot "$RunId-$($Phase.ToLowerInvariant())-matlab.log"
    & $matlab -nojvm -nodesktop -nosplash -logfile $phaseLog -batch $driver
    if ($LASTEXITCODE -ne 0) { throw "MATLAB phase $Phase failed with exit code $LASTEXITCODE; log=$phaseLog" }
    Assert-NoSolverProcess -Boundary "after $Phase"
}

function Write-SourceManifest {
    $spec = @(
        @('hourly_grid_h2\run_stage85r_dro_p150_p200_5h_10k_h2.m','Stage85R accepted runner mother'),
        @('hourly_grid_h2\orchestrate_stage85r_dro_p150_p200_5h_10k.ps1','Stage85R accepted orchestrator mother'),
        @('hourly_grid_h2\run_stage85h_a_checkpoint_reload_audit_h2.m','Stage85H-A clean reload implementation'),
        @('fa_msp\current_hourly_stage88_candidate\input\load_current_hourly_stage88_candidate_h2.m','Stage89F current model entry'),
        @('fa_msp\current_hourly_stage88_candidate\config\current_hourly_stage88_candidate_options_h2.m','Stage89F current options'),
        @('fa_h2\fuzhu\load_terminal_loh_lookup_h2.m','Stage88 loader'),
        @('fa_h2\forward_pass_h2.m','reused forward core'),
        @('fa_h2\backward_pass_h2.m','reused backward core'),
        @('terminalLoh_wdro\current_w_mainline_stage89\msp_bridge\load_current_stage89_hourly_h2.m','Stage89M adopted model/input entry'),
        @('terminalLoh_wdro\current_w_mainline_stage89\msp_bridge\load_stage89_adopted_terminal_loh_h2.m','Stage89K strict adopted loader'),
        @('terminalLoh_wdro\current_w_mainline_stage89\terminal_tables\terminal_loh_stage89k_dro_eta003_adopted.csv','Stage89K adopted DRO table'),
        @('fa_msp\current_hourly_stage89_adopted\launcher\run_stage89n_stage85r_single_loc4_gap1000_h2.m','Stage89N thin launcher'),
        @('fa_msp\current_hourly_stage89_adopted\launcher\orchestrate_stage89n_stage85r_single_loc4_gap1000.ps1','Stage89N thin orchestrator'),
        @('fa_msp\current_hourly_stage89_adopted\launcher\finalize_stage89n_single_loc4.py','Stage89N finalizer'),
        @('fa_msp\current_hourly_stage89_adopted\launcher\stage85r_stage89n_adapter_diff.md','adapter diff audit'),
        @('results\task-002-stage2b-b3-smoke\89H-stage85r-single-loc4-stage88-dro-gap1000-10iter-oos10000\run-003\oos\loc4\oos_path_bank.mat','Stage89H accepted common OOS bank')
    )
    $rows = foreach ($item in $spec) {
        $rel = $item[0]; $path = Join-Path $repo $rel
        if (-not (Test-Path -LiteralPath $path)) { throw "Missing manifest source $rel" }
        $info = Get-Item -LiteralPath $path
        & git -C $repo ls-files --error-unmatch -- $rel 2>$null | Out-Null
        $tracked = if ($LASTEXITCODE -eq 0) { 'tracked' } else { 'untracked' }
        [pscustomobject]@{
            path = $rel.Replace('\','/')
            size_bytes = $info.Length
            mtime = $info.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss zzz')
            sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
            role = $item[1]
            tracked_or_untracked = $tracked
        }
    }
    $rows | Export-Csv -LiteralPath (Join-Path $runDir 'source_manifest.csv') -NoTypeInformation -Encoding UTF8
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'stage85r_stage89n_adapter_diff.md') -Destination (Join-Path $runDir 'stage85r_stage89n_adapter_diff.md')
}

try {
    if (Test-Path -LiteralPath $runDir) { throw "Refusing to overwrite $runDir" }
    Invoke-Phase -Phase 'INIT'
    Write-SourceManifest
    Invoke-Phase -Phase 'TRAIN'
    Set-Content -LiteralPath (Join-Path $runDir 'TRAINING_PROCESS_EXITED_BEFORE_RELOAD') -Value 'TRAINING_PROCESS_EXITED_BEFORE_RELOAD=true' -Encoding UTF8

    $shaWatch = [System.Diagnostics.Stopwatch]::StartNew()
    $checkpointHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $checkpoint).Hash.ToLowerInvariant()
    $shaWatch.Stop()
    $checkpointShaSeconds = $shaWatch.Elapsed.TotalSeconds
    $env:STAGE89N_CHECKPOINT_SHA256 = $checkpointHash
    Invoke-Phase -Phase 'RELOAD_OOS'

    $postWatch = [System.Diagnostics.Stopwatch]::StartNew()
    $postHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $checkpoint).Hash.ToLowerInvariant()
    $postWatch.Stop()
    if ($postHash -ne $checkpointHash) { throw 'Checkpoint hash changed after clean reload/OOS' }
    $training = Import-Csv -LiteralPath (Join-Path $runDir 'training\training_summary.csv')
    $reload = Import-Csv -LiteralPath (Join-Path $runDir 'checkpoint_reload_audit.csv')
    [pscustomobject]@{
        checkpoint_save_seconds = [double]$training.checkpoint_save_seconds
        checkpoint_sha_seconds = $checkpointShaSeconds
        clean_reload_seconds = [double]$reload.clean_reload_seconds
        checkpoint_post_oos_sha_seconds = $postWatch.Elapsed.TotalSeconds
        checkpoint_sha256 = $checkpointHash
        checkpoint_hash_unchanged_after_oos = $true
    } | Export-Csv -LiteralPath (Join-Path $runDir 'checkpoint_timing.csv') -NoTypeInformation -Encoding UTF8

    Assert-NoSolverProcess -Boundary 'before finalization'
    $python = (Get-Command python.exe -ErrorAction Stop).Source
    & $python (Join-Path $PSScriptRoot 'finalize_stage89n_single_loc4.py') --run-dir $runDir --checkpoint $checkpoint --source-head $FrozenCommit
    if ($LASTEXITCODE -ne 0) { throw "Stage89N finalizer failed with exit code $LASTEXITCODE" }
    Assert-NoSolverProcess -Boundary 'after finalization'
} catch {
    if (Test-Path -LiteralPath $runDir) {
        Set-Content -LiteralPath (Join-Path $runDir 'ORCHESTRATOR_FAILURE.txt') -Value ($_ | Out-String) -Encoding UTF8
    }
    throw
} finally {
    Remove-Item Env:STAGE89N_RUN_ID,Env:STAGE89N_FROZEN_COMMIT,Env:STAGE89N_PHASE,Env:STAGE89N_CHECKPOINT_SHA256 -ErrorAction SilentlyContinue
    if ($LogPath) { Stop-Transcript | Out-Null }
}
