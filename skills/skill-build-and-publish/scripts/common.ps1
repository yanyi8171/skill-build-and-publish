Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Utf8NoBomEncoding {
    return New-Object System.Text.UTF8Encoding($false)
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )

    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Content, (Get-Utf8NoBomEncoding))
}

function Write-ExistingUtf8PreserveLink {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Existing file not found: $Path"
    }
    $bytes = (Get-Utf8NoBomEncoding).GetBytes($Content)
    $stream = New-Object System.IO.FileStream(
        $Path,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::Read
    )
    try {
        $stream.SetLength(0)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
    }
    finally {
        $stream.Dispose()
    }
}

function Get-SkillBuildRoot {
    return Split-Path -Parent $PSScriptRoot
}

function Get-DefaultTrueSourceRoot {
    return Split-Path -Parent (Get-SkillBuildRoot)
}

function Get-DefaultWorkspaceRoot {
    $trueSource = Get-DefaultTrueSourceRoot
    $agentPack = Split-Path -Parent $trueSource
    return Split-Path -Parent $agentPack
}

function Assert-SafeSkillName {
    param([Parameter(Mandatory = $true)][string]$Name)

    if ($Name -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
        throw "Skill name must use lowercase letters, digits, and single hyphens only: $Name"
    }
}

function Resolve-TrueSourceSkillPath {
    param(
        [string]$SkillName,
        [string]$SkillPath,
        [string]$TrueSourceRoot = (Get-DefaultTrueSourceRoot)
    )

    if ($SkillPath) {
        return [System.IO.Path]::GetFullPath($SkillPath)
    }
    if (-not $SkillName) {
        throw 'Provide -SkillName or -SkillPath.'
    }
    Assert-SafeSkillName -Name $SkillName
    return [System.IO.Path]::GetFullPath((Join-Path $TrueSourceRoot $SkillName))
}

function Get-RelativeChildPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $pathFull = [System.IO.Path]::GetFullPath($Path)
    $prefix = $rootFull + [System.IO.Path]::DirectorySeparatorChar
    if (-not $pathFull.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside the expected root: $pathFull"
    }
    return $pathFull.Substring($prefix.Length)
}

