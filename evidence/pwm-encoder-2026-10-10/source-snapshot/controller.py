"""Dependency-free Tk control panel. Talks to RUNNING firmware through OpenOCD.
Opening this program does NOT connect, flash, reset, or enable PWM.
"""
from __future__ import annotations
import argparse
import csv
import datetime as dt
import json
from pathlib import Path
import queue
import socket
import subprocess
import threading
import time
import tkinter as tk
from tkinter import ttk, messagebox

ROOT = Path(__file__).resolve().parent
MAGIC = 0x43414E50
WORDS = 16
FAULTS = {0: "none", 1: "CAN heartbeat lost; Stop before re-arm", 3: "G431 loop stalled",
          4: "G431 telemetry missing/stale", 6: "G431/legacy CAN fault latched",
          20: "F303 loop delay >10 ms", 21: "F303 hardware RX FIFO overflow",
          22: "F303 software RX queue overflow", 23: "F303 HAL receive failure",
          24: "F303 CAN error-passive/bus-off", 25: "F303 waiting for stable startup bus"}
DIAG_FIELDS = ('magic','version','snapshot','fault_bits','first_reason','first_tick',
               'first_esr','first_rf0r','first_hal_error','max_loop_ms','rx_frames',
               'invalid_frames','complete_snapshots','queue_high_water','fifo_overruns',
               'queue_overruns','receive_errors','loop_stalls','telemetry_age_ms',
               'remote_valid','remote_fault','controller_ready','startup_controller_events',
               'startup_first_tick','startup_first_esr','startup_last_esr')

def decode_diagnostics(values):
    if len(values) != len(DIAG_FIELDS) or values[:2] != [0x43414E44, 2]:
        raise RuntimeError("Wrong F303 diagnostics; rebuild/flash matching firmware")
    return {'bridge_' + key: value for key, value in zip(DIAG_FIELDS, values)}

def peer_ready(status):
    return status['fault'] == 0 and not status.get('bridge_fault_bits', 0) and (
        'bridge_remote_valid' not in status or (
            status['bridge_remote_valid'] and status['bridge_telemetry_age_ms'] < 250 and
            status['bridge_controller_ready']))

def status_prefix(status):
    if 'bridge_remote_valid' in status:
        if not status['bridge_remote_valid'] or status['bridge_telemetry_age_ms'] >= 250:
            return 'REMOTE STALE (last known)'
        if status['fault'] == 25:
            return 'LIVE TELEMETRY / STARTUP LOCKED'
        if status['fault'] or status['bridge_fault_bits']:
            return 'LIVE TELEMETRY / FAULT LATCHED'
    elif status['fault'] == 4:
        return 'REMOTE STALE (last known)'
    elif status['fault']:
        return 'FAULT LATCHED / freshness unknown'
    return 'ARMED' if status['armed'] else 'DISARMED'

def signed(value: int, bits: int = 32) -> int:
    value &= (1 << bits) - 1
    return value - (1 << bits) if value & (1 << (bits - 1)) else value

def remote_fresh(status):
    if 'bridge_remote_valid' in status:
        return bool(status['bridge_remote_valid']) and status['bridge_telemetry_age_ms'] < 250
    return status['fault'] != 4

def encoder_display(status):
    if not remote_fresh(status):
        return 'Count: — (no live data)', 'Counts/s: —', 'A/B: —   Timer raw: —'
    details = f"A: {status['a']}   B: {status['b']}   Timer raw: {status['raw']}"
    if status.get('encoder_diagnostics'):
        setup = 'OK' if status['encoder_config_ok'] else 'MISMATCH'
        details += (f"\nTIM4 setup: {setup}; sampled changes A/B: "
                    f"{status['encoder_a_changes']}/{status['encoder_b_changes']}")
    return f"Count: {status['count']:,}", f"Counts/s: {status['cps']:,}", details

def decode(words: list[int]) -> dict:
    if len(words) != WORDS or words[0] != MAGIC or words[1] != 1:
        raise RuntimeError("Wrong firmware/mailbox. Do not control this target.")
    return dict(tick=words[2], armed=words[3], fault=words[4], hz=words[5],
                pwm1=words[6], pwm2=words[7], raw=words[8],
                count=signed(words[9] | (words[10] << 32), 64),
                cps=signed(words[11]), a=words[12] & 1, b=(words[12] >> 1) & 1,
                ack=words[13], result=words[14], snapshot=words[15],
                encoder_diagnostics=bool(words[12] & 0x80),
                encoder_config_ok=bool(words[12] & 0x40),
                encoder_states_seen=(words[12] >> 2) & 15,
                encoder_a_changes=(words[12] >> 8) & 4095,
                encoder_b_changes=(words[12] >> 20) & 4095)

