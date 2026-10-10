# Source appendix — review snapshot, not a standalone application

Copied from the active bench workspace on 10 October 2026. Original application code was not changed while preparing this archive. This appendix omits startup, HAL/CMSIS dependencies, headers, linker files and runtime build metadata, so it is **not a self-contained flashing package**. Do not flash a historical application or stale ELF as though it contains this firmware.

| File | Active-workspace origin |
| --- | --- |
| `controller.py` | `CAN_PWM_CONTROL/controller.py` |
| `test_controller.py` | `CAN_PWM_CONTROL/test_controller.py` |
| `g431-main.c` | `CAN_PWM_CONTROL/firmware/g431-node/Core/Src/main.c` |
| `f303-can-master.c` | `CAN_PWM_CONTROL/firmware/f303-master/Src/can_master.c` |
| `f303-g431-build-original.ps1` | `CAN_PWM_CONTROL/build.ps1` |
| `g474-g431-pullup-build-original.ps1` | `CAN_G474_PWM/build.ps1` |

The F303 master application is `can_master.c`, not the older inherited `main.c`. The selected G431 build comes from the second build script's G431 branch with `-DIG42_ENCODER_PULLUPS=1` and 1 Mbit/s selected; its G474 branch does not change the F303 role in this demonstration. The original F303/G431 script does **not** pass the pull-up flag, so rebuilding through it unchanged would use the G431 source default of pull-ups off. These scripts are retained as provenance, not recommended launchers from this appendix.

The tested host code can be checked offline here:

```text
python -m unittest -v test_controller
```

These 26 tests use mocks and do not access hardware. Opening the original GUI does not itself connect or arm, but manual connection/control actions do contact the bridge. Do not run motor commands without appropriate physical precautions.

The exact image identities of the supplied videos were not independently captured at recording time. The SHA256 manifest freezes this source review snapshot only. A portable, integrated firmware application and automated build workflow should be reviewed separately before a new firmware release.
