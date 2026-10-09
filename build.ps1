param(
    [string]$Version = "0.4.0"
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$dist = Join-Path $root "dist"
$runtime = Join-Path $root "tools\love-11.5-win64"
$gameLove = Join-Path $root "game.love"
$gameLoveZip = Join-Path $dist ".game-love-build.zip"
$bundleName = "HaxBall-RS-v$Version.zip"
$bundleZip = Join-Path $dist $bundleName
$bundleDir = Join-Path $dist "HaxBall-RS"
$stage = Join-Path $dist ".game-love-stage"

function Copy-GameTree($source, $destination) {
    $excludedDirectories = @(".git", "tests", "dist", "tools", "saves", "save", "docs", "documentation", "scripts")
    foreach ($file in Get-ChildItem -LiteralPath $source -Recurse -File -Force) {
        $relative = $file.FullName.Substring($source.Length).TrimStart([char[]]@('\', '/'))
        $parts = $relative -split '[\\/]'
        if ($parts | Where-Object { $excludedDirectories -contains $_ }) { continue }
        if ($file.Name -match '^(README|PUBLISHING)(\.|$)' -or $file.Extension -match '^\.(love|zip|exe|sav|save)$') { continue }
        $target = Join-Path $destination $relative
        $targetDirectory = Split-Path -Parent $target
        New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $target
    }
}

if (-not (Test-Path -LiteralPath (Join-Path $runtime "love.exe"))) {
    throw "Runtime LÖVE 11.5 x64 não encontrado em tools\love-11.5-win64."
}
if (-not (Test-Path -LiteralPath (Join-Path $runtime "love.dll"))) {
    throw "love.dll não encontrado no runtime portátil."
}
foreach ($required in @("main.lua", "conf.lua", "src", "net")) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $required))) {
        throw "Arquivo ou pasta necessária ausente: $required"
    }
}

New-Item -ItemType Directory -Path $dist -Force | Out-Null
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage | Out-Null
Copy-Item -LiteralPath (Join-Path $root "main.lua") -Destination $stage
Copy-Item -LiteralPath (Join-Path $root "conf.lua") -Destination $stage
Copy-GameTree (Join-Path $root "src") (Join-Path $stage "src")
Copy-GameTree (Join-Path $root "net") (Join-Path $stage "net")
$assets = Join-Path $root "assets"
if (Test-Path -LiteralPath $assets) { Copy-GameTree $assets (Join-Path $stage "assets") }

if (Test-Path -LiteralPath $gameLove) { Remove-Item -LiteralPath $gameLove -Force }
if (Test-Path -LiteralPath $gameLoveZip) { Remove-Item -LiteralPath $gameLoveZip -Force }
Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $gameLoveZip -CompressionLevel Optimal
Move-Item -LiteralPath $gameLoveZip -Destination $gameLove

if (Test-Path -LiteralPath $bundleDir) { Remove-Item -LiteralPath $bundleDir -Recurse -Force }
New-Item -ItemType Directory -Path $bundleDir | Out-Null
Copy-Item -LiteralPath (Join-Path $runtime "love.exe") -Destination $bundleDir
Get-ChildItem -LiteralPath $runtime -Filter "*.dll" -File | Copy-Item -Destination $bundleDir
$license = Join-Path $runtime "license.txt"
if (-not (Test-Path -LiteralPath $license)) { $license = Join-Path $root "bin\love\license.txt" }
if (-not (Test-Path -LiteralPath $license)) { throw "license.txt do LÖVE não foi encontrado."
}
Copy-Item -LiteralPath $license -Destination (Join-Path $bundleDir "license.txt")
Copy-Item -LiteralPath $gameLove -Destination $bundleDir
Copy-Item -LiteralPath (Join-Path $root "LEIA-ME.txt") -Destination $bundleDir
$launcher = "@echo off`r`ncd /d `"%~dp0`"`r`nlove.exe game.love`r`n"
[System.IO.File]::WriteAllText((Join-Path $bundleDir "Jogar.bat"), $launcher, [System.Text.Encoding]::ASCII)

if (Test-Path -LiteralPath $bundleZip) { Remove-Item -LiteralPath $bundleZip -Force }
Compress-Archive -Path $bundleDir -DestinationPath $bundleZip -CompressionLevel Optimal
Copy-Item -LiteralPath $gameLove -Destination (Join-Path $dist "game.love") -Force
Remove-Item -LiteralPath $stage -Recurse -Force

$zipInfo = Get-Item -LiteralPath $bundleZip
$loveInfo = Get-Item -LiteralPath (Join-Path $dist "game.love")
Write-Host "Pacote criado: $($zipInfo.FullName) ($([math]::Round($zipInfo.Length / 1MB, 2)) MB)"
Write-Host "Pacote LÖVE:  $($loveInfo.FullName) ($([math]::Round($loveInfo.Length / 1KB, 1)) KB)"
