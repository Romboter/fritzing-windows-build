[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$lockPath = Join-Path $root 'config/build-lock.json'
$lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
}

Assert-True ($lock.schemaVersion -eq 1) 'Unexpected build-lock schema.'
foreach ($sourceName in @('fritzingApp', 'fritzingParts')) {
    $source = $lock.sources.$sourceName
    Assert-True ($source.repository -match '^https://github\.com/') "$sourceName must use an HTTPS GitHub repository."
    Assert-True ($source.ref -match '^[0-9a-f]{40}$') "$sourceName must be locked to a full commit SHA."
}
Assert-True ($lock.sources.fritzingParts.packagedBranch -match '^[0-9A-Za-z][0-9A-Za-z._/-]{0,199}$') 'Parts packagedBranch is invalid.'

$allowedHosts = @('github.com', 'archives.boost.io', 'sourceforge.net')
$fileNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($property in $lock.dependencies.PSObject.Properties) {
    $dep = $property.Value
    $uri = [Uri] $dep.url
    Assert-True ($uri.Scheme -eq 'https') "$($property.Name) must use HTTPS."
    Assert-True ($allowedHosts -contains $uri.Host) "$($property.Name) uses an unapproved host: $($uri.Host)"
    Assert-True ($dep.sha256 -match '^[0-9a-f]{64}$') "$($property.Name) has an invalid SHA-256 value."
    Assert-True ($fileNames.Add([string] $dep.fileName)) "Duplicate archive filename: $($dep.fileName)"
}

$parseFailures = @()
Get-ChildItem -LiteralPath (Join-Path $root 'scripts') -Filter '*.ps1' -File -Recurse |
    ForEach-Object {
        $tokens = $null
        $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref] $tokens, [ref] $errors)
        foreach ($error in $errors) { $script:parseFailures += "$($_.Name): $($error.Message)" }
    }
Assert-True ($parseFailures.Count -eq 0) ("PowerShell parse errors:`n" + ($parseFailures -join "`n"))

$workflowFiles = Get-ChildItem -LiteralPath (Join-Path $root '.github/workflows') -Include '*.yml', '*.yaml' -File -Recurse
foreach ($workflow in $workflowFiles) {
    $text = Get-Content -LiteralPath $workflow.FullName -Raw
    Assert-True ($text -notmatch '(?m)^\s*pull_request_target\s*:') "$($workflow.Name) must not use pull_request_target."
    Assert-True ($text -match '(?m)^permissions\s*:') "$($workflow.Name) must declare permissions."
    foreach ($match in [regex]::Matches($text, '(?m)^\s*uses:\s*([^\s#]+)')) {
        $uses = $match.Groups[1].Value
        Assert-True ($uses -match '@[0-9a-f]{40}$') "Action is not pinned to a full commit SHA in $($workflow.Name): $uses"
    }
}

$allScripts = (Get-ChildItem -LiteralPath (Join-Path $root 'scripts') -Filter '*.ps1' -File -Recurse | Get-Content -Raw) -join "`n"
foreach ($blocked in @('Invoke-Expression', 'EncodedCommand', 'DownloadString', 'FromBase64String')) {
    Assert-True ($allScripts -notmatch [regex]::Escape($blocked)) "Blocked dynamic-execution primitive found: $blocked"
}
Assert-True ($allScripts -match 'parts\.db') 'Build scripts must validate parts.db.'
Assert-True ($allScripts -match 'SQLite format 3') 'Build scripts must verify the SQLite header.'

$installer = Get-Content -LiteralPath (Join-Path $root 'installer/Fritzing.iss') -Raw
Assert-True ($installer -match 'DefaultDirName=\{localappdata\}') 'Installer must default to a per-user directory.'
Assert-True ($installer -match 'PrivilegesRequired=lowest') 'Installer must not require elevation.'
Assert-True ($installer -notmatch '(?m)^\[Code\]') 'Installer contains unexpected executable Pascal code.'

Write-Host 'Repository validation passed.'
