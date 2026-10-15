# Real graphical-editor regression: rebuild script docs and check saved scene loading.
[CmdletBinding()]
param(
    [string]$GodotPath = 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe',
    [string]$ProjectPath = (Join-Path $PSScriptRoot '..'),
    [ValidateRange(1, 20)]
    [int]$Rounds = 3,
    [ValidateRange(30, 600)]
    [int]$TimeoutSeconds = 120
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath($ProjectPath).TrimEnd('\', '/')
$projectPrefix = $projectRoot + [IO.Path]::DirectorySeparatorChar

function Assert-ProjectPath([string]$Path) {
    $absolutePath = [IO.Path]::GetFullPath($Path)
    if (-not $absolutePath.StartsWith($projectPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing a path outside this project: $absolutePath"
    }
    # A junction beneath the project must not turn a local cache move into an external move.
    $ancestor = $absolutePath
    while ($ancestor.Length -gt $projectRoot.Length) {
        if (Test-Path -LiteralPath $ancestor) {
            $item = Get-Item -LiteralPath $ancestor -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing a path through a junction or symbolic link: $ancestor"
            }
        }
        $ancestor = [IO.Path]::GetDirectoryName($ancestor)
    }
    return $absolutePath
}

function Get-SavedScenePaths([string]$LayoutPath) {
    $layoutText = [IO.File]::ReadAllText($LayoutPath)
    $section = [regex]::Match($layoutText, '(?ms)^\[EditorNode\]\r?\n(?<body>.*?)(?=^\[|\z)')
    if (-not $section.Success) { throw 'The saved editor layout has no EditorNode section.' }
    $sceneSetting = [regex]::Match($section.Groups['body'].Value, '(?m)^\s*open_scenes\s*=\s*PackedStringArray\((?<values>[^\r\n]*)\)\s*$')
    $currentSetting = [regex]::Match($section.Groups['body'].Value, '(?m)^\s*current_scene\s*=\s*(?<value>"(?:\\.|[^"\\])*")\s*$')
    if (-not $sceneSetting.Success -or -not $currentSetting.Success) {
        throw 'Cannot read open_scenes/current_scene from the saved editor layout.'
    }
    $stringPattern = '"(?:\\.|[^"\\])*"'
    $values = $sceneSetting.Groups['values'].Value
    if ([regex]::Replace($values, $stringPattern, '').Trim(' ', "`t", ',').Length -ne 0) {
        throw 'The saved open_scenes array contains an unsupported value.'
    }
    $scenes = @([regex]::Matches($values, $stringPattern) | ForEach-Object { $_.Value | ConvertFrom-Json })
    return [pscustomobject]@{
        Scenes = $scenes
        CurrentScene = ($currentSetting.Groups['value'].Value | ConvertFrom-Json)
    }
}

function Get-EditorProjectPath([string]$CommandLine) {
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $null }
    if (-not ('GodotStartupCheck.NativeArguments' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace GodotStartupCheck {
    public static class NativeArguments {
        [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern IntPtr CommandLineToArgvW(string commandLine, out int argc);
        [DllImport("kernel32.dll")]
        public static extern IntPtr LocalFree(IntPtr memory);
    }
}
'@
    }
    $argumentCount = 0
    $argumentVector = [GodotStartupCheck.NativeArguments]::CommandLineToArgvW($CommandLine, [ref]$argumentCount)
    if ($argumentVector -eq [IntPtr]::Zero) { throw 'Cannot inspect the command line of a running Godot process.' }
    try {
        $arguments = @(for ($index = 0; $index -lt $argumentCount; $index++) {
            $argumentPointer = [Runtime.InteropServices.Marshal]::ReadIntPtr($argumentVector, $index * [IntPtr]::Size)
            [Runtime.InteropServices.Marshal]::PtrToStringUni($argumentPointer)
        })
    } finally {
        $null = [GodotStartupCheck.NativeArguments]::LocalFree($argumentVector)
    }
    $isEditor = $false
    $editorPath = $null
    for ($index = 1; $index -lt $arguments.Count; $index++) {
        if ($arguments[$index] -ceq '--') { break }
        if ($arguments[$index] -ceq '--editor' -or $arguments[$index] -ceq '-e') { $isEditor = $true }
        if ($arguments[$index] -ceq '--path' -and $index + 1 -lt $arguments.Count) {
            $editorPath = $arguments[++$index]
        }
    }
    if (-not $isEditor -or [string]::IsNullOrEmpty($editorPath)) { return $null }
    # Resolve only absolute paths: another process's relative working directory is unknown.
    if ($editorPath -notmatch '^(?:[A-Za-z]:[\\/]|[\\/]{2})') { return $null }
    return [IO.Path]::GetFullPath($editorPath.Replace('/', '\')).TrimEnd('\', '/')
}

function Assert-NoRunningEditor {
    $conflicts = @(Get-CimInstance -ClassName Win32_Process -Filter "Name LIKE 'godot%.exe'" | Where-Object {
        $runningProject = Get-EditorProjectPath $_.CommandLine
        $null -ne $runningProject -and $runningProject.Equals($projectRoot, [StringComparison]::OrdinalIgnoreCase)
    })
    if ($conflicts.Count -gt 0) {
        $conflictingIds = ($conflicts | ForEach-Object { $_.ProcessId }) -join ', '
        throw "Godot editor is already running for '$projectRoot' (PID: $conflictingIds). Close the target project's editor, or use -ProjectPath with an independent copy. No existing process was stopped."
    }
}

if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot executable not found: $GodotPath"
}
$GodotPath = (Resolve-Path -LiteralPath $GodotPath).ProviderPath
$projectFile = Assert-ProjectPath (Join-Path $projectRoot 'project.godot')
$layoutPath = Assert-ProjectPath (Join-Path $projectRoot '.godot\editor\editor_layout.cfg')
foreach ($requiredFile in @($projectFile, $layoutPath)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Required project file not found: $requiredFile"
    }
}
Assert-NoRunningEditor

$outputRoot = Assert-ProjectPath (Join-Path $projectRoot ('artifacts\editor_startup_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff')))
New-Item -ItemType Directory -Path $outputRoot | Out-Null
$docCache = Assert-ProjectPath (Join-Path $projectRoot '.godot\editor\editor_script_doc_cache.res')
$roundResults = [Collections.Generic.List[object]]::new()
$overallPassed = $true

for ($round = 1; $round -le $Rounds; $round++) {
    $roundRoot = Assert-ProjectPath (Join-Path $outputRoot ('round_{0:D2}' -f $round))
    New-Item -ItemType Directory -Path $roundRoot | Out-Null
    $stdoutPath = Join-Path $roundRoot 'stdout.log'
    $stderrPath = Join-Path $roundRoot 'stderr.log'
    $engineLogPath = Join-Path $roundRoot 'godot.log'
    $backupPath = Assert-ProjectPath (Join-Path $roundRoot 'editor_script_doc_cache.before.res')
    $failures = [Collections.Generic.List[string]]::new()
    $editorProcess = $null
    $exitCode = $null
    $timedOut = $false
    $cacheBackedUp = $false
    $expectedScenes = @()
    $expectedCurrentScene = ''
    $layoutRead = $false
    $startedAt = Get-Date
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()

    try {
        Assert-NoRunningEditor
        $savedLayout = Get-SavedScenePaths $layoutPath
        $expectedScenes = @($savedLayout.Scenes)
        $expectedCurrentScene = $savedLayout.CurrentScene
        $layoutRead = $true
        # This is the only cache we move. Keep imported assets, layout and project settings intact.
        if (Test-Path -LiteralPath $docCache -PathType Leaf) {
            $null = Assert-ProjectPath $docCache
            $null = Assert-ProjectPath $backupPath
            Move-Item -LiteralPath $docCache -Destination $backupPath
            $cacheBackedUp = $true
        }
        $arguments = @(
            '--path', ('"{0}"' -f $projectRoot),
            '--editor',
            '--verbose', '--max-fps', '60', '--quit-after', '1800',
            '--log-file', ('"{0}"' -f $engineLogPath)
        )
        $editorProcess = Start-Process -FilePath $GodotPath -ArgumentList $arguments `
            -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        # Retain the native handle before exit so Windows PowerShell can read ExitCode.
        $null = $editorProcess.Handle
        Write-Output ('Round {0}/{1}: editor PID {2}, rebuilding script documentation.' -f $round, $Rounds, $editorProcess.Id)

        while (-not $editorProcess.WaitForExit(1000)) {
            if ($stopwatch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
                $timedOut = $true
                $failures.Add("Editor did not exit within $TimeoutSeconds seconds.")
                # Only the Process instance started by this round is eligible for termination.
                $editorProcess.Kill()
                $null = $editorProcess.WaitForExit(5000)
                break
            }
        }
        if ($editorProcess.HasExited) {
            $editorProcess.WaitForExit()
            $exitCode = $editorProcess.ExitCode
        }
    } catch {
        $failures.Add($_.Exception.Message)
    } finally {
        if ($null -ne $editorProcess -and -not $editorProcess.HasExited) {
            $editorProcess.Kill()
            $null = $editorProcess.WaitForExit(5000)
        }
        $stopwatch.Stop()
    }

    $logParts = foreach ($logPath in @($stdoutPath, $stderrPath, $engineLogPath)) {
        if (Test-Path -LiteralPath $logPath -PathType Leaf) {
            [IO.File]::ReadAllText($logPath)
        }
    }
    $logText = $logParts -join "`n"
    # These are completed resource loads, not a direct EditorInterface tab-state query.
    $loadedSavedScenes = @($expectedScenes | Where-Object { $logText.Contains("Completed load for: '$_' remapped ") })
    $missingSavedScenes = @($expectedScenes | Where-Object { -not $logText.Contains("Completed load for: '$_' remapped ") })
    $currentSceneLoaded = [string]::IsNullOrEmpty($expectedCurrentScene) -or $logText.Contains("Completed load for: '$expectedCurrentScene' remapped ")
    $cacheRegenerated = $false
    $cacheBytes = 0L
    if (Test-Path -LiteralPath $docCache -PathType Leaf) {
        $newCache = Get-Item -LiteralPath $docCache
        $cacheBytes = $newCache.Length
        $cacheRegenerated = $cacheBytes -gt 0 -and $newCache.LastWriteTimeUtc -ge $startedAt.ToUniversalTime().AddSeconds(-2)
    }
    if ($null -eq $exitCode -or $exitCode -ne 0) { $failures.Add("Editor exit code was $exitCode; expected 0.") }
    foreach ($missingScene in $missingSavedScenes) { $failures.Add("Saved scene has no completed load record: $missingScene") }
    if (-not $currentSceneLoaded) { $failures.Add("Saved current scene has no completed load record: $expectedCurrentScene") }
    if (-not $cacheRegenerated) { $failures.Add('No fresh, nonempty script documentation cache was generated.') }

    $failurePatterns = @(
        '(?im)^ERROR:.*(?:Error copying library|Can.t open (?:GDExtension )?dynamic library|Failed to create an autoload).*$',
        '(?im)^SCRIPT ERROR:.*$',
        '(?im)^(?:ERROR:\s*)?(?:Failed|Could not|Cannot|Unable) to (?:load|open|parse|import|instantiate) (?:script|resource|scene)\b.*$',
        '(?im)^ERROR:\s*Failed loading (?:resource|script|scene)\b.*$',
        '(?im)^ERROR:\s*(?:Cannot|Could not|Failed to) open file.*(?:res://|\.gd|\.tscn|\.tres).*$',
        '(?im)^ERROR:\s*(?:Error loading resource|Resource file not found|No loader found|Parse Error).*$',
        '(?im)^.*Script docs haven.t been properly loaded or regenerated.*$'
    )
    foreach ($pattern in $failurePatterns) {
        foreach ($match in [regex]::Matches($logText, $pattern)) {
            $failures.Add($match.Value.Trim())
        }
    }
    # Vulkan loader GENERAL messages (including missing overlay DLLs) remain in the logs;
    # they are not evidence of a failed GDScript/resource parse.
    $uniqueFailures = @($failures | Select-Object -Unique)
    $passed = $uniqueFailures.Count -eq 0
    $result = [ordered]@{
        round = $round
        passed = $passed
        started_at = $startedAt.ToString('o')
        duration_seconds = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 2)
        process_id = $(if ($null -ne $editorProcess) { $editorProcess.Id } else { $null })
        exit_code = $exitCode
        timed_out = $timedOut
        saved_layout_read = $layoutRead
        saved_scenes = $expectedScenes
        loaded_saved_scenes = $loadedSavedScenes.Count
        all_saved_scenes_loaded = $layoutRead -and $missingSavedScenes.Count -eq 0
        missing_saved_scenes = $missingSavedScenes
        saved_current_scene = $expectedCurrentScene
        saved_current_scene_loaded = $layoutRead -and $currentSceneLoaded
        doc_cache_backed_up = $cacheBackedUp
        doc_cache_regenerated = $cacheRegenerated
        doc_cache_bytes = $cacheBytes
        failures = $uniqueFailures
        logs = @{ stdout = $stdoutPath; stderr = $stderrPath; godot = $engineLogPath }
    }
    $roundResults.Add($result)
    $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $roundRoot 'result.json') -Encoding UTF8
    Write-Output ('Round {0}: {1}; exit={2}; loaded_saved_scenes={3}/{4}; current_scene_loaded={5}; new_doc_cache={6}; seconds={7}' -f $round, $(if ($passed) { 'PASS' } else { 'FAIL' }), $exitCode, $result.loaded_saved_scenes, $expectedScenes.Count, $currentSceneLoaded, $cacheRegenerated, $result.duration_seconds)
    if (-not $passed) {
        $overallPassed = $false
        $uniqueFailures | ForEach-Object { Write-Output "  $_" }
        break
    }
}

$reportPath = Join-Path $outputRoot 'report.json'
[ordered]@{
    passed = $overallPassed -and $roundResults.Count -eq $Rounds
    godot_path = $GodotPath
    project_path = $projectRoot
    requested_rounds = $Rounds
    completed_rounds = $roundResults.Count
    rounds = @($roundResults.ToArray())
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8
Write-Output "Report: $reportPath"
if (-not $overallPassed) { exit 1 }
exit 0
