param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^run-\d{3}$')]
    [string]$RunId
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$resultRoot = Join-Path $repoRoot "results\task-002-stage2b-b3-smoke\57-main-msp-converged-terminal-loh-ab\$RunId"
$matlab = 'D:\Program Files\MATLAB\R2022a\bin\matlab.exe'
$batchCommand = "cd('C:/Users/chaos/Desktop/biye/test/testH2_v2'); run_main_msp_h2_fixed_budget_ab"

if (Test-Path -LiteralPath $resultRoot) {
    throw "Refusing to overwrite existing Step-05B run directory: $resultRoot"
}
New-Item -ItemType Directory -Path $resultRoot | Out-Null

function Invoke-FixedBudgetCase {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('saa', 'chi2_eta003')]
        [string]$Mode
    )

    $caseDir = Join-Path $resultRoot "case-$Mode"
    New-Item -ItemType Directory -Path $caseDir | Out-Null
    $logFile = Join-Path $caseDir 'matlab_console.log'

    $env:STEP05B_RUN_ID = $RunId
    $env:STEP05B_TERMINAL_MODE = $Mode
    $argumentString = "-logfile `"$logFile`" -batch `"$batchCommand`""
    $process = Start-Process -FilePath $matlab -ArgumentList $argumentString `
        -WorkingDirectory $repoRoot -WindowStyle Hidden -PassThru -Wait
    if ($process.ExitCode -ne 0) {
        throw "$Mode MATLAB process failed with exit code $($process.ExitCode)."
    }

    $readableResult = Join-Path $caseDir 'native_output\benchmark\H2results_readable.csv'
    if (-not (Test-Path -LiteralPath $readableResult)) {
        throw "$Mode did not produce its readable result: $readableResult"
    }
    $row = Import-Csv -LiteralPath $readableResult | Select-Object -First 1
    if ([int]$row.stop_flag -ne 2) {
        throw "$Mode stopped with flag $($row.stop_flag), expected fixed-budget flag 2."
    }
}

Invoke-FixedBudgetCase -Mode 'saa'
Invoke-FixedBudgetCase -Mode 'chi2_eta003'