function Get-FileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        try {
            $hash = $sha.ComputeHash($stream)
        }
        finally {
            $stream.Dispose()
        }
    }
    finally {
        $sha.Dispose()
    }
    return ([System.BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
}

function Get-NormalizedSkillHash {
    param([Parameter(Mandatory = $true)][string]$SkillMdPath)

    $text = [System.IO.File]::ReadAllText($SkillMdPath)
    $normalized = $text.Replace("`r`n", "`n")
    $bytes = (Get-Utf8NoBomEncoding).GetBytes($normalized)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($bytes)
    }
    finally {
        $sha.Dispose()
    }
    return ([System.BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
}

function Get-TreeHash {
    param([Parameter(Mandatory = $true)][string]$Root)

    $lines = New-Object System.Collections.Generic.List[string]
    $files = Get-ChildItem -LiteralPath $Root -Recurse -File -Force | Sort-Object FullName
    foreach ($file in $files) {
        $relative = (Get-RelativeChildPath -Root $Root -Path $file.FullName).Replace('\', '/')
        $lines.Add("$relative`:$((Get-FileSha256 -Path $file.FullName))")
    }
    $payload = ($lines -join "`n") + "`n"
    $bytes = (Get-Utf8NoBomEncoding).GetBytes($payload)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($bytes)
    }
    finally {
        $sha.Dispose()
    }
    return ([System.BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
}

function Get-SkillMetadata {
    param([Parameter(Mandatory = $true)][string]$SkillMdPath)

    $content = [System.IO.File]::ReadAllText($SkillMdPath)
    $frontmatterMatch = [regex]::Match($content, '(?ms)\A---\s*\r?\n(?<body>.*?)\r?\n---(?:\s*\r?\n|\s*\z)')
    if (-not $frontmatterMatch.Success) {
        return [pscustomobject]@{
            HasFrontmatter = $false
            Name = $null
            Description = $null
            License = $null
            Compatibility = $null
            Author = $null
            Version = $null
        }
    }

    $frontmatter = $frontmatterMatch.Groups['body'].Value
    function Read-Scalar([string]$Name) {
        $pattern = '(?m)^' + [regex]::Escape($Name) + ':\s*(?<value>[^\r\n]+)'
        $match = [regex]::Match($frontmatter, $pattern)
        if ($match.Success) { return $match.Groups['value'].Value.Trim().Trim('"').Trim("'") }
        return $null
    }
    function Read-MetadataScalar([string]$Name) {
        $pattern = '(?m)^\s{2,}' + [regex]::Escape($Name) + ':\s*(?<value>[^\r\n]+)'
        $match = [regex]::Match($frontmatter, $pattern)
        if ($match.Success) { return $match.Groups['value'].Value.Trim().Trim('"').Trim("'") }
        return $null
    }

    return [pscustomobject]@{
        HasFrontmatter = $true
        Name = Read-Scalar 'name'
        Description = Read-Scalar 'description'
        License = Read-Scalar 'license'
        Compatibility = Read-Scalar 'compatibility'
        Author = Read-MetadataScalar 'author'
        Version = Read-MetadataScalar 'version'
    }
}

function Get-PublishableTextFiles {
    param([Parameter(Mandatory = $true)][string]$Root)

    $extensions = @('.md', '.txt', '.json', '.ps1', '.psm1', '.sh', '.py', '.js', '.mjs', '.cjs', '.ts', '.tsx', '.yml', '.yaml', '.toml', '.xml', '.html', '.css')
    return Get-ChildItem -LiteralPath $Root -Recurse -File -Force | Where-Object {
        $_.Length -le 5MB -and $extensions -contains $_.Extension.ToLowerInvariant()
    }
}

function Invoke-SkillPreflight {
    param([Parameter(Mandatory = $true)][string]$SkillPath)

    $errors = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $fileList = New-Object System.Collections.Generic.List[string]
    $metadata = $null
    $skillName = Split-Path -Leaf $SkillPath
    $version = $null

    if (-not (Test-Path -LiteralPath $SkillPath -PathType Container)) {
        $errors.Add("Skill directory does not exist: $SkillPath")
    }
    else {
        $skillMd = Join-Path $SkillPath 'SKILL.md'
        if (-not (Test-Path -LiteralPath $skillMd -PathType Leaf)) {
            $errors.Add('Required file SKILL.md is missing.')
        }
        else {
            $metadata = Get-SkillMetadata -SkillMdPath $skillMd
            if (-not $metadata.HasFrontmatter) { $errors.Add('SKILL.md has no valid YAML frontmatter.') }
            if (-not $metadata.Name) { $errors.Add('Frontmatter is missing name.') }
            if (-not $metadata.Description) { $errors.Add('Frontmatter is missing description.') }
            if (-not $metadata.License) { $errors.Add('Frontmatter is missing license.') }
            if (-not $metadata.Compatibility) { $errors.Add('Frontmatter is missing compatibility.') }
            if (-not $metadata.Author) { $errors.Add('Frontmatter metadata is missing author.') }
            if (-not $metadata.Version) { $errors.Add('Frontmatter metadata is missing version.') }

            if ($metadata.Name) {
                $skillName = $metadata.Name
                try { Assert-SafeSkillName -Name $metadata.Name } catch { $errors.Add($_.Exception.Message) }
                if ((Split-Path -Leaf $SkillPath) -ne $metadata.Name) {
                    $errors.Add("Directory name differs from frontmatter name: $(Split-Path -Leaf $SkillPath) != $($metadata.Name)")
                }
            }
            if ($metadata.Version) {
                $version = $metadata.Version
                if ($version -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') {
                    $errors.Add("Version is not valid semantic versioning: $version")
                }
            }
            if ($metadata.Description -and $metadata.Description.Length -lt 40) {
                $warnings.Add('Description is short and may trigger unreliably.')
            }

            $skillText = [System.IO.File]::ReadAllText($skillMd)
            if ([regex]::IsMatch($skillText, '<!--\s*TODO_PUBLICATION')) {
                $errors.Add('SKILL.md still contains TODO_PUBLICATION markers.')
            }
            $links = [regex]::Matches($skillText, '\[[^\]]+\]\((?<path>[^)]+)\)')
            foreach ($link in $links) {
                $linkPath = $link.Groups['path'].Value.Trim().Trim('<', '>').Split('#')[0]
                if (-not $linkPath -or $linkPath -match '^(?:https?://|mailto:|#)') { continue }
                $resolvedLink = Join-Path $SkillPath $linkPath
                if (-not (Test-Path -LiteralPath $resolvedLink)) {
                    $errors.Add("SKILL.md references a missing file: $linkPath")
                }
            }
        }

        if (-not (Test-Path -LiteralPath (Join-Path $SkillPath 'evals\evals.json'))) {
            $warnings.Add('evals/evals.json is missing; add at least three realistic tests before publishing.')
        }

        $blockedDirectories = @('.git', '.svn', 'node_modules', '.venv', 'venv', '__pycache__')
        $directories = Get-ChildItem -LiteralPath $SkillPath -Recurse -Directory -Force
        foreach ($directory in $directories) {
            if ($blockedDirectories -contains $directory.Name) {
                $errors.Add("Blocked publish directory found: $((Get-RelativeChildPath -Root $SkillPath -Path $directory.FullName).Replace('\', '/'))")
            }
        }

        $blockedFilePatterns = @('.env', '.env.*', 'cookies.txt', '*.cookies.txt', '*.pem', '*.key', 'id_rsa', 'id_ed25519')
        $allFiles = Get-ChildItem -LiteralPath $SkillPath -Recurse -File -Force
        foreach ($file in $allFiles) {
            $relative = (Get-RelativeChildPath -Root $SkillPath -Path $file.FullName).Replace('\', '/')
            $fileList.Add($relative)
            foreach ($pattern in $blockedFilePatterns) {
                if ($file.Name -like $pattern) {
                    $errors.Add("Sensitive or blocked file found: $relative")
                    break
                }
            }
        }

        $secretPatterns = @(
            @{ Label = 'GitHub token'; Regex = '(?i)\bgh[pousr]_[A-Za-z0-9]{20,}\b' },
            @{ Label = 'GitHub fine-grained token'; Regex = '(?i)\bgithub_pat_[A-Za-z0-9_]{20,}\b' },
            @{ Label = 'AWS access key'; Regex = '\bAKIA[0-9A-Z]{16}\b' },
            @{ Label = 'private key'; Regex = '-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----' },
            @{ Label = 'Bearer token'; Regex = '(?i)\bBearer\s+[A-Za-z0-9._~+/=-]{20,}' },
            @{ Label = 'credential assignment'; Regex = '(?im)\b(?:api[_-]?key|access[_-]?token|auth[_-]?token|password|cookie)\b\s*[:=]\s*["'']?[A-Za-z0-9_./+=-]{12,}' },
            @{ Label = 'Windows user path'; Regex = '(?i)\bC:\\Users\\(?!<|%|\$)[^\\\r\n]+' }
        )

        foreach ($file in (Get-PublishableTextFiles -Root $SkillPath)) {
            $relative = (Get-RelativeChildPath -Root $SkillPath -Path $file.FullName).Replace('\', '/')
            $content = [System.IO.File]::ReadAllText($file.FullName)
            foreach ($pattern in $secretPatterns) {
                if ([regex]::IsMatch($content, $pattern.Regex)) {
                    $errors.Add("$($pattern.Label) detected in: $relative")
                }
            }
        }
    }

    return [pscustomobject][ordered]@{
        skillName = $skillName
        skillPath = $SkillPath
        version = $version
        ready = ($errors.Count -eq 0)
        errorCount = $errors.Count
        warningCount = $warnings.Count
        errors = @($errors.ToArray())
        warnings = @($warnings.ToArray())
        files = @($fileList.ToArray() | Sort-Object)
        checkedAt = (Get-Date).ToString('s')
    }
}

function Expand-TextTemplate {
    param(
        [Parameter(Mandatory = $true)][string]$TemplatePath,
        [Parameter(Mandatory = $true)][hashtable]$Tokens
    )

    $content = [System.IO.File]::ReadAllText($TemplatePath)
    foreach ($key in $Tokens.Keys) {
        $content = $content.Replace('{{' + $key + '}}', [string]$Tokens[$key])
    }
    $unresolved = [regex]::Matches($content, '\{\{[A-Z0-9_]+\}\}') | ForEach-Object { $_.Value } | Select-Object -Unique
    if ($unresolved) {
        throw "Template has unresolved tokens: $($unresolved -join ', ')"
    }
    return $content
}

function Copy-SafeSkillTree {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    $blockedDirectories = @('.git', '.svn', 'node_modules', '.venv', 'venv', '__pycache__')
    $blockedFiles = @('.DS_Store', 'Thumbs.db')
    $files = Get-ChildItem -LiteralPath $Source -Recurse -File -Force
    foreach ($file in $files) {
        $relative = Get-RelativeChildPath -Root $Source -Path $file.FullName
        $segments = $relative -split '[\\/]'
        if (@($segments | Where-Object { $blockedDirectories -contains $_ }).Count -gt 0) { continue }
        if ($blockedFiles -contains $file.Name) { continue }
        $destinationPath = Join-Path $Destination $relative
        $parent = Split-Path -Parent $destinationPath
        if (-not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        Copy-Item -LiteralPath $file.FullName -Destination $destinationPath
    }
}

function Write-JsonUtf8 {
    param(
        [Parameter(Mandatory = $true)]$InputObject,
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$Depth = 20
    )
    $json = $InputObject | ConvertTo-Json -Depth $Depth
    Write-Utf8NoBom -Path $Path -Content ($json + "`n")
}
