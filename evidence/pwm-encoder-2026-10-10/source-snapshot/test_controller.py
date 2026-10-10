"""Offline protocol/GUI tests. None of these access real ST-LINK or motors."""
import unittest
from unittest.mock import Mock
import controller as c

class ProtocolTests(unittest.TestCase):
    def words(self):
        return [c.MAGIC, 1, 100, 0, 0, 1000, 0, 0, 0, 0, 0, 0, 3, 2, 0, 4]

    def test_decode_signed_position(self):
        w = self.words()
        w[9], w[10], w[11] = 0xFFFFFFFE, 0xFFFFFFFF, 0xFFFFFF9C
        s = c.decode(w)
        self.assertEqual((s['count'], s['cps']), (-2, -100))

    def test_signed_positive_large_position(self):
        w = self.words()
        w[9], w[10] = 7, 1
        self.assertEqual(c.decode(w)['count'], 4294967303)

    def test_wrong_firmware_rejected(self):
        w = self.words()
        for index in (0, 1):
            bad = w.copy(); bad[index] = 0
            with self.assertRaises(RuntimeError): c.decode(bad)
        with self.assertRaises(RuntimeError): c.decode(w[:-1])

    def test_encoder_diagnostics_backward_compatible(self):
        w = self.words()
        self.assertFalse(c.decode(w)['encoder_diagnostics'])
        w[12] = 0x80 | 0x40 | (15 << 2) | 2 | (123 << 8) | (4095 << 20)
        s = c.decode(w)
        self.assertEqual((s['a'], s['b']), (0, 1))
        self.assertTrue(s['encoder_config_ok'])
        self.assertEqual((s['encoder_a_changes'], s['encoder_b_changes']), (123, 4095))
        self.assertEqual(s['encoder_states_seen'], 15)

    def test_stale_encoder_never_displayed_as_zero(self):
        s = c.decode(self.words()); s.update(self.diagnostics())
        s['bridge_remote_valid'] = 0
        for text in c.encoder_display(s): self.assertIn('—', text)
        s['bridge_remote_valid'] = 1; s['bridge_telemetry_age_ms'] = 250
        self.assertIn('no live data', c.encoder_display(s)[0])
        s['bridge_telemetry_age_ms'] = 20
        self.assertEqual(c.encoder_display(s)[0], 'Count: 0')

    def test_command_limits(self):
        for duty in (0, 1, 500, 1000): c.validate_command(3, 1, duty)
        for duty in (-1, 1001):
            with self.assertRaises(ValueError): c.validate_command(3, 1, duty)
        for ch in (0, 3):
            with self.assertRaises(ValueError): c.validate_command(3, ch, 100)
        for hz in (100, 1000, 20000): c.validate_command(5, hz=hz)
        for hz in (99, 20001):
            with self.assertRaises(ValueError): c.validate_command(5, hz=hz)

    def worker(self):
        import queue
        w = c.Worker('fake', queue.Queue(), queue.Queue())
        w.address = 0x20000004
        w.link = Mock()
        return w

    def test_commit_written_last(self):
        w = self.worker(); w.link.read.return_value = [1, 0]
        w.command(3, 2, 500)
        self.assertEqual(w.link.write.call_args_list[0].args, (w.address+72, [3, 2, 500, 1000]))
        self.assertEqual(w.link.write.call_args_list[1].args, (w.address+68, [1]))

    def test_rejection_surfaced(self):
        w = self.worker(); w.link.read.return_value = [1, 2]
        with self.assertRaisesRegex(RuntimeError, 'rejected'): w.command(3, 1, 500)

    def test_seqlock_retry(self):
        w = self.worker(); torn = self.words(); torn[15] = 3
        stable = self.words()
        w.link.snapshot.side_effect = [None, stable]
        self.assertEqual(w.status()['snapshot'], 4)

    def test_diagnostics_collision_keeps_coherent_mailbox(self):
        w = self.worker(); w.diagnostics_address = 0x20000100
        diag = [0] * len(c.DIAG_FIELDS); diag[:3] = [0x43414E44, 2, 2]
        w.link.snapshot.side_effect = [self.words()] + [None] * 8 + [diag]
        status = w.status()
        self.assertEqual(status['snapshot'], 4)
        self.assertEqual(status['bridge_version'], 2)
        calls = w.link.snapshot.call_args_list
        self.assertEqual(sum(call.args[0] == w.address for call in calls), 1)
        self.assertEqual(sum(call.args[0] == w.diagnostics_address for call in calls), 9)

    def test_persistent_snapshot_collision_still_fails(self):
        w = self.worker(); w.link.snapshot.return_value = None
        with self.assertRaisesRegex(RuntimeError, 'No coherent snapshot'):
            w.status()
        self.assertEqual(w.link.snapshot.call_count, 16)

    def test_snapshot_rejects_update_during_block(self):
        link = c.TclConnection.__new__(c.TclConnection)
        stable = self.words()
        link.call = Mock(return_value='OK 2 ' + ' '.join(map(str, stable)) + ' 4')
        self.assertIsNone(link.snapshot(0x20000000, 16, 15))
        link.call.return_value = 'OK 4 ' + ' '.join(map(str, stable)) + ' 4'
        self.assertEqual(link.snapshot(0x20000000, 16, 15), stable)
        self.assertEqual(link.call.call_args.args[0].count('read_memory'), 3)

    def diagnostics(self):
        v = [0] * len(c.DIAG_FIELDS); v[:3] = [0x43414E44, 2, 2]
        v[18], v[19], v[21] = 20, 1, 1
        return c.decode_diagnostics(v)

    def test_fresh_telemetry_with_master_fault_not_labelled_stale(self):
        s = c.decode(self.words()); s.update(self.diagnostics()); s['fault'] = 20
        s['bridge_fault_bits'] = 16
        self.assertEqual(c.status_prefix(s), 'LIVE TELEMETRY / FAULT LATCHED')
        self.assertFalse(c.peer_ready(s))

    def test_stale_diagnostics_disable_controls_even_with_fault_zero(self):
        s = c.decode(self.words()); s.update(self.diagnostics())
        self.assertTrue(c.peer_ready(s))
        s['bridge_telemetry_age_ms'] = 250
        self.assertFalse(c.peer_ready(s))
        self.assertEqual(c.status_prefix(s), 'REMOTE STALE (last known)')

    def test_diagnostic_signature_guard(self):
        with self.assertRaises(RuntimeError): c.decode_diagnostics([0] * len(c.DIAG_FIELDS))

    def test_startup_lock_and_warning(self):
        s = c.decode(self.words()); s.update(self.diagnostics())
        s['bridge_controller_ready'] = 0; s['fault'] = 25
        self.assertFalse(c.peer_ready(s))
        self.assertEqual(c.status_prefix(s), 'LIVE TELEMETRY / STARTUP LOCKED')
        s['bridge_controller_ready'] = 1; s['fault'] = 0
        s['bridge_startup_controller_events'] = 1
        self.assertTrue(c.peer_ready(s))  # historical startup warning isn't silently erased

    def test_heartbeat_wrap(self):
        w = self.worker(); w.hb = 0xFFFFFFFF
        w.heartbeat()
        self.assertEqual(w.hb, 1)
        w.link.write.assert_called_once_with(w.address+64, [1])

    def test_tcl_fragmented_reply(self):
        link = c.TclConnection.__new__(c.TclConnection)
        link.sock = Mock(); link.pending = b''
        link.sock.recv.side_effect = [b'OK 0x', b'10 20\x1a']
        self.assertEqual(link.read(0x20000004, 2), [16, 20])
        self.assertTrue(link.sock.sendall.call_args.args[0].endswith(b'\x1a'))

    def test_write_failure_not_hidden(self):
        link = c.TclConnection.__new__(c.TclConnection)
        link.sock = Mock(); link.pending = b'Error: target not examined\x1a'
        with self.assertRaises(RuntimeError): link.write(0x20000004, [1])

