param(
    [Parameter(Mandatory = $true)]
    [string]$WorkDir,
    [Parameter(Mandatory = $true)]
    [string]$PreparedSourceWorkDir
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$target = Join-Path $repo $WorkDir
$cloneScript = Join-Path $PSScriptRoot "run_step04CC6_isolated_processes.ps1"
$caseScript = Join-Path $PSScriptRoot "run_step04CC6_python_cases.ps1"

Push-Location $repo
try {
    & $cloneScript -WorkDir $WorkDir -Stage ClonePrepare -PreparedSourceWorkDir $PreparedSourceWorkDir
    & $caseScript -WorkDir $WorkDir -Stage State19
    & $caseScript -WorkDir $WorkDir -Stage Remaining
    @(
        "status=PASS",
        "controller=hidden_background_powershell",
        "case_process_type=PYTHON",
        "case_processes_sequential=1",
        "MATLAB_used_for_optimization_cases=0"
    ) | Set-Content -LiteralPath (Join-Path $target "BACKGROUND_CONTROLLER_COMPLETE.txt") -Encoding UTF8
}
catch {
    $message = $_ | Out-String
    if (Test-Path -LiteralPath $target) {
        @(
            "status=FAIL",
            "controller=hidden_background_powershell",
            "message=$message"
        ) | Set-Content -LiteralPath (Join-Path $target "BACKGROUND_CONTROLLER_FAILED.txt") -Encoding UTF8
    }
    throw
}
finally {
    Pop-Location
}