def validate_command(op, channel=0, duty=0, hz=1000):
    if op not in (1, 2, 3, 4, 5):
        raise ValueError("Invalid opcode")
    if op == 3 and (channel not in (1, 2) or not 0 <= duty <= 1000):
        raise ValueError("Duty/channel out of range")
    if op == 5 and not 100 <= hz <= 20000:
        raise ValueError("Frequency must be 100..20000 Hz")

def tool_paths():
    plugins = sorted(Path("C:/ST").glob("STM32CubeIDE*/STM32CubeIDE/plugins"))
    for folder in plugins:
        exe = next(folder.glob("*externaltools.openocd.win32*/tools/bin/openocd.exe"), None)
        cfg = next(folder.glob("*mcu.debug.openocd_*/resources/openocd/st_scripts/target/stm32f3x.cfg"), None)
        if exe and cfg:
            return exe, cfg.parent.parent
    raise RuntimeError("STM32CubeIDE OpenOCD not found. Install/configure it first.")

class TclConnection:
    def __init__(self, port):
        self.sock = socket.create_connection(("127.0.0.1", port), timeout=1)
        self.sock.settimeout(0.8)
        self.pending = b""

    def call(self, script):
        self.sock.sendall(script.encode("ascii") + b"\x1a")
        while b"\x1a" not in self.pending:
            data = self.sock.recv(65536)
            if not data:
                raise RuntimeError("OpenOCD disconnected")
            self.pending += data
        result, self.pending = self.pending.split(b"\x1a", 1)
        return result.decode("utf-8", errors="replace").strip()

    def read(self, address, count):
        # Explicit sentinel makes command failure distinguishable from data.
        out = self.call(f"set v [read_memory 0x{address:x} 32 {count}]; format {{OK %s}} $v")
        if not out.startswith("OK "):
            raise RuntimeError(out or "SWD memory read failed")
        try:
            values = [int(v, 0) for v in out[3:].split()]
        except ValueError as exc:
            raise RuntimeError(out) from exc
        if len(values) != count:
            raise RuntimeError("Incomplete SWD read")
        return values

    def write(self, address, values):
        payload = " ".join(str(v & 0xFFFFFFFF) for v in values)
        out = self.call(f"write_memory 0x{address:x} 32 {{{payload}}}; return OK")
        if out != "OK":
            raise RuntimeError(out or "SWD memory write failed")

    def snapshot(self, address, count, sequence_index):
        # Before/block/after in ONE RPC; protects against an update during the block.
        seq_address = address + sequence_index * 4
        out = self.call(f"set a [read_memory 0x{seq_address:x} 32 1]; "
                        f"set v [read_memory 0x{address:x} 32 {count}]; "
                        f"set b [read_memory 0x{seq_address:x} 32 1]; "
                        "format {OK %s %s %s} $a $v $b")
        if not out.startswith('OK '):
            raise RuntimeError(out or 'SWD snapshot read failed')
        values = [int(v, 0) for v in out[3:].split()]
        if len(values) != count + 2:
            raise RuntimeError('Incomplete SWD snapshot')
        before, block, after = values[0], values[1:-1], values[-1]
        if before == block[sequence_index] == after and not before & 1:
            return block
        return None

    def close(self):
        self.sock.close()

