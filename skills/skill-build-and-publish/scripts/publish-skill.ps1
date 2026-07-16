[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ManifestPath,
    [Parameter(Mandatory = $true)][string]$ConfirmationText,
    [Parameter(Mandatory = $true)][switch]$ConfirmPublish
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath failed with exit code $LASTEXITCODE."
    }
}

if (-not $ConfirmPublish) { throw 'Explicit -ConfirmPublish is required.' }
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw "Manifest not found: $ManifestPath" }
$manifest = [System.IO.File]::ReadAllText($ManifestPath) | ConvertFrom-Json
if (-not $manifest.requiresConfirmation) { throw 'Manifest does not require a publish confirmation; refusing unsafe input.' }
if ($ConfirmationText -cne $manifest.expectedConfirmation) {
    throw "Confirmation mismatch. Expected exactly: $($manifest.expectedConfirmation)"
}

$repoPath = [System.IO.Path]::GetFullPath($manifest.repositoryPath)
$zipPath = [System.IO.Path]::GetFullPath($manifest.zipPath)
if (-not (Test-Path -LiteralPath $repoPath -PathType Container)) { throw "Repository staging path not found: $repoPath" }
if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) { throw "Release ZIP not found: $zipPath" }
if (Test-Path -LiteralPath (Join-Path $repoPath '.git')) { throw 'Staging directory already contains .git; create a fresh package before publishing.' }

foreach ($command in @('git', 'gh')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "Required command not found: $command" }
}
Invoke-CheckedCommand -FilePath 'gh' -Arguments @('auth', 'status')

$repoId = "$($manifest.githubOwner)/$($manifest.repositoryName)"
$previousErrorAction = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    & gh repo view $repoId --json name 2>$null | Out-Null
    $repoViewExitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $previousErrorAction
}
if ($repoViewExitCode -eq 0) {
    throw "Remote repository already exists; this v0.1 publisher only creates new repositories: $repoId"
}

Invoke-CheckedCommand -FilePath 'git' -Arguments @('-C', $repoPath, 'init')
Invoke-CheckedCommand -FilePath 'git' -Arguments @('-C', $repoPath, 'branch', '-M', 'main')
Invoke-CheckedCommand -FilePath 'git' -Arguments @('-C', $repoPath, 'config', 'user.name', $manifest.githubOwner)
Invoke-CheckedCommand -FilePath 'git' -Arguments @('-C', $repoPath, 'config', 'user.email', "$($manifest.githubOwner)@users.noreply.github.com")
Invoke-CheckedCommand -FilePath 'git' -Arguments @('-C', $repoPath, 'add', '.')
Invoke-CheckedCommand -FilePath 'git' -Arguments @('-C', $repoPath, 'commit', '-m', "feat: publish $($manifest.skillName) v$($manifest.version)")
Invoke-CheckedCommand -FilePath 'git' -Arguments @('-C', $repoPath, 'tag', '-a', "v$($manifest.version)", '-F', (Join-Path $repoPath 'CHANGELOG.md'))

$visibilityFlag = '--public'
if ($manifest.visibility -eq 'PRIVATE') { $visibilityFlag = '--private' }
Invoke-CheckedCommand -FilePath 'gh' -Arguments @('repo', 'create', $repoId, $visibilityFlag, '--source', $repoPath, '--remote', 'origin', '--push')
Invoke-CheckedCommand -FilePath 'git' -Arguments @('-C', $repoPath, 'push', 'origin', "v$($manifest.version)")
Invoke-CheckedCommand -FilePath 'gh' -Arguments @('release', 'create', "v$($manifest.version)", '--repo', $repoId, '--title', "v$($manifest.version)", '--notes-file', (Join-Path $repoPath 'CHANGELOG.md'), '--verify-tag', $zipPath)

$result = [pscustomobject][ordered]@{
    published = $true
    repository = "https://github.com/$repoId"
    release = "https://github.com/$repoId/releases/tag/v$($manifest.version)"
    skillName = $manifest.skillName
    version = $manifest.version
}
'RESULT_JSON=' + ($result | ConvertTo-Json -Compress)
