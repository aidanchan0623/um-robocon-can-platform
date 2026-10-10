param([ValidateSet(250000,500000,1000000)][int]$CanBitrate=1000000)
$ErrorActionPreference='Stop'
$workspace=Split-Path $PSScriptRoot -Parent
$bin=(Get-ChildItem 'C:/ST/STM32CubeIDE*/STM32CubeIDE/plugins/*gnu-tools*/tools/bin/arm-none-eabi-gcc.exe'|Select-Object -First 1).DirectoryName
if(!$bin){throw 'ARM compiler missing'}
$cpu=@('-mcpu=cortex-m4','-mthumb','-mfpu=fpv4-sp-d16','-mfloat-abi=hard')
foreach($node in @('g474','g431')) {
  if($node -eq 'g474') {
    $root=Join-Path $workspace 'CAN_1M_TEST/firmware/g474-can-ping'
    $device='STM32G474xx'; $role=1; $startup='Core/Startup/startup_stm32g474retx.s'; $ld='STM32G474RETX_FLASH.ld'; $id=0x469
  } else {
    $root=Join-Path $workspace 'CAN_PWM_CONTROL/firmware/g431-node'
    $device='STM32G431xx'; $role=0; $startup='Core/Startup/startup_stm32g431rbtx.s'; $ld='STM32G431RBTX_FLASH.ld'; $id=0x468
  }
  $build=Join-Path $PSScriptRoot "Build/$node"; New-Item -ItemType Directory -Path $build -Force|Out-Null
  $flags=$cpu+@('-std=gnu11','-Og','-g3','-Wall','-Wextra','-Werror','-ffunction-sections','-fdata-sections','-DUSE_HAL_DRIVER',"-D$device","-DIG42_ENCODER_PULLUPS=1","-DCAN_BITRATE=$CanBitrate",'--specs=nano.specs')
  foreach($inc in @('Core/Inc','Drivers/STM32G4xx_HAL_Driver/Inc','Drivers/STM32G4xx_HAL_Driver/Inc/Legacy','Drivers/CMSIS/Device/ST/STM32G4xx/Include','Drivers/CMSIS/Include')) {$flags+='-I'+(Join-Path $root $inc)}
  $application=if($node -eq 'g474'){Join-Path $PSScriptRoot 'g474-master.c'}else{Join-Path $root 'Core/Src/main.c'}
  $sources=@(Get-Item $application,(Join-Path $root 'Core/Src/system_stm32g4xx.c'),(Join-Path $root 'Core/Src/syscalls.c'),(Join-Path $root 'Core/Src/sysmem.c'),(Join-Path $root $startup))
  if($node -eq 'g431') { $sources+=@(Get-Item (Join-Path $root 'Core/Src/stm32g4xx_it.c'),(Join-Path $root 'Core/Src/stm32g4xx_hal_msp.c')) }
  $sources+=@(Get-ChildItem (Join-Path $root 'Drivers/STM32G4xx_HAL_Driver/Src') -Filter '*.c')
  $objects=@(); $index=0
  foreach($source in $sources) {
    $obj=Join-Path $build "$index-$($source.BaseName).o"
    & "$bin/arm-none-eabi-gcc.exe" @flags -c $source.FullName -o $obj
    if($LASTEXITCODE){throw "Compile failed: $source"}; $objects+=$obj; $index++
  }
  $elf=Join-Path $build "$node.elf"
  & "$bin/arm-none-eabi-gcc.exe" @cpu @objects -T (Join-Path $root $ld) --specs=nano.specs --specs=nosys.specs '-Wl,--gc-sections,--fatal-warnings' "-Wl,-Map=$build/$node.map" '-Wl,--start-group' -lc -lm '-Wl,--end-group' -o $elf
  if($LASTEXITCODE){throw 'Link failed'}
  & "$bin/arm-none-eabi-objcopy.exe" -O binary $elf "$build/$node.bin"
  if($LASTEXITCODE){throw 'Binary conversion failed'}
  $symbols=& "$bin/arm-none-eabi-nm.exe" -n $elf
  $match=$symbols|Select-String '^([0-9a-fA-F]+) [BD] bench$'
  if(!$match){throw 'Mailbox missing'}
  $diag=$symbols|Select-String '^([0-9a-fA-F]+) [BD] diagnostics$'
  $edge=$symbols|Select-String '^([0-9a-fA-F]+) [BD] encoder_trace$'
  $canDiag=$symbols|Select-String '^([0-9a-fA-F]+) [BD] can_diagnostics$'
  $edgeAddress=if($edge){[Convert]::ToUInt32($edge.Matches[0].Groups[1].Value,16)}else{0}
  $canDiagAddress=if($canDiag){[Convert]::ToUInt32($canDiag.Matches[0].Groups[1].Value,16)}else{0}
  $diagnosticsAddress=if($diag){[Convert]::ToUInt32($diag.Matches[0].Groups[1].Value,16)}else{0}
  @{magic=0x43414E50;ig42_pullups=$true;can_only=$false;can_bitrate=$CanBitrate;diagnostics_address=$diagnosticsAddress;encoder_trace_address=$edgeAddress;can_diagnostics_address=$canDiagAddress;mailbox_address=[Convert]::ToUInt32($match.Matches[0].Groups[1].Value,16);role=$role;device_id=$id;bitrate=$CanBitrate;elf=$elf;sha256=(Get-FileHash $elf).Hash}|ConvertTo-Json|Set-Content "$build/interface.json" -Encoding ASCII
  if($node -eq 'g474'){ Copy-Item -LiteralPath "$build/interface.json" -Destination "$PSScriptRoot/Build/interface.json" }
  & "$bin/arm-none-eabi-size.exe" $elf
}
