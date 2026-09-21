Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Invoke-External {
    if ($args.Count -lt 1) { throw 'Invoke-External requires a command.' }
    [string] $FilePath = $args[0]
    [string[]] $ArgumentList = @()
    if ($args.Count -gt 1) {
        $ArgumentList = @($args | Select-Object -Skip 1)
    }
    Write-Host "> $FilePath $($ArgumentList -join ' ')"
    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code $LASTEXITCODE`: $FilePath"
    }
}

function Get-BuildLock {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Build lock not found: $Path"
    }

    $lock = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($lock.schemaVersion -ne 1) {
        throw "Unsupported build-lock schema: $($lock.schemaVersion)"
    }
    return $lock
}

function Assert-SafeGitRef {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Ref)

    if ($Ref -notmatch '^[0-9A-Za-z][0-9A-Za-z._/-]{0,199}$' -or
        $Ref.Contains('..') -or $Ref.Contains('@{') -or $Ref.EndsWith('/') -or
        $Ref.EndsWith('.') -or $Ref.Contains('//')) {
        throw "Unsafe or unsupported Git ref: $Ref"
    }
}

function Assert-ChildPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Parent,
        [Parameter(Mandatory)] [string] $Child
    )

    $parentFull = [IO.Path]::GetFullPath($Parent).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $childFull = [IO.Path]::GetFullPath($Child)
    if (-not $childFull.StartsWith($parentFull, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to operate outside '$parentFull': $childFull"
    }
}

function Write-CiOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Value
    )

    if ($env:GITHUB_OUTPUT) {
        "$Name=$Value" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append
    }
    Write-Host "$Name=$Value"
}

function Get-FileSha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-AsciiFileHeader {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [ValidateRange(1, 4096)] [int] $Length
    )

    $buffer = [byte[]]::new($Length)
    $stream = [IO.File]::OpenRead($Path)
    try {
        $read = $stream.Read($buffer, 0, $Length)
        if ($read -ne $Length) { throw "File is shorter than $Length bytes: $Path" }
    } finally {
        $stream.Dispose()
    }
    return [Text.Encoding]::ASCII.GetString($buffer)
}
