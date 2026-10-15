[CmdletBinding()]
param(
    [string]$GodotPath = 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe',
    [string]$ProjectPath = '',
    [ValidateRange(30, 300)]
    [int]$TimeoutSeconds = 120
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrEmpty($ProjectPath)) { $ProjectPath = Join-Path $PSScriptRoot '..' }
$projectRoot = (Resolve-Path -LiteralPath $ProjectPath).ProviderPath
if (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'project.godot'))) { throw 'Project file not found.' }
if (-not (Test-Path -LiteralPath $GodotPath)) { throw 'Godot executable not found.' }
$outputRoot = Join-Path $projectRoot ('artifacts\resource_shutdown_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
New-Item -ItemType Directory -Path $outputRoot | Out-Null
$results = [Collections.Generic.List[object]]::new()

foreach ($mode in @('menu', 'opening', 'gameplay')) {
    $stdoutPath = Join-Path $outputRoot ($mode + '.stdout.log')
    $stderrPath = Join-Path $outputRoot ($mode + '.stderr.log')
    $arguments = @('--path', ('"{0}"' -f $projectRoot), '--verbose',
        'res://tests/resource_shutdown_check.tscn', '--', $mode)
    $process = Start-Process -FilePath $GodotPath -ArgumentList $arguments -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    $null = $process.Handle
    try {
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) { throw "Shutdown timed out: $mode" }
        $process.WaitForExit()
        $logText = [IO.File]::ReadAllText($stdoutPath) + [IO.File]::ReadAllText($stderrPath)
        $pattern = '(?im)^.*(?:SCRIPT ERROR:|Parse Error:|Failed loading resource:|resources still in use|instances? (?:was|were) leaked|RIDs.*were leaked|allocations.*were leaked|never freed|Pages in use|RenderingServer::get_singleton\(\).*null|Parent node is busy).*$'
        $failures = @([regex]::Matches($logText, $pattern) | ForEach-Object { $_.Value.Trim() })
        $passed = $process.ExitCode -eq 0 -and $failures.Count -eq 0 -and $logText.Contains("CHECK: window close during $mode")
        $results.Add([ordered]@{ mode = $mode; passed = $passed; exit_code = $process.ExitCode; failures = $failures })
        Write-Output ("{0}: {1}; exit={2}; cleanup_failures={3}" -f $mode, $(if ($passed) { 'PASS' } else { 'FAIL' }), $process.ExitCode, $failures.Count)
        if (-not $passed) { $failures | ForEach-Object { Write-Output $_ }; break }
    } finally {
        if (-not $process.HasExited) { $process.Kill(); $null = $process.WaitForExit(5000) }
    }
}

$report = Join-Path $outputRoot 'report.json'
$overallPassed = $results.Count -eq 3 -and @($results | Where-Object { -not $_.passed }).Count -eq 0
[ordered]@{ passed = $overallPassed; project_path = $projectRoot; cases = @($results.ToArray()) } |
    ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $report -Encoding UTF8
Write-Output "Report: $report"
if (-not $overallPassed) { exit 1 }
