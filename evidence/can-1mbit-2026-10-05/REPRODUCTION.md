# Reproducing this bench test

This folder contains the completed test records, report-viewer screenshots, source overlays and the host harness. The original 250 kbit/s firmware folders are unchanged. Hardware setup and measurements are performed manually; diagnostic firmware and host automation were prepared with AI assistance.

The [provenance register](../../docs/firmware-provenance.md) identifies the source/harness archive commit, tested image hashes and the `v0.2.0-bench-validation` release. The archive commit was created after the experiments; exact BIN-hash reproduction, not a fabricated flash-time commit, links this source to the records.

## Offline build

From this repository root in PowerShell 7, choose a new output directory outside the repository's existing firmware projects:

```powershell
./evidence/can-1mbit-2026-10-05/reproduce-build.ps1 -OutputDirectory 'D:/bench/can1m-reproduction' -ToolBin 'D:/your-stm32-gcc/bin'
```

The script copies the two archived Nucleo projects, applies the source overlays, and reuses the same STM32G4 UART HAL files already vendored in `g474-vesc-dual`. It builds both projects without communicating with or flashing any hardware. The original source folders are not modified. The F303 source is linked into its copied IDE project; the G474 CAN IOC contains CAN timing but not the manually initialised UART, so do not regenerate blindly.

The offline reproduction was actually run with the same installed GCC 14.3 toolchain after the bench test. Both `.bin` images matched the tested build's SHA-256:

| Firmware | SHA-256 of exported binary |
| --- | --- |
| G474 | `E27E7EEA58DE54E5888BC552F1F6DE0B7136054F2BB4C21C91297DE8625242CB` |
| F303 | `0ACD2C2AD4172D83BB5F0D767B0931B2310313019251F745394E4FAB42251AA0` |

Debug ELF hashes can differ with absolute build paths. ELF hashes of the actual flashed builds are retained in `manifest.json`. Generated binaries, full flash backups and private probe identifiers are not included in this evidence folder.

## Run on hardware

Each Nucleo needs its own powered transceiver. PA12 is CAN TX and PA11 is CAN RX on both boards. Use a common ground, connect H to H and L to L, isolate competing onboard MCU outputs and terminate only the two cable ends. Power the transceivers before resetting the MCUs. Disconnect ESCs: these firmwares implement a synthetic echo test, not motor control.

After manually flashing the matching builds and verifying execution, discover the G474 ST-LINK virtual COM port and the F303 ST-LINK serial number. The host harness **resets the F303** and **starts CAN traffic on the G474**; unlike the offline builder, this script changes the boards' live state. Use it only on the isolated bench-test arrangement.

```powershell
$programmer = 'D:/STM32CubeProgrammer/bin/STM32_Programmer_CLI.exe'
$probeSerial = 'YOUR_F303_STLINK_SERIAL'
$runDirectory = 'D:/bench/results/new-run'
./evidence/can-1mbit-2026-10-05/tools/run-link-test.ps1 -Rate 100 -Seconds 15 -RunDirectory $runDirectory -Programmer $programmer -F303Serial $probeSerial -Port COM7
./evidence/can-1mbit-2026-10-05/tools/run-link-test.ps1 -Rate 1000 -Seconds 30 -RunDirectory $runDirectory -Programmer $programmer -F303Serial $probeSerial -Port COM7
./evidence/can-1mbit-2026-10-05/tools/run-link-test.ps1 -Rate 2500 -GoalPairs 1000000 -MaxSeconds 600 -RunDirectory $runDirectory -Programmer $programmer -F303Serial $probeSerial -Port COM7
./evidence/can-1mbit-2026-10-05/tools/write-results.ps1 -RunDirectory $runDirectory
```

Do not escalate load if a stage fails. The harness pauses G474 on completion/failure and preserves raw logs; it is not a hard real-time emergency-stop system. The F303 diagnostic read assumes the archived build's `canEcho` address `0x20000250` and 76-byte layout. Verify the symbol with `arm-none-eabi-nm` if the firmware or toolchain is changed. The magic/ready checks reject unrelated memory layouts rather than treating arbitrary data as a pass.

To view progress in a separate read-only terminal, run `tools/show-live-test.ps1 -RunDirectory <your-run-directory>`. Closing that viewer does not stop the test process or send commands. Do not use another serial application on the same COM port during a run.

The screenshots are actual captures of a report viewer displaying summaries generated from the recorded stage JSON. They are not original CAN waveforms, not a per-frame analyser capture, and not additional independent measurements. See [README.md](README.md) for results and limitations.
