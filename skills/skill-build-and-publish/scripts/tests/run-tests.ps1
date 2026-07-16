Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptsRoot = Split-Path -Parent $PSScriptRoot
$skillRoot = Split-Path -Parent $scriptsRoot
. (Join-Path $scriptsRoot 'common.ps1')

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}

$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\', '/')
$testRoot = Join-Path $tempBase ("skill-build-and-publish-tests-{0}" -f ([guid]::NewGuid().ToString('N')))
$workspace = Join-Path $testRoot 'workspace'
$trueSource = Join-Path $testRoot 'true-source'

try {
    New-Item -ItemType Directory -Path $workspace -Force | Out-Null
    New-Item -ItemType Directory -Path $trueSource -Force | Out-Null
    $lockObject = [pscustomobject][ordered]@{
        version = 2
        generatedAt = '2000-01-01'
        hashScheme = 'sha256 of SKILL.md bytes with CRLF normalized to LF'
        note = 'test fixture'
        skills = [pscustomobject]@{}
    }
    Write-JsonUtf8 -InputObject $lockObject -Path (Join-Path $workspace 'skills-lock.json')

    & (Join-Path $scriptsRoot 'new-skill.ps1') `
        -Name 'example-public-skill' `
        -DescriptionZh 'Create a deterministic example skill for local pipeline validation.' `
        -DescriptionEn 'Use for normal, missing-input, and boundary test cases.' `
        -TrueSourceRoot $trueSource | Out-Null

    $example = Join-Path $trueSource 'example-public-skill'
    Assert-True (Test-Path -LiteralPath (Join-Path $example 'SKILL.md')) 'new-skill creates SKILL.md'
    Assert-True (Test-Path -LiteralPath (Join-Path $example 'evals\evals.json')) 'new-skill creates evals.json'

    $draft = [System.IO.File]::ReadAllText((Join-Path $example 'SKILL.md'))
    $draft = [regex]::Replace($draft, '<!--\s*TODO_PUBLICATION.*?-->', '', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    Write-Utf8NoBom -Path (Join-Path $example 'SKILL.md') -Content $draft

    $clean = Invoke-SkillPreflight -SkillPath $example
    Assert-True $clean.ready 'completed example passes preflight'

    & (Join-Path $scriptsRoot 'update-skill-lock.ps1') `
        -SkillName 'example-public-skill' `
        -WorkspaceRoot $workspace `
        -TrueSourceRoot $trueSource | Out-Null
    $updatedLock = [System.IO.File]::ReadAllText((Join-Path $workspace 'skills-lock.json')) | ConvertFrom-Json
    Assert-True ($updatedLock.skills.'example-public-skill'.computedHash -eq (Get-NormalizedSkillHash -SkillMdPath (Join-Path $example 'SKILL.md'))) 'lock hash matches normalized SKILL.md'

    $secretFile = Join-Path $example 'secret-test.txt'
    $fakeToken = 'gh' + 'p_' + ('1' * 30)
    Write-Utf8NoBom -Path $secretFile -Content $fakeToken
    $secretResult = Invoke-SkillPreflight -SkillPath $example
    Assert-True (-not $secretResult.ready) 'GitHub token blocks preflight'
    Remove-Item -LiteralPath $secretFile

    $pathFile = Join-Path $example 'private-path-test.txt'
    $slash = [char]92
    $fakePrivatePath = 'C:' + $slash + 'Users' + $slash + 'sample-user' + $slash + 'private' + $slash + 'file.txt'
    Write-Utf8NoBom -Path $pathFile -Content $fakePrivatePath
    $pathResult = Invoke-SkillPreflight -SkillPath $example
    Assert-True (-not $pathResult.ready) 'Windows user path blocks preflight'
    Remove-Item -LiteralPath $pathFile

    $sourceHash = Get-TreeHash -Root $example
    $packageRoot = Join-Path $testRoot 'package-output'
    $packageOutput = & (Join-Path $scriptsRoot 'package-skill.ps1') `
        -SkillPath $example `
        -OutputRoot $packageRoot `
        -GitHubOwner 'example-owner' `
        -RepositoryNotice 'PERSONAL WORKSPACE NOTICE'
    $resultLine = $packageOutput | Where-Object { $_ -like 'RESULT_JSON=*' } | Select-Object -Last 1
    $packageResult = $resultLine.Substring('RESULT_JSON='.Length) | ConvertFrom-Json
    Assert-True $packageResult.packaged 'package reports success'
    Assert-True (Test-Path -LiteralPath $packageResult.repositoryPath) 'repository staging exists'
    Assert-True (Test-Path -LiteralPath $packageResult.zipPath) 'release ZIP exists'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $packageResult.repositoryPath '.git'))) 'package does not initialize git'
    Assert-True ((Get-TreeHash -Root $example) -eq $sourceHash) 'package leaves source unchanged'
    $generatedReadme = [System.IO.File]::ReadAllText((Join-Path $packageResult.repositoryPath 'README.md'))
    Assert-True $generatedReadme.Contains('PERSONAL WORKSPACE NOTICE') 'README includes repository-specific compatibility notice'
    $generatedWorkflow = [System.IO.File]::ReadAllText((Join-Path $packageResult.repositoryPath '.github/workflows/validate.yml'))
    Assert-True $generatedWorkflow.Contains('(?m)^${field}:') 'workflow safely delimits frontmatter field variable'
    Assert-True (-not $generatedWorkflow.Contains('(?m)^$field:')) 'workflow excludes invalid PowerShell variable syntax'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($packageResult.zipPath)
    try {
        $zipEntries = @($zip.Entries | ForEach-Object { $_.FullName.Replace('\', '/') })
        Assert-True ($zipEntries -contains 'example-public-skill/SKILL.md') 'ZIP contains top-level skill folder and SKILL.md'
    }
    finally {
        $zip.Dispose()
    }

    $gateBlocked = $false
    try {
        & (Join-Path $scriptsRoot 'publish-skill.ps1') `
            -ManifestPath $packageResult.manifestPath `
            -ConfirmPublish `
            -ConfirmationText 'WRONG CONFIRMATION' | Out-Null
    }
    catch {
        $gateBlocked = $_.Exception.Message -like 'Confirmation mismatch*'
    }
    Assert-True $gateBlocked 'publish gate rejects mismatched confirmation before network access'

    $extractPath = Join-Path (Get-DefaultTrueSourceRoot) 'extract-youtube-creator-transcripts'
    if (Test-Path -LiteralPath $extractPath) {
        $extractResult = Invoke-SkillPreflight -SkillPath $extractPath
        Assert-True $extractResult.ready 'existing published transcript skill passes preflight'
    }

    $selfResult = Invoke-SkillPreflight -SkillPath $skillRoot
    Assert-True $selfResult.ready 'skill-build-and-publish passes its own preflight'

    'TEST_RESULT=PASS'
}
finally {
    $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
    if ($resolvedTestRoot.StartsWith($tempBase + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedTestRoot) -like 'skill-build-and-publish-tests-*') {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
