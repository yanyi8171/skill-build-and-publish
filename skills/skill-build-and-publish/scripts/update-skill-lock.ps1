[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SkillName,
    [string]$WorkspaceRoot,
    [string]$TrueSourceRoot,
    [string]$Source = 'local',
    [ValidateSet('local', 'github', 'plugin', 'other')][string]$SourceType = 'local',
    [string]$SkillPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

Assert-SafeSkillName -Name $SkillName
if (-not $WorkspaceRoot) { $WorkspaceRoot = Get-DefaultWorkspaceRoot }
if (-not $TrueSourceRoot) {
    if ([System.IO.Path]::GetFullPath($WorkspaceRoot) -ne [System.IO.Path]::GetFullPath((Get-DefaultWorkspaceRoot))) {
        throw 'When overriding -WorkspaceRoot, also provide -TrueSourceRoot.'
    }
    $TrueSourceRoot = Get-DefaultTrueSourceRoot
}

$skillRoot = Join-Path $TrueSourceRoot $SkillName
$skillMd = Join-Path $skillRoot 'SKILL.md'
if (-not (Test-Path -LiteralPath $skillMd -PathType Leaf)) {
    throw "SKILL.md not found: $skillMd"
}

$lockPath = Join-Path $WorkspaceRoot 'skills-lock.json'
if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) {
    throw "skills-lock.json not found: $lockPath"
}
if (-not $SkillPath) { $SkillPath = "$SkillName/SKILL.md" }

$hash = Get-NormalizedSkillHash -SkillMdPath $skillMd
$original = [System.IO.File]::ReadAllText($lockPath)
$lock = $original | ConvertFrom-Json
if (-not $lock.skills) { throw 'skills-lock.json has no skills object.' }

$entry = [pscustomobject][ordered]@{
    source = $Source
    sourceType = $SourceType
    skillPath = $SkillPath.Replace('\', '/')
    computedHash = $hash
}
$existing = $lock.skills.PSObject.Properties | Where-Object { $_.Name -eq $SkillName } | Select-Object -First 1
if ($existing) {
    $existing.Value.source = $entry.source
    $existing.Value.sourceType = $entry.sourceType
    $existing.Value.skillPath = $entry.skillPath
    $existing.Value.computedHash = $entry.computedHash
}
else {
    $lock.skills | Add-Member -NotePropertyName $SkillName -NotePropertyValue $entry
}
$lock.generatedAt = (Get-Date).ToString('yyyy-MM-dd')

$backupRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'skills-lock-backups'
if (-not (Test-Path -LiteralPath $backupRoot)) { New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null }
$backupPath = Join-Path $backupRoot ("skills-lock-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
Write-Utf8NoBom -Path $backupPath -Content $original

try {
    $updated = ($lock | ConvertTo-Json -Depth 30) + "`n"
    Write-ExistingUtf8PreserveLink -Path $lockPath -Content $updated
    $verified = [System.IO.File]::ReadAllText($lockPath) | ConvertFrom-Json
    $verifiedEntry = $verified.skills.PSObject.Properties | Where-Object { $_.Name -eq $SkillName } | Select-Object -First 1
    if (-not $verifiedEntry -or $verifiedEntry.Value.computedHash -ne $hash) {
        throw 'Lock verification failed after write.'
    }
}
catch {
    $updateError = $_
    try {
        Write-ExistingUtf8PreserveLink -Path $lockPath -Content $original
    }
    catch {
        throw "Lock update failed and automatic restore also failed. Backup: $backupPath. Update error: $($updateError.Exception.Message). Restore error: $($_.Exception.Message)"
    }
    throw $updateError
}

$result = [pscustomobject][ordered]@{
    updated = $true
    skillName = $SkillName
    computedHash = $hash
    lockPath = $lockPath
    backupPath = $backupPath
}
'RESULT_JSON=' + ($result | ConvertTo-Json -Compress)
