param(
    [ValidateSet('Prepare', 'Package')]
    [string]$Action = 'Prepare'
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$dist = Join-Path $root 'dist'
$stage = Join-Path $dist 'HaxBallLocal'
$gameLove = Join-Path $dist 'game.love'
$loveDir = Join-Path $root 'tools\love-11.5-win64'
$loveExe = Join-Path $loveDir 'love.exe'
$loveZipUrl = 'https://github.com/love2d/love/releases/download/11.5/love-11.5-win64.zip'

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

if ($Action -eq 'Prepare') {
    if (-not (Test-Path -LiteralPath $loveExe)) {
        Write-Host 'Baixando LÖVE 11.5 oficial para Windows 64 bits...'
        $tools = Split-Path -Parent $loveDir
        New-Item -ItemType Directory -Force -Path $tools | Out-Null
        $downloadDir = Join-Path ([System.IO.Path]::GetTempPath()) ('haxball-love-' + [guid]::NewGuid().ToString('N'))
        $archive = Join-Path $downloadDir 'love-win64.zip'
        New-Item -ItemType Directory -Path $downloadDir | Out-Null
        try {
            Invoke-WebRequest -Uri $loveZipUrl -OutFile $archive
            Expand-Archive -LiteralPath $archive -DestinationPath $tools -Force
        }
        finally {
            Remove-Item -LiteralPath $downloadDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not (Test-Path -LiteralPath $loveExe)) {
        throw "Runtime LÖVE não encontrado em $loveDir."
    }
    foreach ($required in @('love.dll', 'license.txt')) {
        if (-not (Test-Path -LiteralPath (Join-Path $loveDir $required))) {
            throw "Arquivo requerido do runtime LÖVE ausente: $required"
        }
    }

    if (Test-Path -LiteralPath $stage) {
        Remove-Item -LiteralPath $stage -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    if (Test-Path -LiteralPath $gameLove) {
        Remove-Item -LiteralPath $gameLove -Force
    }

    $archiveStream = [System.IO.Compression.ZipFile]::Open($gameLove, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($file in @('conf.lua', 'main.lua')) {
            $path = Join-Path $root $file
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archiveStream, $path, $file) | Out-Null
        }
        Get-ChildItem -LiteralPath (Join-Path $root 'src') -File -Recurse | ForEach-Object {
            $relative = $_.FullName.Substring($root.Length + 1).Replace('\', '/')
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archiveStream, $_.FullName, $relative) | Out-Null
        }
    }
    finally {
        $archiveStream.Dispose()
    }

    Get-ChildItem -LiteralPath $loveDir -File | Where-Object {
        $_.Name -notin @('love.exe', 'lovec.exe', 'readme.txt', 'changes.txt')
    } | Copy-Item -Destination $stage -Force
    Write-Host "game.love criado: $gameLove"
    exit 0
}

if (-not (Test-Path -LiteralPath (Join-Path $stage 'HaxBallLocal.exe'))) {
    throw 'HaxBallLocal.exe não existe. Execute build.bat para preparar o pacote.'
}
$outputZip = Join-Path $dist 'HaxBallLocal.zip'
if (Test-Path -LiteralPath $outputZip) {
    Remove-Item -LiteralPath $outputZip -Force
}
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $outputZip -CompressionLevel Optimal
Write-Host "Pacote criado: $outputZip"
