# Offline build only: no programmer, serial connection or motor commands.
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('g431-uart','g474-can-ping','f303-can-reply','g474-vesc-single','g474-vesc-dual')]
    [string]$Project,
    [string]$ToolBin
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$projectRoot = Join-Path $repoRoot ("firmware\$Project")
if ($ToolBin) {
    $compiler = Join-Path $ToolBin 'arm-none-eabi-gcc.exe'
} else {
    $compiler = (Get-Command arm-none-eabi-gcc -ErrorAction Stop).Source
    $ToolBin = Split-Path -Parent $compiler
}
$objcopy = Join-Path $ToolBin 'arm-none-eabi-objcopy.exe'
$size = Join-Path $ToolBin 'arm-none-eabi-size.exe'
foreach ($tool in @($compiler,$objcopy,$size)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw "Missing tool: $tool" }
}
$family = 'G4'
$device = 'STM32G474xx'
$sourceDir = 'Core\Src'
$headerDir = 'Core\Inc'
$startupDir = 'Core\Startup'
$extraSources = @()
$linker = 'STM32G474RETX_FLASH.ld'
switch ($Project) {
    'g431-uart' { $device = 'STM32G431xx'; $linker = 'STM32G431RBTX_FLASH.ld' }
    'f303-can-reply' {
        $family = 'F3'; $device = 'STM32F303xE'
        $sourceDir = 'Src'; $headerDir = 'Inc'
        $startupDir = 'STM32CubeIDE\Application\Startup'
        $linker = 'STM32CubeIDE\STM32F303RETX_FLASH.ld'
        $extraSources = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'STM32CubeIDE\Application\User') -Filter '*.c' | Select-Object -ExpandProperty FullName)
    }
}
$buildDir = Join-Path $projectRoot 'Build'
New-Item -ItemType Directory -Path $buildDir -Force | Out-Null
$cpuFlags = @('-mcpu=cortex-m4','-mthumb','-mfpu=fpv4-sp-d16','-mfloat-abi=hard')
$flags = $cpuFlags + @('-std=gnu11','-Og','-g3','-Wall','-Wextra','-Werror','-ffunction-sections','-fdata-sections','-DUSE_HAL_DRIVER',"-D$device",'--specs=nano.specs')
$includes = @($headerDir,"Drivers\STM32${family}xx_HAL_Driver\Inc","Drivers\STM32${family}xx_HAL_Driver\Inc\Legacy","Drivers\CMSIS\Device\ST\STM32${family}xx\Include",'Drivers\CMSIS\Include')
foreach ($include in $includes) { $flags += '-I' + (Join-Path $projectRoot $include) }
$sources = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot $sourceDir) -Filter '*.c' | Select-Object -ExpandProperty FullName)
$sources += $extraSources
$halSources = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot "Drivers\STM32${family}xx_HAL_Driver\Src") -Filter '*.c')
if ($Project -eq 'f303-can-reply') {
    # CubeMX's Basic F3 layout vendors optional templates as well as drivers.
    # Compile only the HAL files selected by the existing IDE project.
    [xml]$ideProject = Get-Content -LiteralPath (Join-Path $projectRoot 'STM32CubeIDE\.project') -Raw
    $halNames = @($ideProject.projectDescription.linkedResources.link |
        Where-Object { $_.name -like 'Drivers/STM32F3xx_HAL_Driver/*.c' } |
        ForEach-Object { [IO.Path]::GetFileName($_.name) })
    $halSources = @($halSources | Where-Object { $_.Name -in $halNames })
    if ($halSources.Count -ne $halNames.Count) { throw 'F303 IDE-selected HAL sources are missing.' }
}
$sources += @($halSources | Select-Object -ExpandProperty FullName)
$sources += @(Get-ChildItem -LiteralPath (Join-Path $projectRoot $startupDir) -Filter '*.s' | Select-Object -ExpandProperty FullName)
$objects = @()
$index = 0
foreach ($source in $sources) {
    $object = Join-Path $buildDir ("$index-" + [IO.Path]::GetFileNameWithoutExtension($source) + '.o')
    $sourceFlags = $flags
    # ST's F3 EXTI driver has two unused Edge arguments on this device.
    # Keep third-party source intact; retain -Werror for every other warning.
    if ($Project -eq 'f303-can-reply' -and [IO.Path]::GetFileName($source) -eq 'stm32f3xx_hal_exti.c') {
        $sourceFlags += '-Wno-unused-parameter'
    }
    & $compiler @sourceFlags -c $source -o $object
    if ($LASTEXITCODE -ne 0) { throw "Compilation failed: $source" }
    $objects += $object
    $index++
}
$elf = Join-Path $buildDir "$Project.elf"
& $compiler @cpuFlags @objects -T (Join-Path $projectRoot $linker) --specs=nano.specs --specs=nosys.specs '-Wl,--gc-sections' ("-Wl,-Map=" + (Join-Path $buildDir "$Project.map")) '-Wl,--start-group' -lc -lm '-Wl,--end-group' -o $elf
if ($LASTEXITCODE -ne 0) { throw 'Link failed.' }
& $objcopy -O binary $elf (Join-Path $buildDir "$Project.bin")
if ($LASTEXITCODE -ne 0) { throw 'Binary export failed.' }
& $objcopy -O ihex $elf (Join-Path $buildDir "$Project.hex")
if ($LASTEXITCODE -ne 0) { throw 'HEX export failed.' }
& $size $elf
if ($LASTEXITCODE -ne 0) { throw 'Size inspection failed.' }
Write-Host "Built $Project (offline only): $elf"
