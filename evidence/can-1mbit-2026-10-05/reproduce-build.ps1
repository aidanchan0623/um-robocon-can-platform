param(
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [Parameter(Mandatory=$true)][string]$ToolBin
)
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $outputRoot) { throw 'Choose a NEW output directory; existing work is never overwritten.' }
New-Item -ItemType Directory -Path $outputRoot | Out-Null
foreach ($project in 'g474-can-ping','f303-can-reply') {
    $sourceRoot = Join-Path $repoRoot "firmware/$project"
    $targetRoot = Join-Path $outputRoot "firmware/$project"
    foreach ($file in Get-ChildItem -LiteralPath $sourceRoot -Recurse -File -Force) {
        $relative = $file.FullName.Substring($sourceRoot.Length).TrimStart('\','/')
        if ($relative -match '(^|[\\/])(Build|Debug|Release|\.settings|\.metadata|Backup)([\\/]|$)') { continue }
        $target = Join-Path $targetRoot $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $target
    }
    $overlay = Join-Path $PSScriptRoot "firmware-overlays/$project"
    foreach ($file in Get-ChildItem -LiteralPath $overlay -Recurse -File -Force) {
        $relative = $file.FullName.Substring($overlay.Length).TrimStart('\','/')
        $target = Join-Path $targetRoot $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $target -Force
    }
}
$vendorSource = Join-Path $repoRoot 'firmware/g474-vesc-dual/Drivers/STM32G4xx_HAL_Driver'
$vendorTarget = Join-Path $outputRoot 'firmware/g474-can-ping/Drivers/STM32G4xx_HAL_Driver'
foreach ($relative in 'Inc/stm32g4xx_hal_uart.h','Inc/stm32g4xx_hal_uart_ex.h','Inc/stm32g4xx_ll_lpuart.h','Src/stm32g4xx_hal_uart.c','Src/stm32g4xx_hal_uart_ex.c') {
    Copy-Item -LiteralPath (Join-Path $vendorSource $relative) -Destination (Join-Path $vendorTarget $relative)
}
New-Item -ItemType Directory -Path (Join-Path $outputRoot 'tools') | Out-Null
Copy-Item -LiteralPath (Join-Path $repoRoot 'tools/build.ps1') -Destination (Join-Path $outputRoot 'tools/build.ps1')
& (Join-Path $outputRoot 'tools/build.ps1') -Project g474-can-ping -ToolBin $ToolBin
& (Join-Path $outputRoot 'tools/build.ps1') -Project f303-can-reply -ToolBin $ToolBin
Write-Host 'Offline reproduction complete. NO connected hardware was reset, flashed or commanded.'
Write-Host 'ELF hashes can differ because debug information contains absolute build paths.'
Get-FileHash -LiteralPath (Join-Path $outputRoot 'firmware/g474-can-ping/Build/g474-can-ping.bin'),(Join-Path $outputRoot 'firmware/f303-can-reply/Build/f303-can-reply.bin')
