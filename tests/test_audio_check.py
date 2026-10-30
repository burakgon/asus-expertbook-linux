"""The audio-fix pacman check: which kernels it warns about, and when it stays quiet."""

import os
from pathlib import Path
import subprocess
import tempfile
import textwrap
import unittest


CHECK = Path(__file__).resolve().parents[1] / "audio-fix/asus-expertbook-audio-check"
OVERLAY = "asus-expertbook-sof-sdw/3.0.3"


class AudioCheckTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(tmp.name)
        self.modules = self.tmp / "modules"
        self.fake = self.tmp / "fake"
        bindir = self.tmp / "bin"
        for d in (self.modules, self.fake / "soundwire", self.fake / "dkms", bindir):
            d.mkdir(parents=True)

        # modinfo -k <kernel> -n soundwire_intel
        self.tool(bindir / "modinfo", f"""
            echo "{self.fake}/soundwire/$2.ko"
        """)
        # dkms status -m <name> -v <version> -k <kernel>
        self.tool(bindir / "dkms", f"""
            f="{self.fake}/dkms/$7"
            [ -f "$f" ] && cat "$f"
            exit 0
        """)
        self.env = dict(os.environ, PATH=f"{bindir}:{os.environ['PATH']}",
                        AUDIO_CHECK_MODULES_ROOT=str(self.modules))

    @staticmethod
    def tool(path, body):
        path.write_text("#!/bin/sh\n" + textwrap.dedent(body))
        path.chmod(0o755)

    def kernel(self, release, quirk=False, dkms=None, vmlinuz=True):
        d = self.modules / release
        d.mkdir()
        if vmlinuz:
            (d / "vmlinuz").write_bytes(b"")
        if quirk:
            (self.fake / "soundwire" / f"{release}.ko").write_bytes(b"\0dmi B9406CAA\0")
        if dkms:
            (self.fake / "dkms" / release).write_text(
                f"asus-expertbook-sof-sdw/3.0.3, {release}, x86_64: {dkms}\n")

    def run_check(self, *args):
        return subprocess.run(["bash", str(CHECK), *args], env=self.env,
                              capture_output=True, text=True, check=False)

    def test_silent_when_every_kernel_is_covered(self):
        self.kernel("7.3.0-4-cachyos", quirk=True)
        self.kernel("7.2.10-arch1-1", dkms="installed")
        self.kernel("6.18.55-2-cachyos-lts")
        result = self.run_check(OVERLAY)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout + result.stderr, "")

    def test_names_a_kernel_whose_build_failed(self):
        self.kernel("7.3.0-4-cachyos", quirk=True)
        self.kernel("7.2.10-arch1-1", dkms="added")
        result = self.run_check(OVERLAY)
        self.assertEqual(result.returncode, 0)
        self.assertIn("WARNING", result.stdout)
        self.assertIn("      7.2.10-arch1-1\n", result.stdout)
        self.assertNotIn("7.3.0-4-cachyos", result.stdout)
        self.assertIn("/var/lib/dkms/asus-expertbook-sof-sdw/3.0.3/build/make.log", result.stdout)

    def test_7_2_11_needs_the_overlay_even_with_the_quirk(self):
        self.kernel("7.2.11-arch1-1", quirk=True)
        self.assertIn("      7.2.11-arch1-1\n", self.run_check(OVERLAY).stdout)

    def test_ignores_a_removed_kernels_leftover_directory(self):
        self.kernel("7.2.9-arch1-1", vmlinuz=False)
        self.assertEqual(self.run_check(OVERLAY).stdout, "")

    def test_bad_arguments_are_silent_and_succeed(self):
        self.kernel("7.2.10-arch1-1")
        for args in ((), ("asus-expertbook-sof-sdw",), ("/3.0.3",)):
            result = self.run_check(*args)
            self.assertEqual((result.returncode, result.stdout), (0, ""), args)

    def test_sourcing_defines_the_rules_without_running_the_check(self):
        self.kernel("7.2.10-arch1-1")
        result = subprocess.run(
            ["bash", "-c", 'source "$1"; audio_kernel_predates_card 6.18.55-lts && '
             '! audio_kernel_predates_card 6.19.0 && echo ok', "_", str(CHECK)],
            env=self.env, capture_output=True, text=True, check=False)
        self.assertEqual(result.stdout, "ok\n")


if __name__ == "__main__":
    unittest.main()
