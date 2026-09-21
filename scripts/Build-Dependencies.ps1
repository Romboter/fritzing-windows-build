[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $LockFile,
    [Parameter(Mandatory)] [string] $Workspace,
    [Parameter(Mandatory)] [string] $QtRoot
)

. "$PSScriptRoot/Common.ps1"

$lock = Get-BuildLock -Path $LockFile
$workspaceFull = [IO.Path]::GetFullPath($Workspace)
$deps = Join-Path $workspaceFull 'deps'
$downloads = Join-Path $workspaceFull 'downloads'
$sources = Join-Path $deps '_sources'
$marker = Join-Path $deps '.lock-sha256'
$lockHash = Get-FileSha256 -Path $LockFile

function Assert-DependencyLayout {
    $required = @(
        (Join-Path $deps 'zlib-1.3.1/build/zlibstatic.lib'),
        (Join-Path $deps 'libgit2-1.7.1/include/git2.h'),
        (Join-Path $deps 'libgit2-1.7.1/lib/git2.lib'),
        (Join-Path $deps "quazip-$($lock.toolchain.qtVersion)-1.4intuisphere/include/QuaZip-Qt6-1.4/quazip/quazip.h"),
        (Join-Path $deps "quazip-$($lock.toolchain.qtVersion)-1.4intuisphere/lib/quazip1-qt6.lib"),
        (Join-Path $deps 'Clipper1-6.4.2/include/polyclipping/clipper.hpp'),
        (Join-Path $deps 'Clipper1-6.4.2/lib/polyclipping.lib'),
        (Join-Path $deps 'boost_1_85_0/boost/version.hpp'),
        (Join-Path $deps 'svgpp-1.3.1/include/svgpp/svgpp.hpp'),
        (Join-Path $deps 'ngspice-42/include/ngspice/sharedspice.h'),
        (Join-Path $deps 'ngspice-42/dll-vs/ngspice.dll'),
        (Join-Path $deps 'ngspice-42/lib/ngspice/analog.cm')
    )
    foreach ($path in $required) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Dependency layout is incomplete: $path"
        }
    }
    foreach ($property in $lock.dependencies.PSObject.Properties) {
        $archive = Join-Path $downloads $property.Value.fileName
        if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) {
            throw "Verified dependency archive is missing: $archive"
        }
        $actual = Get-FileSha256 -Path $archive
        if ($actual -ne $property.Value.sha256.ToLowerInvariant()) {
            throw "Cached archive hash mismatch for $($property.Value.fileName)"
        }
    }
}

if ((Test-Path -LiteralPath $marker -PathType Leaf) -and
    ((Get-Content -LiteralPath $marker -Raw).Trim() -eq $lockHash)) {
    try {
        Assert-DependencyLayout
        Write-Host 'Using verified dependency cache.'
        exit 0
    } catch {
        Write-Warning "Cached dependency tree failed validation: $_"
    }
}

Assert-ChildPath -Parent $workspaceFull -Child $deps
if (Test-Path -LiteralPath $deps) {
    Remove-Item -LiteralPath $deps -Recurse -Force
}
New-Item -ItemType Directory -Path $deps, $downloads, $sources -Force | Out-Null

function Get-VerifiedArchive {
    param([Parameter(Mandatory)] $Entry)

    $destination = Join-Path $downloads $Entry.fileName
    $needsDownload = $true
    if (Test-Path -LiteralPath $destination -PathType Leaf) {
        $needsDownload = (Get-FileSha256 -Path $destination) -ne $Entry.sha256.ToLowerInvariant()
    }
    if ($needsDownload) {
        Write-Host "Downloading $($Entry.url)"
        Invoke-WebRequest -Uri $Entry.url -OutFile $destination -MaximumRetryCount 3 -RetryIntervalSec 3
    }

    $actual = Get-FileSha256 -Path $destination
    if ($actual -ne $Entry.sha256.ToLowerInvariant()) {
        throw "SHA-256 mismatch for $($Entry.fileName). Expected $($Entry.sha256), got $actual"
    }
    return $destination
}

function Expand-TarGz {
    param([string] $Archive, [string] $Destination)
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Invoke-External tar -xzf $Archive -C $Destination
}

foreach ($property in $lock.dependencies.PSObject.Properties) {
    [void](Get-VerifiedArchive -Entry $property.Value)
}

# zlib
$zlibArchive = Join-Path $downloads $lock.dependencies.zlib.fileName
Expand-TarGz -Archive $zlibArchive -Destination $deps
$zlibRoot = Join-Path $deps 'zlib-1.3.1'
$zlibBuild = Join-Path $zlibRoot 'build'
New-Item -ItemType Directory -Path $zlibBuild -Force | Out-Null
Invoke-External cmake -S $zlibRoot -B $zlibBuild -G $lock.toolchain.cmakeGenerator '-DCMAKE_BUILD_TYPE=Release'
Invoke-External cmake --build $zlibBuild --config Release
Copy-Item -LiteralPath (Join-Path $zlibBuild 'zconf.h') -Destination $zlibRoot -Force

