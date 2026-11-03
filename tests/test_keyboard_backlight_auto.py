"""Regressions for disconnected evdev devices and sysfs LED notifications."""

import errno
import importlib.machinery
import importlib.util
import os
from pathlib import Path
import select
import tempfile
import unittest
from unittest.mock import Mock, patch


SOURCE = Path(__file__).resolve().parents[1] / "keyboard-backlight-auto/kbd-backlight-auto"
loader = importlib.machinery.SourceFileLoader("kbd_backlight_auto", str(SOURCE))
spec = importlib.util.spec_from_loader(loader.name, loader)
kbd = importlib.util.module_from_spec(spec)
loader.exec_module(kbd)


class EventMonitorTests(unittest.TestCase):
    def setUp(self):
        self.monitor = kbd.EventMonitor("/nonexistent-led", True)
        self.log = patch.object(kbd, "log").start()
        self.writers = []
        self.addCleanup(patch.stopall)
        self.addCleanup(self.cleanup)

    def cleanup(self):
        self.monitor.close()
        for fd in self.writers:
            os.close(fd)

    def pipe(self, kind="key"):
        reader, writer = os.pipe2(os.O_NONBLOCK)
        self.monitor.fds[reader] = ("/dev/input/test", kind)
        self.monitor.poller.register(reader, select.POLLIN)
        self.writers.append(writer)
        return reader, writer

    def test_real_disconnect_removes_fd_and_next_poll_sleeps(self):
        reader, writer = self.pipe()
        os.close(writer)
        self.writers.remove(writer)
        self.assertEqual(self.monitor.events(0), [])
        self.assertNotIn(reader, self.monitor.fds)
        with self.assertRaises(OSError):
            os.fstat(reader)
        # A dead evdev fd used to wake this poll immediately forever.
        import time
        start = time.monotonic()
        self.monitor.events(0.02)
        self.assertGreaterEqual(time.monotonic() - start, 0.015)

    def test_enodev_removes_fd_even_without_hangup_mask(self):
        reader, _writer = self.pipe()
        self.monitor.poller = Mock()
        self.monitor.poller.poll.return_value = [(reader, select.POLLIN)]
        with patch.object(kbd.os, "read", side_effect=OSError(errno.ENODEV, "gone")):
            self.assertEqual(self.monitor.events(0), [])
        self.assertNotIn(reader, self.monitor.fds)

    def test_pollnval_on_already_closed_fd_does_not_crash(self):
        reader, _writer = self.pipe()
        os.close(reader)
        self.assertEqual(self.monitor.events(0), [])
        self.assertNotIn(reader, self.monitor.fds)

    def test_eof_removes_fd(self):
        reader, _writer = self.pipe()
        self.monitor.poller = Mock()
        self.monitor.poller.poll.return_value = [(reader, select.POLLIN)]
        with patch.object(kbd.os, "read", return_value=b""):
            self.monitor.events(0)
        self.assertNotIn(reader, self.monitor.fds)

    def test_eagain_keeps_live_device(self):
        reader, _writer = self.pipe()
        self.monitor.poller = Mock()
        self.monitor.poller.poll.return_value = [(reader, select.POLLIN)]
        with patch.object(kbd.os, "read", side_effect=BlockingIOError(errno.EAGAIN, "retry")):
            self.monitor.events(0)
        self.assertIn(reader, self.monitor.fds)

    def test_sysfs_pollerr_with_pollpri_is_a_valid_notification(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "brightness_hw_changed"
            path.write_text("3\n")
            self.monitor.watch(str(path), "hardware")
            reader = next(iter(self.monitor.fds))
            self.monitor.poller = Mock()
            self.monitor.poller.poll.return_value = [
                (reader, select.POLLPRI | select.POLLERR)]
            self.assertEqual(self.monitor.events(0), [("hardware", 3)])
            self.assertIn(reader, self.monitor.fds)

    def test_unreadable_sysfs_notification_is_disarmed(self):
        reader, _writer = self.pipe("hardware")
        self.monitor.poller = Mock()
        self.monitor.poller.poll.return_value = [(reader, select.POLLERR)]
        with patch.object(kbd.os, "lseek"), patch.object(
                kbd.os, "read", side_effect=OSError(errno.ENODATA, "no data")):
            self.assertEqual(self.monitor.events(0), [])
        self.assertNotIn(reader, self.monitor.fds)

    def test_rescan_is_bounded_and_reopens_disconnected_path(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "event"
            path.touch()
            with patch.object(kbd, "find_illum_key_devices", return_value=[{"event": str(path)}]), \
                    patch.object(kbd, "find_lid_device", return_value=None), \
                    patch.object(kbd.time, "monotonic", return_value=10.0) as clock:
                self.monitor.scan()
                reader = next(iter(self.monitor.fds))
                self.monitor.drop(reader)
                self.monitor.scan()
                self.assertEqual(self.monitor.fds, {})
                clock.return_value = 15.0
                self.monitor.scan()
                self.assertEqual(len(self.monitor.fds), 1)

    def test_lid_and_fn_key_events_survive_batch_reads(self):
        lid, lid_writer = self.pipe("lid")
        key, key_writer = self.pipe("key")
        os.write(lid_writer, kbd.INPUT_EVENT.pack(0, 0, kbd.EV_SW, kbd.SW_LID, 1))
        os.write(key_writer,
                 kbd.INPUT_EVENT.pack(0, 0, kbd.EV_KEY, kbd.KEY_KBDILLUMUP, 1) +
                 kbd.INPUT_EVENT.pack(0, 0, kbd.EV_KEY, kbd.KEY_KBDILLUMUP, 0))
        self.assertCountEqual(self.monitor.events(0), [("lid", True), ("key", 1)])
        self.assertTrue(self.monitor.has_lid())
        self.monitor.drop(lid)
        self.assertFalse(self.monitor.has_lid())

    def test_poll_rounds_up_fractional_millisecond(self):
        self.monitor.poller = Mock()
        self.monitor.poller.poll.return_value = []
        self.monitor.events(0.0001)
        self.monitor.poller.poll.assert_called_once_with(1)


class SensorDiscoveryTests(unittest.TestCase):
    def setUp(self):
        self.log = patch.object(kbd, "log").start()
        patch.object(kbd, "Backlight").start()
        patch.object(kbd, "read_proc_lid_state", return_value=None).start()
        self.addCleanup(patch.stopall)
        self.root = tempfile.TemporaryDirectory()
        self.addCleanup(self.root.cleanup)

    def sensor(self, name, lux):
        path = os.path.join(self.root.name, name)
        os.makedirs(path, exist_ok=True)
        with open(os.path.join(path, "in_illuminance_raw"), "w") as fh:
            fh.write("%d\n" % lux)
        return kbd.AmbientSensor(path)

    def controller(self, sensors):
        find = patch.object(kbd.AmbientSensor, "find", side_effect=sensors).start()
        controller = kbd.Controller(dict(kbd.DEFAULTS), dry_run=True)
        return controller, find

    def test_missing_sensor_at_start_waits_instead_of_exiting(self):
        late = self.sensor("iio:device1", 40)
        controller, _find = self.controller([None, None, late])
        self.assertIsNone(controller.sensor)
        self.assertIsNone(controller.sample())
        self.assertEqual(controller.sample(), 40.0)
        self.assertIs(controller.sensor, late)

    def test_vanished_sensor_is_found_again_under_a_new_path(self):
        first = self.sensor("iio:device1", 10)
        controller, find = self.controller([first])
        self.assertEqual(controller.sample(), 10.0)
        os.remove(first.raw)
        second = self.sensor("iio:device2", 10)
        find.side_effect = [None, second]
        self.assertIsNone(controller.sample())
        # Smoothed against the first reading, so 10.000000000000002 can come back.
        self.assertAlmostEqual(controller.sample(), 10.0)
        self.assertIs(controller.sensor, second)

    def test_present_sensor_is_not_rediscovered_every_tick(self):
        sensor = self.sensor("iio:device1", 5)
        controller, find = self.controller([sensor])
        for _ in range(3):
            controller.sample()
        find.assert_called_once()



class CurveTests(unittest.TestCase):
    # Smoothed readings logged on a B9406CAA in a room near 200 lux, one
    # morning: Microsoft's 155-205 / 200-300 overlap is 2.5% wide there, and
    # the keyboard went off and on again with each of these.
    ROOM_NEAR_200_LUX = [199.4, 205.0, 199.4, 206.3, 199.5, 206.9, 199.0,
                         205.2, 199.9, 206.2, 196.9, 205.8, 198.9]

    def levels(self, buckets, readings, hysteresis):
        bucket, out = None, []
        for lux in readings:
            bucket = kbd.select_bucket(buckets, lux, bucket, hysteresis)
            out.append(kbd.pct_to_level(buckets[bucket][2], 3))
        return out

    def changes(self, levels):
        return sum(1 for a, b in zip(levels, levels[1:]) if a != b)

    def test_default_curve_flapped_on_the_overlaps_alone(self):
        buckets = kbd.parse_curve(kbd.DEFAULT_CURVE)
        self.assertGreaterEqual(
            self.changes(self.levels(buckets, self.ROOM_NEAR_200_LUX, 0.0)), 8)

    def test_hysteresis_holds_the_level_in_that_room(self):
        buckets = kbd.parse_curve(kbd.DEFAULT_CURVE)
        hysteresis = kbd.parse_hysteresis(kbd.DEFAULT_HYSTERESIS)
        levels = self.levels(buckets, self.ROOM_NEAR_200_LUX, hysteresis)
        self.assertEqual(self.changes(levels), 0, levels)

    def test_hysteresis_still_follows_a_real_change_of_light(self):
        buckets = kbd.parse_curve(kbd.DEFAULT_CURVE)
        levels = self.levels(buckets, [199.0, 300.0, 120.0, 20.0], 0.10)
        self.assertEqual(levels, [2, 0, 2, 2])
        self.assertEqual(self.levels(buckets, [3.0], 0.10), [1])

    def test_hysteresis_must_be_a_sane_fraction(self):
        self.assertEqual(kbd.parse_hysteresis("0"), 0.0)
        for bad in ("-0.1", "0.8", "lots"):
            with self.assertRaises(ValueError):
                kbd.parse_hysteresis(bad)

    def test_light_keycaps_preset_is_dim_when_dark_and_off_in_daylight(self):
        buckets = kbd.parse_curve(" Light-Keycaps ")
        self.assertEqual(buckets, kbd.parse_curve(kbd.CURVE_PRESETS["light-keycaps"]))
        levels = self.levels(buckets, [2.0, 30.0, 55.0, 70.0, 200.0, 500.0, 50.0, 35.0], 0.10)
        self.assertEqual(levels, [1, 1, 1, 0, 0, 0, 0, 1])

    def test_microsoft_preset_and_explicit_curves_still_parse(self):
        self.assertEqual(kbd.parse_curve("microsoft"), kbd.parse_curve(kbd.DEFAULT_CURVE))
        self.assertEqual(kbd.parse_curve("0:10:50, 5:100:0"), [(0.0, 10.0, 50.0), (5.0, 100.0, 0.0)])
        with self.assertRaises(ValueError):
            kbd.parse_curve("dark-keycaps")


if __name__ == "__main__":
    unittest.main()
