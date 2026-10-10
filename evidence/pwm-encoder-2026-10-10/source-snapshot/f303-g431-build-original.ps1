param([string]$ToolBin,[ValidateSet(250000,500000,1000000)][int]$CanBitrate=1000000,[switch]$CanOnly)
$ErrorActionPreference='Stop'
if(!$ToolBin){$ToolBin=(Get-ChildItem 'C:\ST\STM32CubeIDE*\STM32CubeIDE\plugins\*gnu-tools*\tools\bin\arm-none-eabi-gcc.exe'|Select-Object -First 1).DirectoryName}
if(!$ToolBin){throw 'ARM compiler missing'}
$gcc=Join-Path $ToolBin 'arm-none-eabi-gcc.exe'
$cpu=@('-mcpu=cortex-m4','-mthumb','-mfpu=fpv4-sp-d16','-mfloat-abi=hard')
foreach($project in @('g431-node','f303-master')){
  $root=Join-Path $PSScriptRoot "firmware\$project"
  $build=Join-Path $root 'Build';New-Item -ItemType Directory -Path $build -Force|Out-Null
  if($project -eq 'g431-node'){$family='G4';$device='STM32G431xx';$src='Core\Src';$inc='Core\Inc';$startup='Core\Startup';$ld='STM32G431RBTX_FLASH.ld'}
  else{$family='F3';$device='STM32F303xE';$src='Src';$inc='Inc';$startup='STM32CubeIDE\Application\Startup';$ld='STM32CubeIDE\STM32F303RETX_FLASH.ld'}
  $flags=$cpu+@('-std=gnu11','-Og','-g3','-Wall','-Wextra','-Werror','-ffunction-sections','-fdata-sections','-DUSE_HAL_DRIVER',"-D$device",'--specs=nano.specs')
  $flags+=@("-DCAN_BITRATE=$CanBitrate", "-DCAN_ONLY_TEST=$([int][bool]$CanOnly)")
  foreach($dir in @($inc,"Drivers\STM32${family}xx_HAL_Driver\Inc","Drivers\STM32${family}xx_HAL_Driver\Inc\Legacy","Drivers\CMSIS\Device\ST\STM32${family}xx\Include",'Drivers\CMSIS\Include')){$flags+='-I'+(Join-Path $root $dir)}
  $sources=@(Get-ChildItem (Join-Path $root $src) -Filter '*.c'|Where-Object { $_.Name -ne 'can_echo_test.c' -and ($family -eq 'G4' -or $_.Name -ne 'main.c') })
  $hal=Join-Path $root "Drivers\STM32${family}xx_HAL_Driver\Src"
  if($family -eq 'G4'){$sources+=@(Get-ChildItem $hal -Filter '*.c')}
  else{
    $sources+=@(Get-ChildItem (Join-Path $root 'STM32CubeIDE\Application\User') -Filter '*.c')
    foreach($name in @('stm32f3xx_hal.c','stm32f3xx_hal_can.c','stm32f3xx_hal_cortex.c','stm32f3xx_hal_gpio.c','stm32f3xx_hal_rcc.c','stm32f3xx_hal_rcc_ex.c','stm32f3xx_hal_flash.c','stm32f3xx_hal_flash_ex.c','stm32f3xx_hal_pwr.c','stm32f3xx_hal_pwr_ex.c')){$sources+=Get-Item (Join-Path $hal $name)}
  }
  $sources+=@(Get-ChildItem (Join-Path $root $startup) -Filter '*.s');$objects=@();$index=0
  foreach($source in $sources){$obj=Join-Path $build "$index-$($source.BaseName).o";& $gcc @flags -c $source.FullName -o $obj;if($LASTEXITCODE){throw "Compile failed: $source"};$objects+=$obj;$index++}
  $elf=Join-Path $build "$project.elf"
  & $gcc @cpu @objects -T (Join-Path $root $ld) --specs=nano.specs --specs=nosys.specs '-Wl,--gc-sections' "-Wl,-Map=$build\$project.map" '-Wl,--start-group' -lc -lm '-Wl,--end-group' -o $elf
  if($LASTEXITCODE){throw 'Link failed'}
  & "$ToolBin\arm-none-eabi-objcopy.exe" -O binary $elf "$build\$project.bin";if($LASTEXITCODE){throw 'objcopy failed'}
  $symbols=& "$ToolBin\arm-none-eabi-nm.exe" -n $elf
  $match=$symbols|Select-String '^([0-9a-fA-F]+) [BD] bench$';if(!$match){throw 'Mailbox missing'}
  $address=[Convert]::ToUInt32($match.Matches[0].Groups[1].Value,16)
  $metadata=@{mailbox_address=$address;magic=1128353360;version=1;elf=$elf;can_bitrate=$CanBitrate;can_only=[bool]$CanOnly}
  if($project -eq 'g431-node') {
    $canDiagMatch=$symbols|Select-String '^([0-9a-fA-F]+) [BD] can_diagnostics$'
    if(!$canDiagMatch){throw 'G431 CAN diagnostic record missing'}
    $metadata.can_diagnostics_address=[Convert]::ToUInt32($canDiagMatch.Matches[0].Groups[1].Value,16)
  }
  if($project -eq 'f303-master') {
    $diagMatch=$symbols|Select-String '^([0-9a-fA-F]+) [BD] diagnostics$'
    if(!$diagMatch){throw 'Diagnostics missing'}
    $metadata.diagnostics_address=[Convert]::ToUInt32($diagMatch.Matches[0].Groups[1].Value,16)
  }
  $metadata|ConvertTo-Json|Set-Content "$build\interface.json" -Encoding ASCII
  if($project -eq 'f303-master'){New-Item -ItemType Directory "$PSScriptRoot\Build" -Force|Out-Null;Copy-Item "$build\interface.json" "$PSScriptRoot\Build\interface.json"}
  & "$ToolBin\arm-none-eabi-size.exe" $elf
}
