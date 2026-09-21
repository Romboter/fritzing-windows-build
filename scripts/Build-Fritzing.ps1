[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $AppPath,
    [Parameter(Mandatory)] [string] $DependencyRoot,
    [Parameter(Mandatory)] [string] $QtVersion
)

. "$PSScriptRoot/Common.ps1"

$appFull = [IO.Path]::GetFullPath($AppPath)
$depsFull = [IO.Path]::GetFullPath($DependencyRoot)
$siblingRoot = Split-Path -Parent $appFull

$dependencyNames = @(
    'libgit2-1.7.1',
    "quazip-$QtVersion-1.4intuisphere",
    'Clipper1-6.4.2',
    'boost_1_85_0',
    'svgpp-1.3.1',
    'ngspice-42'
)

foreach ($name in $dependencyNames) {
    $target = Join-Path $depsFull $name
    $link = Join-Path $siblingRoot $name
    if (-not (Test-Path -LiteralPath $target -PathType Container)) {
        throw "Required dependency is missing: $target"
    }
    if (Test-Path -LiteralPath $link) {
        $item = Get-Item -LiteralPath $link -Force
        if (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Refusing to replace non-link dependency path: $link"
        }
        Remove-Item -LiteralPath $link -Force
    }
    New-Item -ItemType Junction -Path $link -Target $target | Out-Null
}

$zlibBuild = Join-Path $depsFull 'zlib-1.3.1/build'
$env:RELEASE_SCRIPT = 'github-actions'

Push-Location $appFull
try {
    Remove-Item -LiteralPath '.qmake.cache', '.qmake.stash' -Force -ErrorAction SilentlyContinue
    Invoke-External lrelease phoenix.pro
    Invoke-External qmake phoenix.pro 'CONFIG+=release' 'QMAKE_TARGET.arch=x86_64' `
        "LIBS+=-L$zlibBuild -lzlibstatic -ladvapi32 -lwinhttp -lrpcrt4 -lcrypt32 -lole32 -lsecur32 -lws2_32"
    Invoke-External nmake release
} finally {
    Pop-Location
}

$exe = Join-Path $siblingRoot 'release64/Fritzing.exe'
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
    throw "Fritzing build did not produce $exe"
}

Write-CiOutput -Name 'release_dir' -Value (Split-Path -Parent $exe)

