param([string]$Port = '', [int]$VescId = 1, [int]$VescId2 = 2, [int]$Erpm = 1400,
      [switch]$VerifyOnly, [string]$PreviewPath = '',
      [switch]$AutoConnect, [switch]$ArmOnReady, [string]$StatePath = '')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class MotorKeys {
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int key);
    public static bool Down(int key) { return (GetAsyncKeyState(key) & 0x8000) != 0; }
}
'@

$script:Serial = $null
$script:Armed = $false
$script:PendingArm = $false
$script:LastTelemetry = [DateTime]::MinValue
$script:InputBuffer = ''
$script:Telemetry = @{}
$script:LastError = ''
$script:StartupArmWaiting = $false
if ($ArmOnReady) { throw 'Two-motor setup requires clicking Arm after both VESCs are configured.' }
$script:StartupArmDeadline = [DateTime]::UtcNow.AddSeconds(12)
$script:LastStateWrite = [DateTime]::MinValue

[Windows.Forms.Application]::EnableVisualStyles()
$form = New-Object Windows.Forms.Form
$form.Text = 'Two motors - G474 CAN controller'
$form.ClientSize = New-Object Drawing.Size(680,430)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object Drawing.Font('Segoe UI',11)
$form.KeyPreview = $true
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false

function Add-Label([string]$Text, [int]$X, [int]$Y, [int]$Width, [int]$Height) {
    $label = New-Object Windows.Forms.Label
    $label.Text = $Text; $label.SetBounds($X,$Y,$Width,$Height)
    $form.Controls.Add($label)
    return $label
}
$null = Add-Label 'USB serial port' 20 20 160 25
$ports = New-Object Windows.Forms.ComboBox
$ports.DropDownStyle = 'DropDownList'; $ports.SetBounds(180,17,125,30)
foreach ($name in @([IO.Ports.SerialPort]::GetPortNames() | Sort-Object)) { $null = $ports.Items.Add($name) }
if ($Port) {
    if ($ports.Items.Contains($Port)) { $ports.SelectedItem = $Port }
} elseif ($ports.Items.Count -gt 0) { $ports.SelectedIndex = 0 }
$form.Controls.Add($ports)

$connect = New-Object Windows.Forms.Button
$connect.Text = 'Connect'; $connect.SetBounds(325,16,140,32); $form.Controls.Add($connect)
$refresh = New-Object Windows.Forms.Button
$refresh.Text = 'Refresh'; $refresh.SetBounds(485,16,140,32); $form.Controls.Add($refresh)
$null = Add-Label 'VESC 1 ID' 20 65 160 25
$id = New-Object Windows.Forms.NumericUpDown
$id.Minimum = 0; $id.Maximum = 253; $id.Value = [Math]::Min(253,[Math]::Max(0,$VescId))
$id.SetBounds(180,62,125,30); $form.Controls.Add($id)
$null = Add-Label 'VESC 2 ID' 350 65 120 25
$id2 = New-Object Windows.Forms.NumericUpDown
$id2.Minimum = 0; $id2.Maximum = 253; $id2.Value = [Math]::Min(253,[Math]::Max(0,$VescId2))
$id2.SetBounds(490,62,125,30); $form.Controls.Add($id2)
$null = Add-Label 'Speed (electrical RPM)' 20 110 200 25
$speed = New-Object Windows.Forms.NumericUpDown
$speed.Minimum = 700; $speed.Maximum = 3500; $speed.Increment = 350
$speed.Value = [Math]::Min(3500,[Math]::Max(700,$Erpm)); $speed.SetBounds(230,107,125,30)
$form.Controls.Add($speed)
$null = Add-Label '1400 eRPM = 200 shaft RPM for a 14-pole motor.' 375 111 285 48

