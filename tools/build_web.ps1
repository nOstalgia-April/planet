[CmdletBinding()]
param(
    [string]$GodotPath = 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe',
    [string]$OutputPath = '',
    [string]$SdkZip = ''
)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $OutputPath) { $OutputPath = Join-Path $root 'output/planet-web' }
$artifacts = Join-Path $root 'artifacts'
New-Item -ItemType Directory -Path $artifacts -Force | Out-Null
if (-not (Test-Path (Join-Path $artifacts '.gdignore'))) { New-Item -ItemType File -Path (Join-Path $artifacts '.gdignore') | Out-Null }
$jobRoot = Join-Path $artifacts ('web_build_' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $jobRoot | Out-Null
try {
    $arguments = @((Join-Path $PSScriptRoot 'build_web.py'), '--godot', $GodotPath, '--stage', (Join-Path $jobRoot 'project'), '--output', [IO.Path]::GetFullPath($OutputPath))
    if ($SdkZip) { $arguments += @('--sdk-zip', $SdkZip) }
    & python @arguments
    if ($LASTEXITCODE -ne 0) { throw 'Web build failed. See the errors printed above.' }
} finally {
    $target = [IO.Path]::GetFullPath($jobRoot)
    if (-not $target.StartsWith($artifacts + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe cleanup target.' }
    Remove-Item -LiteralPath $target -Recurse -Force
    if (Test-Path -LiteralPath $target) { throw "Staging cleanup failed: $target" }
}
