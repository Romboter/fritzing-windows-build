[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $DistDir,
    [Parameter(Mandatory)] [string] $Version
)

. "$PSScriptRoot/Common.ps1"

function Get-MissingImports {
    param([Parameter(Mandatory)] [string] $Root)

    if (-not (Get-Command dumpbin -ErrorAction SilentlyContinue)) { return 'dumpbin is not available' }
    $present = @{}
    Get-ChildItem -LiteralPath $Root -Filter '*.dll' -File | ForEach-Object { $present[$_.Name.ToLowerInvariant()] = $true }
    $system32 = Join-Path $env:WINDIR 'System32'
    $missing = foreach ($file in Get-ChildItem -LiteralPath $Root -Recurse -File | Where-Object { $_.Extension -in '.exe', '.dll' }) {
        foreach ($line in (& dumpbin /nologo /dependents $file.FullName)) {
            if ($line -notmatch '^\s+(\S+\.dll)\s*$') { continue }
            $import = $Matches[1].ToLowerInvariant()
            if ($import -like 'api-ms-win-*' -or $present[$import] -or (Test-Path -LiteralPath (Join-Path $system32 $import))) { continue }
            "$($file.Name) -> $import"
        }
    }
    return (($missing | Sort-Object -Unique) -join '; ')
}

function Test-FritzingTree {
    param([Parameter(Mandatory)] [string] $Root)

    $exe = Join-Path $Root 'Fritzing.exe'
    $parts = Join-Path $Root 'fritzing-parts'
    $db = Join-Path $parts 'parts.db'
    $buildInfoPath = Join-Path $Root 'BUILD-INFO.json'
    foreach ($path in @($exe, (Join-Path $parts '.git/HEAD'), $db, $buildInfoPath, (Join-Path $Root 'ngspice.dll'), (Join-Path $Root 'ngspice/analog.cm'))) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Release tree is missing $path"
        }
    }

    $buildInfo = Get-Content -LiteralPath $buildInfoPath -Raw | ConvertFrom-Json
    $sha = (& git -C $parts rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $sha -ne $buildInfo.sources.fritzingParts.commit) {
        throw 'Packaged parts Git repository is invalid.'
    }
    $branch = (& git -C $parts symbolic-ref --short HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $branch -ne $buildInfo.sources.fritzingParts.branch) {
        throw "Packaged parts branch is invalid: $branch"
    }
    Invoke-External git -C $parts fsck --no-dangling

    $header = Get-AsciiFileHeader -Path $db -Length 16
    if ($header -ne "SQLite format 3`0") { throw 'Packaged parts.db is not SQLite.' }

    # Fritzing.exe is a GUI-subsystem binary: wait for it and capture its output explicitly.
    $outFile = [IO.Path]::GetTempFileName()
    $errFile = [IO.Path]::GetTempFileName()
    $versionProcess = Start-Process -FilePath $exe -ArgumentList '--version' -Wait -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile
    $output = (Get-Content -LiteralPath $outFile -Raw) + (Get-Content -LiteralPath $errFile -Raw)
    Remove-Item -LiteralPath $outFile, $errFile -Force
    if ($versionProcess.ExitCode -ne 0) {
        throw "Fritzing --version failed with exit code $($versionProcess.ExitCode): $output. Unresolved imports: $(Get-MissingImports -Root $Root)"
    }
    if ($output -notmatch [regex]::Escape($Version)) {
        throw "Fritzing version output did not contain $Version`: $output"
    }
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('fritzing-release-test-' + [guid]::NewGuid().ToString('N'))
$portableRoot = Join-Path $testRoot 'portable'
$installRoot = Join-Path $testRoot 'installed'
New-Item -ItemType Directory -Path $portableRoot, $installRoot -Force | Out-Null

$originalPath = $env:PATH
$originalQtPluginPath = $env:QT_PLUGIN_PATH
$originalQtPlatformPluginPath = $env:QT_QPA_PLATFORM_PLUGIN_PATH
$originalQmlImportPath = $env:QML2_IMPORT_PATH
if ($env:QT_ROOT_DIR) {
    $env:PATH = (($env:PATH -split [IO.Path]::PathSeparator) |
        Where-Object { -not $_.StartsWith($env:QT_ROOT_DIR, [StringComparison]::OrdinalIgnoreCase) }) -join [IO.Path]::PathSeparator
}
$env:QT_PLUGIN_PATH = $null
$env:QT_QPA_PLATFORM_PLUGIN_PATH = $null
$env:QML2_IMPORT_PATH = $null

try {
    $portable = Join-Path $DistDir "Fritzing-$Version-Windows-x64-Portable.zip"
    $installer = Join-Path $DistDir "Fritzing-$Version-Windows-x64-Setup.exe"
    Expand-Archive -LiteralPath $portable -DestinationPath $portableRoot -Force
    Test-FritzingTree -Root $portableRoot

    $installProcess = Start-Process -FilePath $installer -ArgumentList @(
        '/SP-', '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/NOICONS', "/DIR=$installRoot"
    ) -Wait -PassThru
    if ($installProcess.ExitCode -ne 0) {
        throw "Silent installer returned $($installProcess.ExitCode)"
    }
    Test-FritzingTree -Root $installRoot

    $uninstaller = Get-ChildItem -LiteralPath $installRoot -Filter 'unins*.exe' -File | Select-Object -First 1
    if (-not $uninstaller) { throw 'Installer did not create an uninstaller.' }
    $uninstallProcess = Start-Process -FilePath $uninstaller.FullName -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') -Wait -PassThru
    if ($uninstallProcess.ExitCode -ne 0) {
        throw "Silent uninstaller returned $($uninstallProcess.ExitCode)"
    }
} finally {
    $env:PATH = $originalPath
    $env:QT_PLUGIN_PATH = $originalQtPluginPath
    $env:QT_QPA_PLATFORM_PLUGIN_PATH = $originalQtPlatformPluginPath
    $env:QML2_IMPORT_PATH = $originalQmlImportPath
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}

Write-Host 'Portable archive and clean installer installation passed smoke tests.'
