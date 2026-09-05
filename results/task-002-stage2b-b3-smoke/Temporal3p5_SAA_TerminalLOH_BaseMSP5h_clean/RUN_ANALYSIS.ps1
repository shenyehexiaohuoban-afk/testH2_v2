param([Parameter(Mandatory=$true)][string]$InputRoot,[Parameter(Mandatory=$true)][string]$OutputRoot,[string]$BaseRoot,[string]$CandidateId='CANDIDATE')
$ErrorActionPreference='Stop'; $packageRoot=$PSScriptRoot
$config=@{}; Get-Content (Join-Path $packageRoot 'RUN_CONFIG.txt') | ForEach-Object { if ($_ -match '^([^#=]+)=(.*)$') { $config[$matches[1].Trim()]=$matches[2].Trim() } }
if ($config['RUN_ANALYSIS'] -ne '1') { throw 'Template is execution-disabled. Set RUN_ANALYSIS=1 in a derived experiment package.' }
$script=Join-Path $packageRoot 'analysis\python\run_candidate_oos_analysis.py'
$resolvedInput=Resolve-Path $InputRoot
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$resolvedOutput=Resolve-Path $OutputRoot
if ([string]::IsNullOrWhiteSpace($BaseRoot)) { throw 'BaseRoot is required for paired analysis.' }
$resolvedBase=Resolve-Path $BaseRoot
python $script --base-root $resolvedBase --candidate-root $resolvedInput --output-root $resolvedOutput --candidate-id $CandidateId --oos-mode $config['ANALYSIS_MODE']
python (Join-Path $packageRoot 'analysis\python\run_candidate_oos_closeout.py') --analysis-root $resolvedOutput