class KeyboardTests(unittest.TestCase):
    def app(self):
        import queue
        a = c.App.__new__(c.App)
        a.root = Mock(); a.key_active = None; a.key_release_job = None
        a.keyboard_enabled = Mock(); a.keyboard_enabled.get.return_value = True
        a.connected = a.armed = True; a.can_only = False
        a.last_status = {'fault': 0, 'pwm1': 0, 'pwm2': 0}
        a.duty = Mock(); a.duty.get.return_value = '5'
        a.channel = Mock(); a.message = Mock(); a.send = Mock()
        a.commands = queue.Queue()
        return a

    def event(self, key='Up', widget_class='TLabel'):
        e = Mock(); e.keysym = key; e.widget.winfo_class.return_value = widget_class
        return e

    def test_keys_select_channels_with_tuned_duty(self):
        for key, channel in [('Up', 1), ('Down', 2)]:
            a = self.app(); a.key_press(self.event(key))
            a.send.assert_called_once_with(3, channel, 50)

    def test_not_armed_disabled_stale_or_editing_never_runs(self):
        for mode in ('disarmed', 'disabled', 'stale', 'edit', 'can_only'):
            a = self.app(); e = self.event()
            if mode == 'disarmed': a.armed = False
            if mode == 'disabled': a.keyboard_enabled.get.return_value = False
            if mode == 'stale': a.last_status['fault'] = 4
            if mode == 'edit': e.widget.winfo_class.return_value = 'TSpinbox'
            if mode == 'can_only': a.can_only = True
            a.key_press(e); a.send.assert_not_called()

    def test_repeat_does_not_queue_more_pwm(self):
        a = self.app(); a.key_press(self.event()); a.key_release_job = 'repeat'
        a.key_press(self.event()); self.assertEqual(a.send.call_count, 1)
        a.root.after_cancel.assert_called_once_with('repeat')

    def test_release_clears_pending_duty_and_sends_zero(self):
        a = self.app(); a.key_active = 'Down'; a.commands.put((3, 2, 50, 1000))
        a.finish_key_release(); a.send.assert_called_once_with(3, 2, 0)
        self.assertTrue(a.commands.empty()); self.assertIsNone(a.key_active)

    def test_opposite_keys_stop_and_disable(self):
        a = self.app(); a.key_active = 'Up'; a.key_press(self.event('Down'))
        a.send.assert_called_once_with(2); a.keyboard_enabled.set.assert_called_with(False)

    def test_focus_loss_stops_and_disables(self):
        a = self.app(); a.root.focus_displayof.return_value = None
        a.check_keyboard_focus(); a.send.assert_called_once_with(2)
        a.keyboard_enabled.set.assert_called_with(False)

    def test_reversal_waits_for_confirmed_zero(self):
        a = self.app(); a.last_status['pwm1'] = 50
        a.key_press(self.event('Down')); a.send.assert_not_called()

if __name__ == '__main__': unittest.main(verbosity=2)
