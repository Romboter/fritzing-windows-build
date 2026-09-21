[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $AppPath,
    [Parameter(Mandatory)] [string] $PartsPath,
    [Parameter(Mandatory)] [string] $ReleaseDir,
    [Parameter(Mandatory)] [string] $DependencyRoot,
    [Parameter(Mandatory)] [string] $StageDir,
    [Parameter(Mandatory)] [string] $LockFile,
    [string] $PartsBranch,
    [Parameter(Mandatory)] [ValidatePattern('^[0-9a-f]{40}$')] [string] $AppSha,
    [Parameter(Mandatory)] [ValidatePattern('^[0-9a-f]{40}$')] [string] $PartsSha,
    [Parameter(Mandatory)] [ValidatePattern('^[0-9a-f]{40}$')] [string] $BuilderSha
)

. "$PSScriptRoot/Common.ps1"

$lock = Get-BuildLock -Path $LockFile
$stage = [IO.Path]::GetFullPath($StageDir)
$release = [IO.Path]::GetFullPath($ReleaseDir)
$stageParent = Split-Path -Parent $stage
Assert-ChildPath -Parent $stageParent -Child $stage

if (Test-Path -LiteralPath $stage) {
    Remove-Item -LiteralPath $stage -Recurse -Force
}
New-Item -ItemType Directory -Path $stage -Force | Out-Null

$builtExe = Join-Path $release 'Fritzing.exe'
if (-not (Test-Path -LiteralPath $builtExe -PathType Leaf)) {
    throw "Built executable not found: $builtExe"
}
Copy-Item -LiteralPath $builtExe -Destination $stage -Force

Push-Location $stage
try {
    Invoke-External windeployqt --release --compiler-runtime --no-system-d3d-compiler Fritzing.exe
} finally {
    Pop-Location
}

foreach ($folder in @('help', 'sketches', 'translations')) {
    Copy-Item -LiteralPath (Join-Path $AppPath $folder) -Destination $stage -Recurse -Force
}
Get-ChildItem -LiteralPath (Join-Path $stage 'translations') -Filter '*.ts' -File -ErrorAction SilentlyContinue |
    Remove-Item -Force

foreach ($file in @('README.md', 'INSTALL.txt', 'LICENSE.CC-BY-SA', 'LICENSE.GPL2', 'LICENSE.GPL3', 'LICENSE.LGPLv3', 'LICENSE.Modified_BSD', 'LICENSE_1_0.txt.BOOST')) {
    $source = Join-Path $AppPath $file
    if (Test-Path -LiteralPath $source -PathType Leaf) {
        Copy-Item -LiteralPath $source -Destination $stage -Force
    }
}

$quazipRoot = Join-Path $DependencyRoot "quazip-$($lock.toolchain.qtVersion)-1.4intuisphere"
$quazipDll = Get-ChildItem -LiteralPath $quazipRoot -Filter 'quazip1-qt6.dll' -File -Recurse | Select-Object -First 1
if (-not $quazipDll) { throw 'QuaZip runtime DLL was not found.' }
Copy-Item -LiteralPath $quazipDll.FullName -Destination $stage -Force
# windeployqt only scans Fritzing.exe, so deploy the Qt modules QuaZip needs (Qt6Core5Compat) separately.
Push-Location $stage
try {
    Invoke-External windeployqt --release --no-compiler-runtime --no-system-d3d-compiler $quazipDll.Name
} finally {
    Pop-Location
}

$ngRoot = Join-Path $DependencyRoot 'ngspice-42'
Copy-Item -LiteralPath (Join-Path $ngRoot 'dll-vs/ngspice.dll') -Destination $stage -Force
if (Test-Path -LiteralPath (Join-Path $ngRoot 'dll-vs/libomp140.x86_64.dll')) {
    Copy-Item -LiteralPath (Join-Path $ngRoot 'dll-vs/libomp140.x86_64.dll') -Destination $stage -Force
}
Copy-Item -LiteralPath (Join-Path $ngRoot 'lib/ngspice') -Destination (Join-Path $stage 'ngspice') -Recurse -Force
New-Item -ItemType Directory -Path (Join-Path $stage 'share') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $ngRoot 'share/ngspice') -Destination (Join-Path $stage 'share') -Recurse -Force

$partsDestination = Join-Path $stage 'fritzing-parts'
Invoke-External git clone --quiet --no-hardlinks $PartsPath $partsDestination
Invoke-External git -C $partsDestination remote set-url origin $lock.sources.fritzingParts.repository
if ([string]::IsNullOrWhiteSpace($PartsBranch)) {
    $PartsBranch = [string] $lock.sources.fritzingParts.packagedBranch
}
Assert-SafeGitRef -Ref $PartsBranch
$remoteBranch = & git ls-remote $lock.sources.fritzingParts.repository "refs/heads/$PartsBranch"
if ($LASTEXITCODE -ne 0 -or -not $remoteBranch) {
    throw "The packaged parts branch does not exist upstream: $PartsBranch"
}
Invoke-External git -C $partsDestination checkout --quiet -B $PartsBranch $PartsSha
Invoke-External git -C $partsDestination config "branch.$PartsBranch.remote" origin
Invoke-External git -C $partsDestination config "branch.$PartsBranch.merge" "refs/heads/$PartsBranch"
$packagedPartsSha = (& git -C $partsDestination rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $packagedPartsSha -ne $PartsSha) {
    throw "Packaged parts commit mismatch. Expected $PartsSha, got $packagedPartsSha"
}
$packagedPartsBranch = (& git -C $partsDestination symbolic-ref --short HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $packagedPartsBranch -ne $PartsBranch) {
    throw "Packaged parts branch mismatch. Expected $PartsBranch, got $packagedPartsBranch"
}

