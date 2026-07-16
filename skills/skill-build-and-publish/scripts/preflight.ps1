[CmdletBinding(DefaultParameterSetName = 'ByName')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'ByName')][string]$SkillName,
    [Parameter(Mandatory = $true, ParameterSetName = 'ByPath')][string]$SkillPath,
    [string]$TrueSourceRoot,
    [string]$ReportPath,
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

if (-not $TrueSourceRoot) { $TrueSourceRoot = Get-DefaultTrueSourceRoot }
$resolved = Resolve-TrueSourceSkillPath -SkillName $SkillName -SkillPath $SkillPath -TrueSourceRoot $TrueSourceRoot
$result = Invoke-SkillPreflight -SkillPath $resolved

if ($ReportPath) {
    Write-JsonUtf8 -InputObject $result -Path $ReportPath
}

if ($AsJson) {
    $result | ConvertTo-Json -Depth 20 -Compress
}
else {
    "Skill: $($result.skillName)"
    "Path: $($result.skillPath)"
    "Version: $($result.version)"
    "Ready: $($result.ready)"
    "Errors: $($result.errorCount); warnings: $($result.warningCount)"
    foreach ($item in $result.errors) { "ERROR: $item" }
    foreach ($item in $result.warnings) { "WARN: $item" }
    'RESULT_JSON=' + ($result | ConvertTo-Json -Depth 20 -Compress)
}

if (-not $result.ready) { exit 1 }
