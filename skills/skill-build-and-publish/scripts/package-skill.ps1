[CmdletBinding(DefaultParameterSetName = 'ByName')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'ByName')][string]$SkillName,
    [Parameter(Mandatory = $true, ParameterSetName = 'ByPath')][string]$SkillPath,
    [string]$TrueSourceRoot,
    [string]$OutputRoot,
    [string]$GitHubOwner = 'yanyi8171',
    [string]$Version,
    [string]$ThirdPartyNoticesPath,
    [string]$RepositoryNotice = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

if (-not $TrueSourceRoot) { $TrueSourceRoot = Get-DefaultTrueSourceRoot }
$sourcePath = Resolve-TrueSourceSkillPath -SkillName $SkillName -SkillPath $SkillPath -TrueSourceRoot $TrueSourceRoot
$preflight = Invoke-SkillPreflight -SkillPath $sourcePath
if (-not $preflight.ready) {
    $message = $preflight.errors -join '; '
    throw "Preflight failed: $message"
}

$skillMd = Join-Path $sourcePath 'SKILL.md'
$metadata = Get-SkillMetadata -SkillMdPath $skillMd
$SkillName = $metadata.Name
if (-not $Version) { $Version = $metadata.Version }
if ($Version -ne $metadata.Version) {
    throw "Requested version differs from SKILL.md metadata: $Version != $($metadata.Version)"
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
if (-not $OutputRoot) {
    $OutputRoot = Join-Path ([System.IO.Path]::GetTempPath()) "$SkillName-publish-$timestamp"
}
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
if (Test-Path -LiteralPath $OutputRoot) {
    throw "Output root already exists; overwrite refused: $OutputRoot"
}

$sourceHashBefore = Get-TreeHash -Root $sourcePath
$repoPath = Join-Path $OutputRoot 'repository'
$artifactPath = Join-Path $OutputRoot 'artifacts'
$skillDestination = Join-Path $repoPath "skills\$SkillName"
New-Item -ItemType Directory -Path $skillDestination -Force | Out-Null
New-Item -ItemType Directory -Path $artifactPath -Force | Out-Null
Copy-SafeSkillTree -Source $sourcePath -Destination $skillDestination

$templateRoot = Join-Path (Get-SkillBuildRoot) 'assets\repo-template'
$thirdPartySource = $ThirdPartyNoticesPath
if (-not $thirdPartySource) {
    $candidate = Join-Path $sourcePath 'THIRD_PARTY_NOTICES.md'
    if (Test-Path -LiteralPath $candidate) { $thirdPartySource = $candidate }
}
$thirdPartySection = ''
if ($thirdPartySource) {
    if (-not (Test-Path -LiteralPath $thirdPartySource -PathType Leaf)) {
        throw "Third-party notices file not found: $thirdPartySource"
    }
    Copy-Item -LiteralPath $thirdPartySource -Destination (Join-Path $repoPath 'THIRD_PARTY_NOTICES.md')
    $thirdPartySection = "## Third-party notices`n`nSee [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)."
}

$tokens = @{
    SKILL_NAME = $SkillName
    DESCRIPTION = $metadata.Description
    OWNER = $GitHubOwner
    AUTHOR = $metadata.Author
    VERSION = $Version
    YEAR = (Get-Date).ToString('yyyy')
    DATE = (Get-Date).ToString('yyyy-MM-dd')
    THIRD_PARTY_SECTION = $thirdPartySection
    REPOSITORY_NOTICE = $RepositoryNotice
}

$templateTargets = @(
    @{ Template = 'README.md.tmpl'; Target = 'README.md' },
    @{ Template = 'LICENSE.tmpl'; Target = 'LICENSE' },
    @{ Template = 'CHANGELOG.md.tmpl'; Target = 'CHANGELOG.md' },
    @{ Template = 'gitignore.tmpl'; Target = '.gitignore' },
    @{ Template = 'gitattributes.tmpl'; Target = '.gitattributes' },
    @{ Template = 'validate.yml.tmpl'; Target = '.github\workflows\validate.yml' }
)
foreach ($item in $templateTargets) {
    $content = Expand-TextTemplate -TemplatePath (Join-Path $templateRoot $item.Template) -Tokens $tokens
    Write-Utf8NoBom -Path (Join-Path $repoPath $item.Target) -Content $content
}
Write-Utf8NoBom -Path (Join-Path $repoPath 'VERSION') -Content ($Version + "`n")

$zipPath = Join-Path $artifactPath "$SkillName-v$Version.zip"
Compress-Archive -LiteralPath $skillDestination -DestinationPath $zipPath -CompressionLevel Optimal
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    $zipEntries = @($zip.Entries | ForEach-Object { $_.FullName.Replace('\', '/') })
    if ($zipEntries -notcontains "$SkillName/SKILL.md") {
        throw "Release ZIP has no top-level $SkillName/SKILL.md."
    }
}
finally {
    $zip.Dispose()
}

$sourceHashAfter = Get-TreeHash -Root $sourcePath
if ($sourceHashAfter -ne $sourceHashBefore) {
    throw 'Source skill changed during packaging; result rejected.'
}

$manifest = [pscustomobject][ordered]@{
    schemaVersion = 1
    skillName = $SkillName
    version = $Version
    sourcePath = $sourcePath
    sourceTreeHash = $sourceHashBefore
    repositoryPath = $repoPath
    zipPath = $zipPath
    githubOwner = $GitHubOwner
    repositoryName = $SkillName
    visibility = 'PUBLIC'
    requiresConfirmation = $true
    expectedConfirmation = "PUBLISH $GitHubOwner/$SkillName v$Version PUBLIC"
    packagedAt = (Get-Date).ToString('s')
}
$manifestPath = Join-Path $OutputRoot 'publish-manifest.json'
$preflightPath = Join-Path $OutputRoot 'preflight-report.json'
Write-JsonUtf8 -InputObject $manifest -Path $manifestPath
Write-JsonUtf8 -InputObject $preflight -Path $preflightPath

$result = [pscustomobject][ordered]@{
    packaged = $true
    skillName = $SkillName
    version = $Version
    repositoryPath = $repoPath
    zipPath = $zipPath
    manifestPath = $manifestPath
    sourceUnchanged = $true
    published = $false
    confirmationRequired = $manifest.expectedConfirmation
}
'RESULT_JSON=' + ($result | ConvertTo-Json -Compress)