class Worker(threading.Thread):
    def __init__(self, serial, events, commands):
        super().__init__(daemon=True)
        self.serial, self.events, self.commands = serial, events, commands
        self.quit = threading.Event()
        self.link = None
        self.process = None
        self.log_handle = None
        self.address = 0
        self.diagnostics_address = 0
        self.seq = 0
        self.hb = 0

    def status(self):
        # Never halt, reset or clear a fault to obtain a coherent snapshot.
        def coherent(address, count, sequence_index):
            for _ in range(16):
                values = self.link.snapshot(address, count, sequence_index)
                if values is not None:
                    return values
                # Avoid repeatedly aligning USB reads with the 20-ms publisher.
                time.sleep(0.001)
            raise RuntimeError("No coherent snapshot: SWD too slow or firmware stalled")

        # Each block has its own seqlock and publication time. A collision in
        # diagnostics must not throw away an already coherent mailbox read.
        status = decode(coherent(self.address, WORDS, 15))
        if self.diagnostics_address:
            diag = coherent(self.diagnostics_address, len(DIAG_FIELDS), 2)
            status.update(decode_diagnostics(diag))
        return status

    def heartbeat(self):
        self.hb = (self.hb + 1) & 0xFFFFFFFF or 1
        self.link.write(self.address + 64, [self.hb])

    def command(self, op, channel=0, duty=0, hz=1000):
        validate_command(op, channel, duty, hz)
        self.seq = (self.seq + 1) & 0xFFFFFFFF or 1
        # Fields first, sequence last: target cannot execute a half-written request.
        self.link.write(self.address + 72, [op, channel, duty, hz])
        self.link.write(self.address + 68, [self.seq])
        deadline = time.monotonic() + 0.8
        while time.monotonic() < deadline:
            reply = self.link.read(self.address + 52, 2)
            if reply[0] == self.seq:
                if reply[1]:
                    raise RuntimeError(f"Command rejected/unconfirmed: code {reply[1]}; inspect remote state and physical outputs")
                return
            time.sleep(0.01)
        raise RuntimeError("Firmware did not acknowledge command")

    def run(self):
        csv_file = None
        try:
            metadata = json.loads((ROOT / "Build/interface.json").read_text(encoding="utf-8-sig"))
            self.address = metadata["mailbox_address"]
            self.diagnostics_address = metadata.get("diagnostics_address", 0)
            exe, scripts = tool_paths()
            # Choose a currently unused localhost port. Never attach to another session.
            with socket.socket() as allocator:
                allocator.bind(("127.0.0.1", 0))
                port = allocator.getsockname()[1]
            logs = ROOT / "logs"
            logs.mkdir(exist_ok=True)
            stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
            self.log_handle = (logs / f"openocd-{stamp}.txt").open("w", encoding="utf-8")
            args = [str(exe), "-s", str(scripts), "-f", "interface/stlink-dap.cfg",
                    "-c", "transport select dapdirect_swd",
                    "-c", f"adapter serial {self.serial}", "-f", "target/stm32f3x.cfg",
                    "-c", "adapter speed 1000", "-c", "bindto 127.0.0.1",
                    "-c", "gdb_port disabled", "-c", "telnet_port disabled",
                    "-c", f"tcl_port {port}", "-c", "init"]
            self.process = subprocess.Popen(args, stdout=self.log_handle, stderr=subprocess.STDOUT,
                                            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            deadline = time.monotonic() + 8
            while time.monotonic() < deadline and not self.quit.is_set():
                if self.process.poll() is not None:
                    raise RuntimeError(f"OpenOCD could not connect. See logs/openocd-{stamp}.txt")
                try:
                    self.link = TclConnection(port)
                    break
                except OSError:
                    time.sleep(0.1)
            if not self.link:
                raise RuntimeError("Timed out connecting to OpenOCD")
            chip = self.link.read(0xE0042000, 1)[0] & 0xFFF
            if chip != 0x446:
                raise RuntimeError(f"Not an F303xE target (device ID 0x{chip:03X})")
            first = self.status()
            time.sleep(0.06)
            second = self.status()
            if first["tick"] == second["tick"]:
                raise RuntimeError("Firmware not running; no automatic reset/resume")
            self.seq = second["ack"]
            self.hb = self.link.read(self.address + 64, 1)[0]
            self.heartbeat()
            peer_seen = peer_ready(second)
            if peer_seen:
                self.command(2)
            self.events.put(("connected", "F303 connected — awaiting live G431 CAN feedback; never auto-arm"))
            csv_file = (logs / f"telemetry-{stamp}.csv").open("w", newline="", encoding="utf-8")
            writer = None
            while not self.quit.is_set():
                # GUI liveness is required too: a frozen GUI cannot leave worker heartbeating forever.
                if time.monotonic() - getattr(self, "ui_alive", 0) > 0.7:
                    raise RuntimeError("Control window stopped responding; stopping outputs")
                self.heartbeat()
                try:
                    request = self.commands.get_nowait()
                except queue.Empty:
                    request = None
                if request:
                    self.command(*request)
                status = self.status()
                if peer_ready(status) and not peer_seen:
                    self.command(2)  # first link only sends Stop, never Arm/duty
                    peer_seen = True
                    status = self.status()
                self.events.put(("status", status))
                record = {"utc": dt.datetime.now(dt.timezone.utc).isoformat(), **status}
                if not writer:
                    writer = csv.DictWriter(csv_file, fieldnames=list(record))
                    writer.writeheader()
                writer.writerow(record)
                csv_file.flush()
                self.quit.wait(0.1)
        except Exception as exc:
            self.events.put(("error", str(exc)))
        finally:
            if self.link:
                try:
                    if self.address and self.link.read(self.address, 2) == [MAGIC, 1]:
                        self.command(2)
                except Exception:
                    pass  # target timeout/IWDG are fallback; never claim stop was confirmed
                self.link.close()
            if self.process:
                self.process.terminate()
                try:
                    self.process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    self.process.kill()
            if csv_file:
                csv_file.close()
            if self.log_handle:
                self.log_handle.close()
            self.events.put(("disconnected", "Disconnected. Check physical outputs; PC loss fallback nominally <1.2 s."))

class App:
    def __init__(self, root):
        self.root = root
        self.worker = None
        self.events, self.commands = queue.Queue(), queue.Queue()
        self.connected = False
        self.armed = False
        self.last_status = None
        self.key_active = None
        self.key_release_job = None
        self.keyboard_enabled = tk.BooleanVar(value=False)
        try:
            build = json.loads((ROOT / "Build/interface.json").read_text(encoding="utf-8-sig"))
        except (OSError, ValueError):
            build = {}
        self.can_only = bool(build.get('can_only', False))
        bitrate = build.get('can_bitrate', 1000000)
        root.title("CANDrive — F303 CAN to G431 PWM & encoder")
        root.geometry("820x840")
        root.minsize(780, 740)
        root.configure(bg="#eef2f6")
        style = ttk.Style()
        style.theme_use("clam")
        style.configure("TButton", padding=8)
        pane = ttk.Frame(root, padding=18)
        pane.pack(fill="both", expand=True)
        ttk.Label(pane, text="PWM + quadrature encoder", font=("Segoe UI", 19, "bold")).pack(anchor="w")
        ttk.Label(pane, text=f"PC → F303 ST-LINK → {bitrate/1000:g} kbit/s CAN → G431 (selected build)").pack(anchor="w", pady=(4, 12))
        warning = ("CAN-ONLY DIAGNOSTIC BUILD — PWM locked LOW; encoder processing disabled."
                   if self.can_only else
                   "SIGNAL TEST ONLY — keep motor power disconnected until driver truth table is verified.")
        ttk.Label(pane, text=warning, foreground="#a13218", wraplength=760).pack(anchor="w", pady=(0, 10))
        connection = ttk.Frame(pane)
        connection.pack(fill="x")
        ttk.Label(connection, text="F303 ST-LINK serial:").pack(side="left")
        self.serial = tk.StringVar(value="0669FF353542543351014933")
        ttk.Entry(connection, textvariable=self.serial, width=28).pack(side="left", padx=8)
        self.connect_button = ttk.Button(connection, text="Connect", command=self.connect)
        self.connect_button.pack(side="left")
        ttk.Button(connection, text="Disconnect", command=self.disconnect).pack(side="left", padx=8)
        self.message = tk.StringVar(value="Not connected — opening this window does not flash or enable PWM.")
        ttk.Label(pane, textvariable=self.message, wraplength=760, foreground="#214e75").pack(anchor="w", pady=10)
        controls = ttk.LabelFrame(pane, text="PWM outputs — active HIGH, nominal 0–3.3 V", padding=12)
        controls.pack(fill="x", pady=5)
        self.freq = tk.StringVar(value="1000")
        ttk.Label(controls, text="Frequency (Hz):").grid(row=0, column=0, sticky="w")
        ttk.Combobox(controls, textvariable=self.freq, values=(100, 500, 1000, 5000, 10000, 20000), width=12).grid(row=0, column=1, padx=10)
        self.freq_button = ttk.Button(controls, text="Set while stopped", command=self.set_freq)
        self.freq_button.grid(row=0, column=2)
        self.channel = tk.IntVar(value=1)
        ttk.Radiobutton(controls, text="PWM1: header 2 / PC7", variable=self.channel, value=1).grid(row=1, column=0, pady=12, sticky="w")
        ttk.Radiobutton(controls, text="PWM2: header 3 / PC6", variable=self.channel, value=2).grid(row=1, column=1, columnspan=2, sticky="w")
        self.duty = tk.StringVar(value="10")
        ttk.Label(controls, text="Duty (%) 0–100:").grid(row=2, column=0, sticky="w")
        ttk.Spinbox(controls, from_=0, to=100, increment=1, textvariable=self.duty, width=12).grid(row=2, column=1)
        self.apply_button = ttk.Button(controls, text="Apply selected PWM", command=self.apply)
        self.apply_button.grid(row=2, column=2)
        self.arm_button = ttk.Button(controls, text="Arm signal output (still 0%)", command=lambda: self.send(1))
        self.arm_button.grid(row=3, column=0, columnspan=2, pady=12, sticky="w")
        self.stop_button = tk.Button(controls, text="STOP / BOTH LOW", bg="#b52e31", fg="white", font=("Segoe UI", 11, "bold"), command=self.stop)
        self.stop_button.grid(row=3, column=2, padx=8)
        ttk.Label(controls, text="One channel only. Stop before switching. CAN loss: 0.5 s; PC loss: nominally <1.2 s.", wraplength=730).grid(row=4, column=0, columnspan=3, sticky="w")
        ttk.Checkbutton(controls, text="Enable hold-to-run arrows (arm manually first)",
                        variable=self.keyboard_enabled, command=self.keyboard_toggle).grid(row=5, column=0, columnspan=3, sticky="w", pady=(8, 0))
        keyboard_hint = ttk.Label(controls, text="Hold Up = PWM1; hold Down = PWM2. Release = zero duty.\nClick here before driving; arrows in edit fields only edit values. Escape = STOP/disarm.", wraplength=730)
        keyboard_hint.grid(row=6, column=0, columnspan=3, sticky="w")
        keyboard_hint.bind('<Button-1>', lambda event: root.focus_set())
        encoder = ttk.LabelFrame(pane, text="Encoder — x4 quadrature, A=PB7 / B=PB6", padding=12)
        encoder.pack(fill="x", pady=12)
        self.count = tk.StringVar(value="Count: —")
        self.speed = tk.StringVar(value="Counts/s: —")
        self.ab = tk.StringVar(value="A: —   B: —")
        ttk.Label(encoder, textvariable=self.count, font=("Consolas", 20)).grid(row=0, column=0, sticky="w")
        ttk.Label(encoder, textvariable=self.speed, font=("Consolas", 15)).grid(row=1, column=0, sticky="w", pady=8)
        ttk.Label(encoder, textvariable=self.ab, wraplength=400).grid(row=2, column=0, sticky="w")
        self.zero_button = ttk.Button(encoder, text="Zero count (stopped only)", command=lambda: self.send(4))
        self.zero_button.grid(row=0, column=1, padx=20)
        self.cpr = tk.StringVar(value="0")
        ttk.Label(encoder, text="x4 counts/rev (0=unknown):").grid(row=1, column=1)
        ttk.Entry(encoder, textvariable=self.cpr, width=14).grid(row=2, column=1)
        self.rpm = tk.StringVar(value="RPM: set counts/rev first")
        ttk.Label(encoder, textvariable=self.rpm).grid(row=3, column=0, sticky="w", pady=6)
        self.state = tk.StringVar(value="DISARMED | PWM1 0% | PWM2 0%")
        ttk.Label(pane, textvariable=self.state, font=("Consolas", 11, "bold")).pack(anchor="w")
        ttk.Label(pane, text="G431 ST-LINK is NOT required: use separate board power and a common CAN ground.\nEncoder header: 1=5 V, 2=A, 3=B, 4=GND. Count sign depends on wiring.\nNo PID/speed regulation. Logs are saved in the project’s logs folder.", wraplength=760).pack(anchor="w", pady=8)
        root.protocol("WM_DELETE_WINDOW", self.close)
        root.bind("<KeyPress-Up>", self.key_press)
        root.bind("<KeyPress-Down>", self.key_press)
        root.bind("<KeyRelease-Up>", self.key_release)
        root.bind("<KeyRelease-Down>", self.key_release)
        root.bind("<Escape>", lambda event: self.stop())
        root.bind("<FocusOut>", lambda event: root.after_idle(self.check_keyboard_focus))
        self.refresh_buttons()
        root.after(100, self.poll)

    def refresh_buttons(self):
        ready = not self.can_only and self.connected and self.last_status is not None and peer_ready(self.last_status)
        for widget in (self.arm_button, self.freq_button, self.zero_button):
            widget.configure(state="normal" if ready and not self.armed else "disabled")
        self.apply_button.configure(state="normal" if ready and self.armed else "disabled")
        self.stop_button.configure(state="normal" if self.connected else "disabled")

    def connect(self):
        if self.worker and self.worker.is_alive():
            return
        serial = self.serial.get().strip()
        if not serial.isalnum():
            messagebox.showerror("Serial", "Enter the ST-LINK serial number (letters/digits only).")
            return
        self.commands = queue.Queue()
        self.worker = Worker(serial, self.events, self.commands)
        self.worker.ui_alive = time.monotonic()
        self.message.set("Connecting... no automatic flashing, reset, or PWM enable.")
        self.connect_button.configure(state="disabled")
        self.worker.start()

    def send(self, op, ch=0, duty=0, hz=1000):
        if self.can_only and op != 2:
            self.message.set("CAN-only build: only STOP commands are permitted; no PWM/encoder test.")
            return
        if self.connected:
            self.commands.put((op, ch, duty, hz))

    def stop(self):
        self.cancel_key_release()
        self.key_active = None
        # Discard queued arm/duty commands; stop is next in the worker queue.
        while True:
            try:
                self.commands.get_nowait()
            except queue.Empty:
                break
        self.send(2)

    def cancel_key_release(self):
        if self.key_release_job is not None:
            self.root.after_cancel(self.key_release_job)
            self.key_release_job = None

    def keyboard_toggle(self):
        # Changing input mode never starts a motor and clears manual output.
        self.stop()

    def check_keyboard_focus(self):
        if self.root.focus_displayof() is None and self.keyboard_enabled.get():
            self.keyboard_enabled.set(False)
            self.stop()

    def key_press(self, event):
        if event.widget.winfo_class() in ('Entry', 'TEntry', 'Spinbox', 'TSpinbox', 'TCombobox'):
            return
        if not self.keyboard_enabled.get():
            return
        if self.key_active == event.keysym:
            self.cancel_key_release()  # Ignore OS auto-repeat, including synthetic release.
            return 'break'
        if self.key_active is not None:
            self.stop()  # Simultaneous opposite keys must never reverse immediately.
            self.keyboard_enabled.set(False)
            return 'break'
        if not (self.connected and self.armed and not self.can_only and
                self.last_status and peer_ready(self.last_status)):
            return 'break'
        if self.last_status['pwm1'] or self.last_status['pwm2']:
            self.message.set('Wait for confirmed zero duty before starting an arrow direction.')
            return 'break'
        try:
            duty = float(self.duty.get())
            if not 0 <= duty <= 100:
                raise ValueError('Duty must be 0–100%')
            ch = 1 if event.keysym == 'Up' else 2
            self.channel.set(ch)
            self.key_active = event.keysym
            self.send(3, ch, round(duty * 10))
        except ValueError as exc:
            self.message.set(str(exc))
        return 'break'

    def key_release(self, event):
        if self.key_active == event.keysym:
            self.cancel_key_release()
            self.key_release_job = self.root.after_idle(self.finish_key_release)
            return 'break'

    def finish_key_release(self):
        self.key_release_job = None
        key = self.key_active
        self.key_active = None
        if key is not None:
            # Retain manual arming, but remove any not-yet-issued duty request.
            while True:
                try:
                    self.commands.get_nowait()
                except queue.Empty:
                    break
            self.send(3, 1 if key == 'Up' else 2, 0)

    def set_freq(self):
        try:
            hz = int(self.freq.get())
            validate_command(5, hz=hz)
            self.send(5, 0, 0, hz)
        except ValueError as exc:
            messagebox.showerror("Frequency", str(exc))

    def apply(self):
        if self.keyboard_enabled.get():
            self.message.set('Disable arrow control before using manual Apply.')
            return
        try:
            duty = float(self.duty.get())
            if not 0 <= duty <= 100:
                raise ValueError("Duty must be 0–100%")
            ch = self.channel.get()
            if self.last_status and self.last_status[f"pwm{3-ch}"]:
                raise ValueError("Stop both outputs, then arm again before changing channels.")
            self.send(3, ch, round(duty * 10))
        except ValueError as exc:
            messagebox.showerror("PWM", str(exc))

    def disconnect(self):
        self.cancel_key_release()
        self.key_active = None
        self.keyboard_enabled.set(False)
        if self.worker:
            self.worker.quit.set()
        self.connected = self.armed = False
        self.refresh_buttons()

    def poll(self):
        if self.worker:
            self.worker.ui_alive = time.monotonic()
        try:
            while True:
                kind, payload = self.events.get_nowait()
                if kind == "connected":
                    self.connected = True
                    self.message.set(payload)
                elif kind == "error":
                    self.message.set("ERROR: " + payload)
                    self.connected = self.armed = False
                    self.cancel_key_release()
                    self.key_active = None
                    self.keyboard_enabled.set(False)
                elif kind == "disconnected":
                    self.connected = self.armed = False
                    self.connect_button.configure(state="normal")
                    if not self.message.get().startswith("ERROR"):
                        self.message.set(payload)
                    self.state.set("DISCONNECTED — outputs not confirmed; check physical signal")
                    self.count.set('Count: — (disconnected)')
                    self.speed.set('Counts/s: —'); self.ab.set('A/B: —   Timer raw: —')
                    self.rpm.set('RPM: — (no live data)')
                elif kind == "status":
                    s = self.last_status = payload
                    self.armed = bool(s["armed"])
                    if not peer_ready(s):
                        self.cancel_key_release()
                        self.key_active = None
                        self.keyboard_enabled.set(False)
                    count_text, speed_text, ab_text = encoder_display(s)
                    self.count.set(count_text); self.speed.set(speed_text); self.ab.set(ab_text)
                    if self.can_only:
                        self.count.set("Encoder: disabled for CAN isolation")
                        self.speed.set("Counts/s: —"); self.ab.set("A/B: not sampled")
                    fault = FAULTS.get(s["fault"], str(s["fault"]))
                    prefix = status_prefix(s)
                    self.state.set(f"{prefix} | PWM1 {s['pwm1']/10:g}% | PWM2 {s['pwm2']/10:g}% | {s['hz']} Hz | fault: {fault}")
                    if 'bridge_rx_frames' in s:
                        age = f"{s['bridge_telemetry_age_ms']} ms" if s['bridge_remote_valid'] else 'never received'
                        self.message.set(f"CAN RX {s['bridge_rx_frames']:,}; complete snapshots {s['bridge_complete_snapshots']:,}; "
                                         f"age {age}; max loop {s['bridge_max_loop_ms']} ms; "
                                         f"FIFO/queue overflows {s['bridge_fifo_overruns']}/{s['bridge_queue_overruns']}; "
                                         f"startup events {s['bridge_startup_controller_events']}")
                    try:
                        cpr = float(self.cpr.get())
                        self.rpm.set(('RPM: — (no live data)' if not remote_fresh(s) else
                                      f"RPM: {s['cps']*60/cpr:.2f}" if cpr > 0 else "RPM: set counts/rev first"))
                    except ValueError:
                        self.rpm.set("RPM: invalid counts/rev")
                    if self.can_only:
                        self.rpm.set("RPM: disabled for CAN isolation")
                self.refresh_buttons()
        except queue.Empty:
            pass
        self.root.after(100, self.poll)

    def close(self):
        self.disconnect()
        self.message.set("Closing — requesting both outputs low and releasing ST-LINK...")
        self.wait_close()

    def wait_close(self):
        if self.worker and self.worker.is_alive():
            self.root.after(100, self.wait_close)
        else:
            self.root.destroy()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--smoke-test", action="store_true", help="Render/check widgets then exit; no hardware")
    args = parser.parse_args()
    root = tk.Tk()
    app = App(root)
    if args.smoke_test:
        root.update()
        assert not app.connected and not app.armed
        assert str(app.apply_button["state"]) == "disabled"
        assert str(app.arm_button["state"]) == "disabled"
        root.after(500, app.close)
    root.mainloop()

if __name__ == "__main__":
    main()
