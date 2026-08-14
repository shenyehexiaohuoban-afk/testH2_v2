param(
    [Parameter(Mandatory=$true)][string]$TrainingCommit,
    [Parameter(Mandatory=$true)][string]$OosFixCommit,
    [Parameter(Mandatory=$true)][string]$OosRunCommit,
    [string]$RunId = 'run-001'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$matlab = 'D:\Program Files\MATLAB\R2022a\bin\matlab.exe'
$baseDir = Join-Path $repo 'results\task-002-stage2b-b3-smoke\84B-full-common-oos-paired-analysis'
$runDir = Join-Path $baseDir $RunId
if (-not (Test-Path -LiteralPath $matlab)) { throw "MATLAB not found: $matlab" }
if (Test-Path -LiteralPath $runDir) { throw "Refusing to overwrite $runDir" }
$head = (git -C $repo rev-parse HEAD).Trim()
if ($head -ne $OosRunCommit) { throw "HEAD $head does not match OOS run commit $OosRunCommit" }
git -C $repo merge-base --is-ancestor $OosFixCommit $OosRunCommit
if ($LASTEXITCODE -ne 0) { throw 'OOS fix commit is not an ancestor of the runner commit.' }
git -C $repo diff --quiet
if ($LASTEXITCODE -ne 0) { throw 'Tracked worktree is not clean.' }
git -C $repo diff --cached --quiet
if ($LASTEXITCODE -ne 0) { throw 'Staged worktree is not clean.' }
if (Get-Process MATLAB -ErrorAction SilentlyContinue) { throw 'A MATLAB process is already running.' }
$drive = Get-PSDrive -Name ([IO.Path]::GetPathRoot($repo).Substring(0,1))
if ($drive.Free -lt 50GB) { throw 'Less than 50 GB free; refusing to launch full OOS.' }
if (-not (Test-Path -LiteralPath $baseDir)) { New-Item -ItemType Directory -Path $baseDir | Out-Null }

$attempt = 1
do {
    $suffix = if ($attempt -eq 1) { '' } else { "-$('{0:D3}' -f $attempt)" }
    $recordFile = Join-Path $baseDir "$RunId-launch-record$suffix.txt"
    $matlabLog = Join-Path $baseDir "$RunId-matlab-launch$suffix.log"
    $attempt++
} while ((Test-Path -LiteralPath $recordFile) -or (Test-Path -LiteralPath $matlabLog))

$expr = "cd('$($repo.Replace('\','/'))'); addpath(fullfile(pwd,'hourly_grid_h2')); run_stage84b_full_oos_analysis_h2"
$psi = [System.Diagnostics.ProcessStartInfo]::new()
$psi.FileName = $matlab
$psi.WorkingDirectory = $repo
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.RedirectStandardOutput = $false
$psi.RedirectStandardError = $false
$psi.Environment['STAGE84B_RUN_ID'] = $RunId
$psi.Environment['STAGE84B_RUN_COMMIT'] = $OosRunCommit
$psi.ArgumentList.Add('-logfile')
$psi.ArgumentList.Add($matlabLog)
$psi.ArgumentList.Add('-batch')
$psi.ArgumentList.Add($expr)
$process = [System.Diagnostics.Process]::new()
$process.StartInfo = $psi
if (-not $process.Start()) { throw 'Failed to start MATLAB.' }

$record = @(
    "START_PROCESS_PID=$($process.Id)"
    "START_TIME=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    "RUN_DIR=$runDir"
    "TRAINING_COMMIT=$TrainingCommit"
    "OOS_FIX_COMMIT=$OosFixCommit"
    "OOS_RUN_COMMIT=$OosRunCommit"
    "RUN_ID=$RunId"
    "MATLAB_LOG=$matlabLog"
    "AUTOMATIC_MONITORING=false"
) -join "`r`n"
Set-Content -LiteralPath $recordFile -Value $record -Encoding UTF8
$record
