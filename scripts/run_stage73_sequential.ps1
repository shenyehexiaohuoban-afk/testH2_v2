param([string]$RunId='run-001')
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$stageRoot=Join-Path $repo "results\task-002-stage2b-b3-smoke\73-htt-transport-cost-sensitivity\$RunId"
$logRoot=Join-Path $stageRoot 'logs'; $stateRoot=Join-Path $stageRoot 'state'; $analysisRoot=Join-Path $stageRoot 'analysis\run-001'
$matlab=(Get-Command matlab -ErrorAction Stop).Source; $python=(Get-Command python -ErrorAction Stop).Source
$mainLog=Join-Path $logRoot 'sequential_runner.log'; New-Item -ItemType Directory -Force -Path $logRoot,$stateRoot|Out-Null
if(Test-Path -LiteralPath (Join-Path $stageRoot 'RUNNER_STARTED.txt')){throw "Refusing duplicate Stage-73 runner start: $stageRoot"}
function Log([string]$m){Add-Content -LiteralPath $mainLog -Value "$(Get-Date -Format o) | $m" -Encoding utf8}
function Invoke-Matlab([string]$script,[string]$log){
  $p=$script.Replace('\','/').Replace("'","''"); $repoMat=$repo.Replace('\','/').Replace("'","''")
  $expr="cd('$repoMat'); run('$p'); System.Environment.Exit(0);"
  $args="-logfile `"$log`" -batch `"$expr`""
  $process=Start-Process -FilePath $matlab -ArgumentList $args -WorkingDirectory $repo -WindowStyle Hidden -PassThru -Wait
  return $process.ExitCode
}
function NonEmpty([string]$p){(Test-Path -LiteralPath $p -PathType Leaf)-and((Get-Item -LiteralPath $p).Length-gt 0)}
$launchers=@{'H04'=Join-Path $repo 'terminalLoh_wdro\src\run_stage73_H04_h2.m';'H02'=Join-Path $repo 'terminalLoh_wdro\src\run_stage73_H02_h2.m';'H01'=Join-Path $repo 'terminalLoh_wdro\src\run_stage73_H01_h2.m'}
$evaluator=Join-Path $repo 'terminalLoh_wdro\src\run_stage73_detailed_oos_evaluator_h2.m'
$status=@{}; $started=Get-Date
Set-Content -LiteralPath (Join-Path $stageRoot 'RUNNER_STARTED.txt') -Value @("status=RUNNING","run_id=$RunId","runner_pid=$PID","started_at=$($started.ToString('o'))") -Encoding utf8
Log "RUNNER_START run_id=$RunId pid=$PID"

# Expensive phase first: exactly H04 SAA -> H04 DRO -> H02 SAA -> H02 DRO -> H01 SAA -> H01 DRO.
foreach($experiment in @('H04','H02','H01')){foreach($mode in @('saa','chi2_eta003')){
  $key="${experiment}_${mode}"; $case=Join-Path $stageRoot "$experiment\case-$mode"; $train=Join-Path $case 'TRAIN_DONE.txt'; $log=Join-Path $logRoot "${key}_train.log"
  $env:STAGE73_RUN_ID=$RunId; $env:STAGE73_TERMINAL_MODE=$mode; $env:STAGE73_EXPERIMENT_ID=$experiment
  if(Test-Path -LiteralPath $case){$status[$key]='FAIL_EXISTING_CASE_PRESERVED'; Log "TRAIN_SKIP_PRESERVE case=$key"; continue}
  Set-Content -LiteralPath (Join-Path $stateRoot "${key}_LAUNCHED.txt") -Value @("case=$key","launched_at=$(Get-Date -Format o)") -Encoding utf8
  Log "TRAIN_START case=$key"; $exit=Invoke-Matlab $launchers[$experiment] $log; Log "TRAIN_EXIT case=$key exit_code=$exit"
  $ws=Join-Path $case 'native_output\h2_workspace.mat'; $id=Join-Path $case 'parameter_identity.csv'
  if($exit -eq 0 -and (NonEmpty $train) -and (NonEmpty $ws) -and (NonEmpty $id)){
    $status[$key]='PASS'
    Set-Content -LiteralPath (Join-Path $case 'RUN_DONE.txt') -Value @('status=PASS','phase=training',"case=$key","policy=$ws","parameter_identity=$id","train_log=$log","completed_at=$(Get-Date -Format o)") -Encoding utf8
  }else{
    New-Item -ItemType Directory -Force -Path $case|Out-Null; $status[$key]="FAIL_TRAIN_EXIT_$exit"
    Set-Content -LiteralPath (Join-Path $case 'FAILED.txt') -Value @('phase=training',"exit_code=$exit","log=$log","failed_at=$(Get-Date -Format o)") -Encoding utf8
  }
}}
$num=@('Stage-73 numerical runs summary',"run_id=$RunId","runner_pid=$PID","started_at=$($started.ToString('o'))","completed_at=$(Get-Date -Format o)")
foreach($experiment in @('H04','H02','H01')){foreach($mode in @('saa','chi2_eta003')){$key="${experiment}_${mode}";$num+="$key=$($status[$key])";$num+="$key.result_dir=$(Join-Path $stageRoot "$experiment\case-$mode")";$num+="$key.train_log=$(Join-Path $logRoot "${key}_train.log")"}}
$numerical=Join-Path $stageRoot 'NUMERICAL_RUNS_DONE.txt'; Set-Content -LiteralPath $numerical -Value $num -Encoding utf8; Log 'NUMERICAL_RUNS_DONE_WRITTEN'

# Unified evaluation only after all six expensive trainings have ended. Failed policies are preserved and skipped independently.
foreach($experiment in @('Reference_08','H04','H02','H01')){foreach($mode in @('saa','chi2_eta003')){
  $key="${experiment}_${mode}"; if($experiment -ne 'Reference_08' -and $status[$key] -ne 'PASS'){Log "EVAL_SKIP_FAILED_TRAIN case=$key"; continue}
  $env:STAGE73_RUN_ID=$RunId; $env:STAGE73_TERMINAL_MODE=$mode; $env:STAGE73_EXPERIMENT_ID=$experiment
  $case=Join-Path $stageRoot "$experiment\case-$mode"; $elog=Join-Path $logRoot "${key}_eval.log"; Log "EVAL_START case=$key"; $exit=Invoke-Matlab $evaluator $elog; Log "EVAL_EXIT case=$key exit_code=$exit"
  if($exit -ne 0 -or -not(NonEmpty (Join-Path $case 'EVAL_DONE.txt'))){Set-Content -LiteralPath (Join-Path $case 'FAILED.txt') -Value @('phase=evaluation',"exit_code=$exit","log=$elog","failed_at=$(Get-Date -Format o)") -Encoding utf8}
}}

$allEval=$true; foreach($experiment in @('Reference_08','H04','H02','H01')){foreach($mode in @('saa','chi2_eta003')){if(-not(NonEmpty (Join-Path $stageRoot "$experiment\case-$mode\EVAL_DONE.txt"))){$allEval=$false}}}
if(-not $allEval){Set-Content -LiteralPath (Join-Path $stageRoot 'POSTPROCESS_SKIPPED_NUMERICAL_OR_EVAL_FAILURE.txt') -Value @('At least one policy/evaluation failed. Expensive results are preserved.',"see=$numerical","stopped_at=$(Get-Date -Format o)") -Encoding utf8; Log 'RUNNER_STOP incomplete_evaluation'; exit 2}

$rel="results/task-002-stage2b-b3-smoke/73-htt-transport-cost-sensitivity/$RunId"; $analysisRel="$rel/analysis/run-001"
$post=Join-Path $repo 'terminalLoh_wdro\src\postprocess_stage73_transport_cost.py'; $verify=Join-Path $repo 'terminalLoh_wdro\src\verify_stage73_transport_cost.py'
& $python $post --run-root $rel --output $analysisRel *> (Join-Path $logRoot 'postprocess.log'); $pe=$LASTEXITCODE
if($pe -ne 0){Set-Content -LiteralPath (Join-Path $stageRoot 'POSTPROCESS_FAILED.txt') -Value @("exit_code=$pe","log=$(Join-Path $logRoot 'postprocess.log')","failed_at=$(Get-Date -Format o)") -Encoding utf8; exit 3}
& $python $verify --run-root $rel --output $analysisRel *> (Join-Path $logRoot 'verification.log'); $ve=$LASTEXITCODE
if($ve -ne 0){Set-Content -LiteralPath (Join-Path $stageRoot 'VERIFICATION_FAILED.txt') -Value @("exit_code=$ve","log=$(Join-Path $logRoot 'verification.log')","failed_at=$(Get-Date -Format o)") -Encoding utf8; exit 4}
Set-Content -LiteralPath (Join-Path $stageRoot 'ALL_DONE.txt') -Value @('status=PASS',"numerical_summary=$numerical","analysis=$analysisRoot","main_log=$mainLog","completed_at=$(Get-Date -Format o)") -Encoding utf8; Log 'ALL_DONE_PASS'; exit 0