$arm = New-Object Windows.Forms.Button
$arm.Text = 'Arm'; $arm.SetBounds(20,170,200,42); $form.Controls.Add($arm)
$stop = New-Object Windows.Forms.Button
$stop.Text = 'STOP / Disarm'; $stop.SetBounds(240,170,385,42)
$stop.BackColor = [Drawing.Color]::MistyRose; $form.Controls.Add($stop)
$null = Add-Label "Hold UP = both forward | Hold DOWN = both reverse`r`nRelease = torque off / coast | SPACE or ESC = disarm`r`nChanging window or losing the connection also disarms." 20 230 630 76
$status = Add-Label 'Disconnected.' 20 315 630 100
$status.Font = New-Object Drawing.Font('Consolas',10)
if ($Port -and -not $ports.Items.Contains($Port)) {
    $script:LastError = "Nucleo $Port is missing. Connect ST-LINK USB, then click Refresh."
    $status.Text = $script:LastError
}

function Send-Command([string]$Command) {
    if ($script:Serial -and $script:Serial.IsOpen) { $script:Serial.Write($Command + "`n") }
}
function Set-Disarmed([bool]$Send = $true) {
    $script:Armed = $false; $script:PendingArm = $false
    if ($Send) { $script:StartupArmWaiting = $false }
    $speed.Enabled = $true
    if ($Send) { try { Send-Command 'D' } catch { $script:LastError = $_.Exception.Message } }
}
function Disconnect-Port {
    Set-Disarmed
    if ($script:Serial) { $script:Serial.Dispose(); $script:Serial = $null }
    $connect.Text = 'Connect'; $ports.Enabled = $true; $id.Enabled = $true; $id2.Enabled = $true
    $script:LastTelemetry = [DateTime]::MinValue; $script:Telemetry = @{}
}
function Process-Line([string]$Line) {
    if ($Line.StartsWith('T ')) {
        $values = @{}
        foreach ($piece in $Line.Substring(2).Split(' ')) {
            $parts = $piece.Split('=')
            if ($parts.Length -eq 2) { $values[$parts[0]] = $parts[1] }
        }
        if ($values.ContainsKey('armed') -and $values.ContainsKey('link1') -and $values.ContainsKey('link2')) {
            $script:Telemetry = $values; $script:LastTelemetry = [DateTime]::UtcNow
            if ($values['armed'] -eq '0' -and -not $script:PendingArm) { Set-Disarmed $false }
        }
    } elseif ($Line -eq 'OK ARMED') {
        $script:Armed = $true; $script:PendingArm = $false; $speed.Enabled = $false
        $script:LastError = ''
    } elseif ($Line.StartsWith('ERR ')) {
        $script:StartupArmWaiting = $false
        Set-Disarmed $false; $script:LastError = $Line
    } elseif ($Line.StartsWith('G474_DUAL_VESC_CAN')) {
        $script:StartupArmWaiting = $false
        Set-Disarmed $false; $script:LastError = 'Board restarted. Arm again after feedback returns.'
    }
}