$dbPath = Join-Path $partsDestination 'parts.db'
$env:QT_LOGGING_RULES = '*.debug=false'
$stagedExe = Join-Path $stage 'Fritzing.exe'
Push-Location $stage
try {
    # Fritzing.exe is a GUI-subsystem binary; '&' would not wait for it to finish.
    $dbProcess = Start-Process -FilePath $stagedExe -ArgumentList @('-f', $stage, '-pp', $partsDestination, '-db', $dbPath) -WorkingDirectory $stage -Wait -PassThru
    if ($dbProcess.ExitCode -ne 0) {
        throw "Fritzing parts database generation failed with exit code $($dbProcess.ExitCode)"
    }
} finally {
    Pop-Location
}

if (-not (Test-Path -LiteralPath $dbPath -PathType Leaf)) {
    throw 'parts.db was not generated.'
}
$dbInfo = Get-Item -LiteralPath $dbPath
if ($dbInfo.Length -lt 1024) {
    throw "parts.db is unexpectedly small: $($dbInfo.Length) bytes"
}
$header = Get-AsciiFileHeader -Path $dbPath -Length 16
if ($header -ne "SQLite format 3`0") {
    throw 'parts.db does not have a valid SQLite header.'
}

$versionFile = Join-Path $AppPath 'src/version/version.cpp'
$versionText = Get-Content -LiteralPath $versionFile -Raw
$major = [regex]::Match($versionText, 'm_majorVersion\("([^"]+)"\)').Groups[1].Value
$minor = [regex]::Match($versionText, 'm_minorVersion\("([^"]+)"\)').Groups[1].Value
$patch = [regex]::Match($versionText, 'm_minorSubVersion\("([^"]+)"\)').Groups[1].Value
$modifier = [regex]::Match($versionText, 'm_modifier\("([^"]*)"\)').Groups[1].Value
$version = "$major.$minor.$patch$modifier"
if ($version -notmatch '^\d+\.\d+\.\d+[0-9A-Za-z.-]*$') {
    throw "Could not determine a safe Fritzing version: $version"
}

$dependencyList = foreach ($property in $lock.dependencies.PSObject.Properties) {
    [ordered]@{
        name = $property.Name
        version = $property.Value.version
        source = $property.Value.url
        sha256 = $property.Value.sha256
    }
}

$buildInfo = [ordered]@{
    schemaVersion = 1
    generatedUtc = [DateTime]::UtcNow.ToString('o')
    fritzingVersion = $version
    sources = [ordered]@{
        fritzingApp = [ordered]@{ repository = $lock.sources.fritzingApp.repository; commit = $AppSha }
        fritzingParts = [ordered]@{ repository = $lock.sources.fritzingParts.repository; commit = $PartsSha; branch = $PartsBranch }
        builder = [ordered]@{ repository = $env:GITHUB_SERVER_URL + '/' + $env:GITHUB_REPOSITORY; commit = $BuilderSha }
    }
    toolchain = [ordered]@{
        runner = $lock.toolchain.runner
        runnerImage = $env:ImageVersion
        qtVersion = $lock.toolchain.qtVersion
        qtArch = $lock.toolchain.qtArch
        aqtVersion = $lock.toolchain.aqtVersion
        visualStudio = $env:VisualStudioVersion
    }
    dependencies = @($dependencyList)
    partsDatabase = [ordered]@{ bytes = $dbInfo.Length; sha256 = Get-FileSha256 -Path $dbPath }
}
$buildInfo | ConvertTo-Json -Depth 8 | Out-File -LiteralPath (Join-Path $stage 'BUILD-INFO.json') -Encoding utf8

$components = @(
    [ordered]@{ type = 'application'; name = 'Fritzing'; version = $version; purl = "pkg:github/fritzing/fritzing-app@$AppSha" },
    [ordered]@{ type = 'file'; name = 'fritzing-parts'; version = $PartsSha; purl = "pkg:github/fritzing/fritzing-parts@$PartsSha" }
)
foreach ($dep in $dependencyList) {
    $components += [ordered]@{ type = 'library'; name = $dep.name; version = $dep.version; externalReferences = @([ordered]@{ type = 'distribution'; url = $dep.source }); hashes = @([ordered]@{ alg = 'SHA-256'; content = $dep.sha256 }) }
}
$sbom = [ordered]@{
    bomFormat = 'CycloneDX'
    specVersion = '1.5'
    serialNumber = 'urn:uuid:' + [guid]::NewGuid().ToString()
    version = 1
    metadata = [ordered]@{ timestamp = [DateTime]::UtcNow.ToString('o'); component = $components[0] }
    components = $components
}
$sbom | ConvertTo-Json -Depth 10 | Out-File -LiteralPath (Join-Path $stage 'SBOM.cdx.json') -Encoding utf8

Write-CiOutput -Name 'fritzing_version' -Value $version
Write-CiOutput -Name 'stage_dir' -Value $stage
