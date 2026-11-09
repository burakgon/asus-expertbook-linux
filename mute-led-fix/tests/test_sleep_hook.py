"""Run the systemd-sleep hook against fake LED class directories."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest


HOOK = Path(__file__).parents[1] / "sleep-hook.sh"
TRIGGERS = "none kbd-capslock audio-mute audio-micmute"


class SleepHookTests(unittest.TestCase):
    def setUp(self):
        self._dir = tempfile.TemporaryDirectory()
        self.leds = Path(self._dir.name)

    def tearDown(self):
        self._dir.cleanup()

    def led(self, name, selected, brightness):
        directory = self.leds / name
        directory.mkdir()
        listing = " ".join(f"[{t}]" if t == selected else t for t in TRIGGERS.split())
        (directory / "trigger").write_text(listing + "\n")
        (directory / "brightness").write_text(f"{brightness}\n")
        # A real trigger file records each write; a plain file keeps only the last.
        return directory

    def run_hook(self, *args):
        return subprocess.run(
            ["sh", str(HOOK), *args], capture_output=True, text=True, check=True,
            env=dict(os.environ, MUTE_LED_SYSFS=str(self.leds)))

    def test_hibernate_resume_reattaches_each_audio_trigger(self):
        speaker = self.led("platform::mute", "audio-mute", 1)
        mic = self.led("platform::micmute", "audio-micmute", 0)
        self.run_hook("post", "hibernate")
        self.assertEqual((speaker / "trigger").read_text(), "audio-mute\n")
        self.assertEqual((mic / "trigger").read_text(), "audio-micmute\n")
        # Brightness comes from the kernel trigger, not from the hook.
        self.assertEqual((speaker / "brightness").read_text(), "1\n")
        self.assertEqual((mic / "brightness").read_text(), "0\n")

    def test_led_without_a_trigger_gets_its_value_written_back(self):
        speaker = self.led("platform::mute", "none", 1)
        (speaker / "brightness").write_text("1")  # no newline: proves a rewrite
        self.run_hook("post", "hybrid-sleep")
        self.assertEqual((speaker / "brightness").read_text(), "1\n")
        self.assertIn("[none]", (speaker / "trigger").read_text())

    def test_suspend_then_hibernate_resume_is_handled(self):
        speaker = self.led("platform::mute", "audio-mute", 0)
        self.run_hook("post", "suspend-then-hibernate")
        self.assertEqual((speaker / "trigger").read_text(), "audio-mute\n")

    def test_plain_suspend_and_pre_phase_change_nothing(self):
        speaker = self.led("platform::mute", "audio-mute", 1)
        before = (speaker / "trigger").read_text()
        self.run_hook("post", "suspend")
        self.run_hook("pre", "hibernate")
        self.assertEqual((speaker / "trigger").read_text(), before)

    def test_missing_led_is_skipped(self):
        mic = self.led("platform::micmute", "audio-micmute", 1)
        self.run_hook("post", "hibernate")
        self.assertEqual((mic / "trigger").read_text(), "audio-micmute\n")


if __name__ == "__main__":
    unittest.main()