$refresh.Add_Click({
    if ($script:Serial) { return }
    $ports.Items.Clear()
    foreach ($name in [IO.Ports.SerialPort]::GetPortNames()) { $null = $ports.Items.Add($name) }
    if ($Port) {
        if ($ports.Items.Contains($Port)) { $ports.SelectedItem = $Port; $script:LastError = '' }
    } elseif ($ports.Items.Count) { $ports.SelectedIndex = 0 }
})
$connect.Add_Click({
    if ($script:Serial) { Disconnect-Port; return }
    if ($id.Value -eq $id2.Value) { $script:LastError = 'Each VESC needs a different controller ID.'; return }
    if (-not $ports.SelectedItem) { $status.Text = 'Select the Nucleo serial port.'; return }
    try {
        $script:Serial = New-Object IO.Ports.SerialPort([string]$ports.SelectedItem,115200,[IO.Ports.Parity]::None,8,[IO.Ports.StopBits]::One)
        $script:Serial.ReadTimeout = 50; $script:Serial.WriteTimeout = 100
        $script:Serial.DtrEnable = $false; $script:Serial.RtsEnable = $false
        $script:Serial.Open(); $script:Serial.DiscardInBuffer()
        $script:InputBuffer = ''; $script:LastError = ''
        Send-Command 'D'; Send-Command ('I ' + [int]$id.Value + ' ' + [int]$id2.Value); Send-Command '?'
        $connect.Text = 'Disconnect'; $ports.Enabled = $false; $id.Enabled = $false; $id2.Enabled = $false
    } catch {
        $script:LastError = $_.Exception.Message
        Disconnect-Port; $status.Text = $script:LastError
    }
})
$arm.Add_Click({
    $script:StartupArmWaiting = $false
    if (-not $script:Serial) { return }
    if ($script:Armed -or $script:PendingArm) { Set-Disarmed; return }
    if ([MotorKeys]::Down(0x26) -or [MotorKeys]::Down(0x28)) {
        $script:LastError = 'Release the arrow keys before arming.'; return
    }
    if (([DateTime]::UtcNow - $script:LastTelemetry).TotalMilliseconds -gt 500 -or
        ($script:Telemetry['link1'] -ne '1' -or $script:Telemetry['link2'] -ne '1')) {
        $script:LastError = 'Need feedback from both VESCs. Check ID, 250 kbit/s and CAN status messages.'; return
    }
    try { Send-Command 'A'; $script:PendingArm = $true } catch { Disconnect-Port }
})
$stop.Add_Click({ Set-Disarmed })
$form.Add_Deactivate({ Set-Disarmed })
$form.Add_FormClosing({ Disconnect-Port })
$form.Add_KeyDown({
    if ($_.KeyCode -in @([Windows.Forms.Keys]::Up,[Windows.Forms.Keys]::Down,
                        [Windows.Forms.Keys]::Space,[Windows.Forms.Keys]::Escape)) {
        $_.SuppressKeyPress = $true; $_.Handled = $true
        if ($_.KeyCode -in @([Windows.Forms.Keys]::Space,[Windows.Forms.Keys]::Escape)) { Set-Disarmed }
    }
})

$timer = New-Object Windows.Forms.Timer
$timer.Interval = 50
$timer.Add_Tick({
    try {
        if ($script:Serial -and $script:Serial.IsOpen) {
            $script:InputBuffer += $script:Serial.ReadExisting()
            if ($script:InputBuffer.Length -gt 8192) { throw 'Unexpected serial data. Disconnected.' }
            while (($newline = $script:InputBuffer.IndexOf("`n")) -ge 0) {
                $text = $script:InputBuffer.Substring(0,$newline).TrimEnd("`r")
                $script:InputBuffer = $script:InputBuffer.Substring($newline + 1)
                Process-Line $text
            }
            $foreground = [Windows.Forms.Form]::ActiveForm -eq $form
            if (($script:Armed -or $script:PendingArm) -and
                (-not $foreground -or ([DateTime]::UtcNow - $script:LastTelemetry).TotalMilliseconds -gt 500)) { Set-Disarmed }
            if ($foreground -and ([MotorKeys]::Down(0x20) -or [MotorKeys]::Down(0x1b))) { Set-Disarmed }
            # One-time startup arming is only enabled by an explicit launch option.
            # It never rearms after a stop, fault, focus change or restart.
            if ($script:StartupArmWaiting) {
                if ([DateTime]::UtcNow -gt $script:StartupArmDeadline) {
                    $script:StartupArmWaiting = $false
                    $script:LastError = 'Startup arm expired. Click Arm when ready.'
                } elseif ($foreground -and
                    ([DateTime]::UtcNow - $script:LastTelemetry).TotalMilliseconds -le 500 -and
                    $script:Telemetry['link1'] -eq '1' -and $script:Telemetry['link2'] -eq '1' -and
                    [Math]::Abs([long]$script:Telemetry['erpm1']) -le 350 -and
                    [Math]::Abs([long]$script:Telemetry['erpm2']) -le 350 -and
                    -not [MotorKeys]::Down(0x26) -and -not [MotorKeys]::Down(0x28) -and
                    -not [MotorKeys]::Down(0x20) -and -not [MotorKeys]::Down(0x1b)) {
                    $arm.PerformClick()
                }
            }
            if ($script:Armed -or $script:PendingArm) {
                $target = 0
                $up = [MotorKeys]::Down(0x26); $down = [MotorKeys]::Down(0x28)
                if ($script:Armed -and $up -and -not $down) { $target = [int]$speed.Value }
                if ($script:Armed -and $down -and -not $up) { $target = -[int]$speed.Value }
                Send-Command ('R ' + $target)
            }
            $t = $script:Telemetry
            $state = if ($script:Armed) { 'ARMED' } else { 'DISARMED' }
            $status.Text = "$state | Last seen ID=$($t['seen'])`r`nVESC $($t['id1']): link=$($t['link1']) speed=$($t['erpm1']) eRPM RX=$($t['rx1'])`r`nVESC $($t['id2']): link=$($t['link2']) speed=$($t['erpm2']) eRPM RX=$($t['rx2'])`r`n$script:LastError"
            $arm.Text = if ($script:Armed) { 'Disarm' } elseif ($script:PendingArm) { 'Arming...' } else { 'Arm' }
        } else { $status.Text = "Disconnected. $script:LastError" }
        if ($StatePath -and ([DateTime]::UtcNow - $script:LastStateWrite).TotalMilliseconds -ge 200) {
            $snapshot = @{
                updated_utc = [DateTime]::UtcNow.ToString('o')
                connected = [bool]($script:Serial -and $script:Serial.IsOpen)
                armed = $script:Armed; pending_arm = $script:PendingArm
                startup_arm_waiting = $script:StartupArmWaiting
                foreground = ([Windows.Forms.Form]::ActiveForm -eq $form)
                telemetry_fresh = (([DateTime]::UtcNow - $script:LastTelemetry).TotalMilliseconds -le 500)
                telemetry = $script:Telemetry; error = $script:LastError
            } | ConvertTo-Json -Depth 4
            [IO.File]::WriteAllText($StatePath, $snapshot)
            $script:LastStateWrite = [DateTime]::UtcNow
        }
    } catch {
        $script:LastError = $_.Exception.Message
        Disconnect-Port
        $status.Text = $script:LastError
    }
})

