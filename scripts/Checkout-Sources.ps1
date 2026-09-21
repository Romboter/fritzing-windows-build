[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $LockFile,
    [Parameter(Mandatory)] [string] $WorkRoot,
    [string] $AppRef,
    [string] $PartsRef
)

. "$PSScriptRoot/Common.ps1"

$lock = Get-BuildLock -Path $LockFile
if ([string]::IsNullOrWhiteSpace($AppRef)) { $AppRef = $lock.sources.fritzingApp.ref }
if ([string]::IsNullOrWhiteSpace($PartsRef)) { $PartsRef = $lock.sources.fritzingParts.ref }

Assert-SafeGitRef -Ref $AppRef
Assert-SafeGitRef -Ref $PartsRef

$root = [IO.Path]::GetFullPath($WorkRoot)
New-Item -ItemType Directory -Path $root -Force | Out-Null

function Get-ExactSource {
    param(
        [Parameter(Mandatory)] [string] $Repository,
        [Parameter(Mandatory)] [string] $Ref,
        [Parameter(Mandatory)] [string] $Destination
    )

    Assert-ChildPath -Parent $root -Child $Destination
    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }

    Invoke-External git init --quiet $Destination
    Invoke-External git -C $Destination remote add origin $Repository
    Invoke-External git -C $Destination -c protocol.version=2 fetch --quiet --depth=1 --no-tags origin $Ref
    Invoke-External git -C $Destination checkout --quiet --detach FETCH_HEAD

    $sha = (& git -C $Destination rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $sha -notmatch '^[0-9a-f]{40}$') {
        throw "Could not resolve an exact commit for $Repository at $Ref"
    }

    $dirty = & git -C $Destination status --porcelain
    if ($LASTEXITCODE -ne 0 -or $dirty) {
        throw "Source checkout is not clean: $Destination"
    }
    return $sha
}

$appPath = Join-Path $root 'fritzing-app'
$partsPath = Join-Path $root 'fritzing-parts'

$appSha = Get-ExactSource -Repository $lock.sources.fritzingApp.repository -Ref $AppRef -Destination $appPath
$partsSha = Get-ExactSource -Repository $lock.sources.fritzingParts.repository -Ref $PartsRef -Destination $partsPath

Write-CiOutput -Name 'app_sha' -Value $appSha
Write-CiOutput -Name 'parts_sha' -Value $partsSha
Write-CiOutput -Name 'app_path' -Value $appPath
Write-CiOutput -Name 'parts_path' -Value $partsPath

