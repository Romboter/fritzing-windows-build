[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $StageDir,
    [Parameter(Mandatory)] [string] $AppPath,
    [Parameter(Mandatory)] [string] $DownloadsDir,
    [Parameter(Mandatory)] [string] $BuilderRoot,
    [Parameter(Mandatory)] [string] $DistDir,
    [Parameter(Mandatory)] [string] $Version
)

. "$PSScriptRoot/Common.ps1"

$dist = [IO.Path]::GetFullPath($DistDir)
New-Item -ItemType Directory -Path $dist -Force | Out-Null
Get-ChildItem -LiteralPath $dist -Force | Remove-Item -Recurse -Force

$portableName = "Fritzing-$Version-Windows-x64-Portable.zip"
$portablePath = Join-Path $dist $portableName
Push-Location $StageDir
try {
    Invoke-External 7z a -tzip -mx=7 $portablePath .
} finally {
    Pop-Location
}

$listing = & 7z l -ba $portablePath
if ($LASTEXITCODE -ne 0) { throw 'Could not inspect portable archive.' }
foreach ($required in @('fritzing-parts\.git\HEAD', 'fritzing-parts\parts.db', 'Fritzing.exe', 'BUILD-INFO.json')) {
    if (-not ($listing -match [regex]::Escape($required))) {
        throw "Portable archive is missing $required"
    }
}

$iscc = Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6/ISCC.exe'
if (-not (Test-Path -LiteralPath $iscc -PathType Leaf)) {
    throw "Inno Setup compiler not found: $iscc"
}
$installerScript = Join-Path $BuilderRoot 'installer/Fritzing.iss'
Invoke-External $iscc "/DMyAppVersion=$Version" "/DStageDir=$StageDir" "/DOutputDir=$dist" $installerScript
$installerPath = Join-Path $dist "Fritzing-$Version-Windows-x64-Setup.exe"
if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
    throw "Installer was not produced: $installerPath"
}

# Bundle the exact app source plus every verified dependency archive used by the build.
$sourceWork = Join-Path (Split-Path -Parent $dist) ('source-bundle-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $sourceWork 'dependencies') -Force | Out-Null
try {
    Invoke-External git -C $AppPath archive --format=zip --prefix=fritzing-app/ -o (Join-Path $sourceWork 'fritzing-app-source.zip') HEAD
    Copy-Item -Path (Join-Path $DownloadsDir '*') -Destination (Join-Path $sourceWork 'dependencies') -Force
    Copy-Item -LiteralPath (Join-Path $BuilderRoot 'config/build-lock.json'), (Join-Path $BuilderRoot 'THIRD_PARTY.md'), (Join-Path $BuilderRoot 'LICENSE') -Destination $sourceWork -Force
    $sourcePath = Join-Path $dist "Fritzing-$Version-Corresponding-Source.zip"
    Push-Location $sourceWork
    try { Invoke-External 7z a -tzip -mx=7 $sourcePath . } finally { Pop-Location }
} finally {
    if (Test-Path -LiteralPath $sourceWork) { Remove-Item -LiteralPath $sourceWork -Recurse -Force }
}

Copy-Item -LiteralPath (Join-Path $StageDir 'BUILD-INFO.json'), (Join-Path $StageDir 'SBOM.cdx.json') -Destination $dist -Force

$hashTargets = Get-ChildItem -LiteralPath $dist -File | Where-Object Name -ne 'SHA256SUMS.txt' | Sort-Object Name
$hashLines = foreach ($file in $hashTargets) {
    "$(Get-FileSha256 -Path $file.FullName)  $($file.Name)"
}
$hashLines | Out-File -LiteralPath (Join-Path $dist 'SHA256SUMS.txt') -Encoding ascii

Write-CiOutput -Name 'portable_path' -Value $portablePath
Write-CiOutput -Name 'installer_path' -Value $installerPath
Write-CiOutput -Name 'dist_dir' -Value $dist
