# Firmware and result provenance

The 250 kbit/s demonstration and 1 Mbit/s integrity test are different applications. Building the original firmware folders alone produces the demonstration, not the integrity-test image. The release tag **v0.2.0-bench-validation** freezes both snapshots and their evidence; it is an evidence release, not robot qualification.

## Application identities

| Application/version | Controllers and protocol | Archived source identity | Result attribution |
| --- | --- | --- | --- |
| Historical ping/reply snapshot | External G474/F303, 250 kbit/s, standard IDs 0x123/0x124, one-byte 0x55 payload | [Initial source archive 79ce6a0](https://github.com/aidanchan0623/um-robocon-can-platform/tree/79ce6a096ac2eae71ba84228d585e51d691aa270/firmware) | Historical LED/communication demonstration; no exact flash-time commit/hash recorded |
| Historical one-/two-VESC snapshots | External G474, 250 kbit/s, VESC extended-ID commands and Status 1 | Same archive commit; [single](../firmware/g474-vesc-single) / [dual](../firmware/g474-vesc-dual) | Unloaded motor records; no exact flash-time commit/hash recorded |
| CAN1M diagnostic snapshot, 2026-10-05 | External G474/F303, 1 Mbit/s, standard IDs 0x601/0x602, eight-byte requests/echoes | [Source/harness archive 0ccd0e3](https://github.com/aidanchan0623/um-robocon-can-platform/commit/0ccd0e312e52ea0b423d85023be7b91842ce3f78), using [overlays](../evidence/can-1mbit-2026-10-05/firmware-overlays) and archived base projects | Both 5 October datasets use the binary hashes below; reproduction matches them |
| G431 USART3 archive | Onboard G431, PC10 TX, 9600 baud, repeated UART message | [g431-uart](../firmware/g431-uart) in the historical source archive | Does not identify the exact image used for the reported 5 October recovery |

**The archive commits were created after the experiments.** They did not exist as recorded flash-time Git identities. The 1 Mbit/s source-to-result link is established by binary-hash reproduction, not by inventing a historical tested commit. The older demonstrations have weaker provenance and should retain that distinction.

## Tested 1 Mbit/s binary identities

The [initial manifest](../evidence/can-1mbit-2026-10-05/manifest.json) records the actual tested ELF and exported BIN hashes. The [extended dataset's identity](../evidence/can-1mbit-endurance-2026-10-05/baseline-firmware-identification.json) refers to the same firmware.

| Target | Tested/reproduced BIN SHA-256 |
| --- | --- |
| G474 | `E27E7EEA58DE54E5888BC552F1F6DE0B7136054F2BB4C21C91297DE8625242CB` |
| F303 | `0ACD2C2AD4172D83BB5F0D767B0931B2310313019251F745394E4FAB42251AA0` |

For publication on 5 October, both applications were rebuilt offline with STM32 GNU Tools GCC 14.3, the archived builder, unchanged base projects and committed overlays. Both BIN hashes matched. ELF hashes may differ because debug information embeds build paths. Generated binaries, complete flash backups and probe identifiers are excluded from the public archive.

Nominal settings: G474 HSI/PCLK1 16 MHz, prescaler 1; F303 HSI/PLL with PCLK1 32 MHz, prescaler 2. Both have 1 + 11 + 4 = 16 TQ, 75% sample point and 4-TQ SJW, normal Classic CAN and automatic retransmission. Actual oscillator error across operating conditions was not measured.

## Build and audit this release

Follow the [offline reproduction procedure](../evidence/can-1mbit-2026-10-05/REPRODUCTION.md) from the tagged source. The builder makes a new output directory and never contacts hardware. Compare the resulting BIN hashes with the table above before attributing a new hardware run to these images.

Run `./tools/audit-can-evidence.ps1` to reconcile all 16 archived stages from their raw G474 serial and F303 SWD records. This is also offline. The [aggregate record](../evidence/can-validation-2026-10-05.json) identifies the source archive commit and the combined 5,330,951-pair result. The [stage-data commit 5ea073e](https://github.com/aidanchan0623/um-robocon-can-platform/commit/5ea073e91870e9d793bb35a46ea6a9eb39ea9ce3) contains the published raw records and JSON.

Existing result-viewer screenshots show summaries of those records, not independent CAN waveforms. Host scripts in the evidence directories are the archived experiment tools. Publication strips probe serial identifiers from SWD/reset logs; traffic counters, timestamps and payload-test results are retained. Local host-launch files containing personal absolute paths were excluded. The raw trace data are not reformatted to erase warnings or preparation anomalies.

For future runs, record the source commit, compiler version, image hash, target identity, programmer verification, wiring/termination, cable length, clock source and run parameters at acquisition time. The [G431 recovery evidence register](../evidence/g431-swdio-2026-10-05/README.md) remains pending for those flash/measurement records.

No project-wide license has been selected for original team material; the release preserves [third-party terms and notices](../THIRD_PARTY_NOTICES.md).