if ($VerifyOnly) {
    Process-Line 'OK ARMED'
    if (-not $script:Armed -or $speed.Enabled) { throw 'ARM response handling failed.' }
    Process-Line 'T ms=100 armed=0 id1=1 id2=2 link1=1 link2=0 erpm1=0 erpm2=0 out1=0 out2=0 rx1=0 rx2=0 seen=255'
    if ($script:Armed -or -not $speed.Enabled) { throw 'Firmware disarm handling failed.' }
    Process-Line 'OK ARMED'
    Process-Line 'ERR DRIVE DISARMED_OR_LINK_STALE'
    if ($script:Armed) { throw 'Error handling failed.' }
    Process-Line 'OK ARMED'
    Process-Line 'G474_DUAL_VESC_CAN v2 DISARMED'
    if ($script:Armed) { throw 'Restart handling failed.' }
    $script:LastError = ''; $status.Text = 'Disconnected. Select the Nucleo USB serial port.'
    if ($PreviewPath) {
        $form.Opacity = 0
        $form.Show()
        [Windows.Forms.Application]::DoEvents()
        $bitmap = New-Object Drawing.Bitmap($form.Width,$form.Height)
        $form.DrawToBitmap($bitmap, (New-Object Drawing.Rectangle(0,0,$form.Width,$form.Height)))
        $bitmap.Save($PreviewPath, [Drawing.Imaging.ImageFormat]::Png)
        $bitmap.Dispose()
        $form.Hide()
    }
    $timer.Dispose(); $form.Dispose()
    Write-Output 'Keyboard controller checks passed: arm, disarm, error and board restart.'
    exit 0
}
$form.Add_Shown({
    if ($AutoConnect) { $connect.PerformClick() }
    if ($ArmOnReady) { $form.Activate() }
})
$timer.Start()
try { [Windows.Forms.Application]::Run($form) }
finally { $timer.Dispose(); Disconnect-Port; $form.Dispose() }
