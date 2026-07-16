[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$DescriptionZh,
    [string]$DescriptionEn = '',
    [string]$Author = 'yy1675430-stack',
    [string]$Version = '0.1.0',
    [string]$License = 'MIT',
    [string[]]$TestPrompt,
    [string]$ExpectedOutput = 'The skill completes the task and returns a verifiable result.',
    [string]$TrueSourceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

Assert-SafeSkillName -Name $Name
if ($Version -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') {
    throw "Version is not valid semantic versioning: $Version"
}
if (-not $TrueSourceRoot) { $TrueSourceRoot = Get-DefaultTrueSourceRoot }
if (-not (Test-Path -LiteralPath $TrueSourceRoot)) {
    New-Item -ItemType Directory -Path $TrueSourceRoot -Force | Out-Null
}

$target = Join-Path $TrueSourceRoot $Name
if (Test-Path -LiteralPath $target) {
    throw "Target skill already exists; overwrite refused: $target"
}

$templateRoot = Join-Path (Get-SkillBuildRoot) 'assets\skill-template'
$description = $DescriptionZh.Trim()
if ($DescriptionEn.Trim()) { $description += ' ' + $DescriptionEn.Trim() }
$tokens = @{
    SKILL_NAME = $Name
    DESCRIPTION = $description
    AUTHOR = $Author
    VERSION = $Version
    LICENSE = $License
}

New-Item -ItemType Directory -Path (Join-Path $target 'evals') -Force | Out-Null
$skillText = Expand-TextTemplate -TemplatePath (Join-Path $templateRoot 'SKILL.md.tmpl') -Tokens $tokens
Write-Utf8NoBom -Path (Join-Path $target 'SKILL.md') -Content $skillText

if (-not $TestPrompt -or $TestPrompt.Count -eq 0) {
    $TestPrompt = @(
        "Use $Name for a normal task.",
        "Use $Name when required input is missing and identify the gap first.",
        "This request resembles $Name but should not trigger it; explain the boundary."
    )
}
$evals = New-Object System.Collections.Generic.List[object]
for ($i = 0; $i -lt $TestPrompt.Count; $i++) {
    $evals.Add([pscustomobject][ordered]@{
        id = $i + 1
        prompt = $TestPrompt[$i]
        expected_output = $ExpectedOutput
        files = @()
    })
}
$evalObject = [pscustomobject][ordered]@{ skill_name = $Name; evals = @($evals.ToArray()) }
Write-JsonUtf8 -InputObject $evalObject -Path (Join-Path $target 'evals\evals.json')

$result = [pscustomobject][ordered]@{
    created = $true
    skillName = $Name
    skillPath = $target
    registered = $false
    nextStep = 'Complete SKILL.md and tests, then update skills-lock.json after preflight passes.'
}
'RESULT_JSON=' + ($result | ConvertTo-Json -Compress)
