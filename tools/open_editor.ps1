# Keep one graphical editor per project: Windows GDExtensions share a temporary DLL name.
[CmdletBinding()]
param(
    [string]$GodotPath = 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe',
    [string]$ProjectPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrEmpty($ProjectPath)) { $ProjectPath = Join-Path $PSScriptRoot '..' }
$projectRoot = (Resolve-Path -LiteralPath $ProjectPath).ProviderPath.TrimEnd('\', '/')
if (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'project.godot') -PathType Leaf)) {
    throw "Godot project not found: $projectRoot"
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot executable not found: $GodotPath"
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace PlanetEditorLauncher {
    public static class Native {
        [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern IntPtr CommandLineToArgvW(string commandLine, out int argc);
        [DllImport("kernel32.dll")]
        public static extern IntPtr LocalFree(IntPtr memory);
        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr window, int command);
        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr window);
    }
}
'@

function Test-ProjectEditor([string]$CommandLine) {
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $false }
    $argumentCount = 0
    $argumentVector = [PlanetEditorLauncher.Native]::CommandLineToArgvW($CommandLine, [ref]$argumentCount)
    if ($argumentVector -eq [IntPtr]::Zero) { throw 'Cannot inspect Godot process arguments.' }
    try {
        $arguments = @(for ($index = 0; $index -lt $argumentCount; $index++) {
            $pointer = [Runtime.InteropServices.Marshal]::ReadIntPtr($argumentVector, $index * [IntPtr]::Size)
            [Runtime.InteropServices.Marshal]::PtrToStringUni($pointer)
        })
    } finally {
        $null = [PlanetEditorLauncher.Native]::LocalFree($argumentVector)
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
    if (-not $isEditor -or [string]::IsNullOrEmpty($editorPath)) { return $false }
    if ($editorPath -notmatch '^(?:[A-Za-z]:[\\/]|[\\/]{2})') { return $false }
    $absolutePath = [IO.Path]::GetFullPath($editorPath.Replace('/', '\')).TrimEnd('\', '/')
    return $absolutePath.Equals($projectRoot, [StringComparison]::OrdinalIgnoreCase)
}

# Serialize simultaneous double-clicks until the new process appears in the process list.
$pathBytes = [Text.Encoding]::UTF8.GetBytes($projectRoot.ToLowerInvariant())
$hash = [Security.Cryptography.SHA256]::Create()
try { $projectKey = [BitConverter]::ToString($hash.ComputeHash($pathBytes)).Replace('-', '') }
finally { $hash.Dispose() }
$launchMutex = [Threading.Mutex]::new($false, ('Local\PlanetEditor_' + $projectKey))
$ownsMutex = $false
try {
    try { $ownsMutex = $launchMutex.WaitOne(15000) }
    catch [Threading.AbandonedMutexException] { $ownsMutex = $true }
    if (-not $ownsMutex) { throw 'Another project launcher is busy. Try again shortly.' }
    $editors = @(Get-CimInstance Win32_Process -Filter "Name LIKE 'godot%.exe'" | Where-Object {
        Test-ProjectEditor $_.CommandLine
    })
    if ($editors.Count -gt 0) {
        $existing = Get-Process -Id $editors[0].ProcessId
        if ($existing.MainWindowHandle -ne [IntPtr]::Zero) {
            $null = [PlanetEditorLauncher.Native]::ShowWindow($existing.MainWindowHandle, 9)
            $null = [PlanetEditorLauncher.Native]::SetForegroundWindow($existing.MainWindowHandle)
        }
        Write-Output "Reused project editor (PID $($existing.Id)). No second editor was started."
        return
    }
    $arguments = @('--path', ('"{0}"' -f $projectRoot), '--editor')
    $editor = Start-Process -FilePath $GodotPath -ArgumentList $arguments -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru
    Write-Output "Started project editor (PID $($editor.Id))."
} finally {
    if ($ownsMutex) { $launchMutex.ReleaseMutex() }
    $launchMutex.Dispose()
}