# libgit2, statically linked with the dynamic MSVC runtime and WinHTTP HTTPS.
$libgitArchive = Join-Path $downloads $lock.dependencies.libgit2.fileName
Expand-TarGz -Archive $libgitArchive -Destination $deps
$libgitRoot = Join-Path $deps 'libgit2-1.7.1'
$libgitBuild = Join-Path $libgitRoot 'build'
Invoke-External cmake -S $libgitRoot -B $libgitBuild -G $lock.toolchain.cmakeGenerator `
    '-DCMAKE_BUILD_TYPE=Release' '-DBUILD_SHARED_LIBS=OFF' '-DBUILD_TESTS=OFF' `
    '-DBUILD_CLI=OFF' '-DBUILD_EXAMPLES=OFF' '-DSTATIC_CRT=OFF' '-DUSE_HTTPS=WinHTTP' `
    '-DUSE_SSH=OFF' '-DUSE_BUNDLED_ZLIB=OFF' "-DZLIB_LIBRARY=$zlibBuild/zlibstatic.lib" `
    "-DZLIB_INCLUDE_DIR=$zlibRoot"
Invoke-External cmake --build $libgitBuild --config Release
$git2Lib = Get-ChildItem -LiteralPath $libgitBuild -Filter git2.lib -File -Recurse | Select-Object -First 1
if (-not $git2Lib) { throw 'libgit2 build did not produce git2.lib' }
New-Item -ItemType Directory -Path (Join-Path $libgitRoot 'lib') -Force | Out-Null
Copy-Item -LiteralPath $git2Lib.FullName -Destination (Join-Path $libgitRoot 'lib/git2.lib') -Force

# QuaZip dynamic runtime in the sibling layout required by Fritzing qmake.
$quazipArchive = Join-Path $downloads $lock.dependencies.quazip.fileName
Expand-TarGz -Archive $quazipArchive -Destination $sources
$quazipSource = Join-Path $sources 'quazip-1.4'
$quazipBuild = Join-Path $quazipSource 'build'
$quazipPrefix = Join-Path $deps "quazip-$($lock.toolchain.qtVersion)-1.4intuisphere"
Invoke-External cmake -S $quazipSource -B $quazipBuild -G $lock.toolchain.cmakeGenerator `
    '-DCMAKE_BUILD_TYPE=Release' '-DBUILD_SHARED_LIBS=ON' '-DQUAZIP_QT_MAJOR_VERSION=6' `
    '-DQUAZIP_ENABLE_TESTS=OFF' '-DQUAZIP_BZIP2=OFF' '-DQUAZIP_FETCH_LIBS=OFF' `
    "-DCMAKE_PREFIX_PATH=$QtRoot" "-DCMAKE_INSTALL_PREFIX=$quazipPrefix" `
    "-DZLIB_LIBRARY=$zlibBuild/zlibstatic.lib" "-DZLIB_INCLUDE_DIR=$zlibRoot"
Invoke-External cmake --build $quazipBuild --config Release
Invoke-External cmake --install $quazipBuild --config Release

# Clipper 6.4.2 static library.
$clipperExtract = Join-Path $sources 'clipper-6.4.2'
Expand-Archive -LiteralPath (Join-Path $downloads $lock.dependencies.clipper.fileName) -DestinationPath $clipperExtract -Force
$clipperCpp = Get-ChildItem -LiteralPath $clipperExtract -Filter clipper.cpp -File -Recurse | Select-Object -First 1
$clipperHpp = Get-ChildItem -LiteralPath $clipperExtract -Filter clipper.hpp -File -Recurse | Select-Object -First 1
if (-not $clipperCpp -or -not $clipperHpp) { throw 'Clipper archive layout is not recognized.' }
$clipperRoot = Join-Path $deps 'Clipper1-6.4.2'
$clipperInclude = Join-Path $clipperRoot 'include/polyclipping'
$clipperLib = Join-Path $clipperRoot 'lib'
New-Item -ItemType Directory -Path $clipperInclude, $clipperLib -Force | Out-Null
Copy-Item -LiteralPath $clipperCpp.FullName, $clipperHpp.FullName -Destination $clipperInclude -Force
Push-Location $clipperRoot
try {
    Invoke-External cl /nologo /c /O2 /EHsc /MD /Iinclude\polyclipping include\polyclipping\clipper.cpp /Foclipper.obj
    Invoke-External lib /nologo /OUT:lib\polyclipping.lib clipper.obj
} finally {
    Pop-Location
}

# Header-only dependencies.
Expand-TarGz -Archive (Join-Path $downloads $lock.dependencies.boost.fileName) -Destination $deps
Expand-TarGz -Archive (Join-Path $downloads $lock.dependencies.svgpp.fileName) -Destination $deps

# ngspice prebuilt Windows runtime.
$ngExtract = Join-Path $sources 'ngspice-42'
New-Item -ItemType Directory -Path $ngExtract -Force | Out-Null
Invoke-External 7z x (Join-Path $downloads $lock.dependencies.ngspice.fileName) "-o$ngExtract" -y
$ngRoot = Get-ChildItem -LiteralPath $ngExtract -Directory -Recurse |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'include/ngspice/sharedspice.h') } |
    Select-Object -First 1
if (-not $ngRoot) { throw 'ngspice archive layout is not recognized.' }
Copy-Item -LiteralPath $ngRoot.FullName -Destination (Join-Path $deps 'ngspice-42') -Recurse -Force

Assert-DependencyLayout
$lockHash | Out-File -LiteralPath $marker -Encoding ascii -NoNewline
Write-Host 'Dependencies built and verified.'
